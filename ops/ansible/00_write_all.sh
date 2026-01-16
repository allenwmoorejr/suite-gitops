#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

mkdir -p ops/ansible/{playbooks,bin,artifacts}

cat > ops/ansible/bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

sudo apt-get update -y
sudo apt-get install -y python3-venv python3-pip jq

VENV="$ROOT/.venv-ansible"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi

# shellcheck disable=SC1090
source "$VENV/bin/activate"

pip install -U pip
pip install -U ansible-core

ansible-playbook --version | head -n 2
EOF
chmod +x ops/ansible/bootstrap.sh

cat > ops/ansible/ansible.cfg <<'EOF'
[defaults]
inventory = ops/ansible/inventory.ini
stdout_callback = default
retry_files_enabled = False
host_key_checking = False
nocows = 1
timeout = 30
interpreter_python = auto_silent
EOF

cat > ops/ansible/inventory.ini <<'EOF'
[local]
localhost ansible_connection=local ansible_shell_executable=/bin/bash
EOF

cat > ops/ansible/bin/run-fix-flux-source.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

VENV="$ROOT/.venv-ansible"
if [ ! -d "$VENV" ]; then
  echo "Missing venv: $VENV"
  echo "Run: bash ops/ansible/bootstrap.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "$VENV/bin/activate"

ansible-playbook -i ops/ansible/inventory.ini ops/ansible/playbooks/fix_flux_source_controller.yml
EOF
chmod +x ops/ansible/bin/run-fix-flux-source.sh

cat > ops/ansible/playbooks/fix_flux_source_controller.yml <<'EOF'
---
- name: Fix Flux source-controller service wiring + run probes
  hosts: local
  gather_facts: false

  vars:
    ns: flux-system
    svc: source-controller
    deploy: source-controller
    artifacts_dir: ops/ansible/artifacts

  tasks:
    - name: Ensure artifacts directory exists
      ansible.builtin.file:
        path: "{{ artifacts_dir }}"
        state: directory
        mode: "0755"

    - name: Sanity check kubectl access
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl version --client=true
      args:
        executable: /bin/bash

    - name: Discover source-controller pod + ip + node
      ansible.builtin.shell: |
        set -euo pipefail
        POD="$(kubectl -n "{{ ns }}" get pod -l app={{ svc }} -o jsonpath='{.items[0].metadata.name}')"
        PIP="$(kubectl -n "{{ ns }}" get pod "$POD" -o jsonpath='{.status.podIP}')"
        NODE="$(kubectl -n "{{ ns }}" get pod "$POD" -o jsonpath='{.spec.nodeName}')"
        echo "pod=$POD"
        echo "podIP=$PIP"
        echo "node=$NODE"
      args:
        executable: /bin/bash
      register: sc_info

    - name: Set facts
      ansible.builtin.set_fact:
        sc_pod: "{{ (sc_info.stdout_lines | select('match','^pod=') | list | first) | regex_replace('^pod=','') }}"
        sc_ip: "{{ (sc_info.stdout_lines | select('match','^podIP=') | list | first) | regex_replace('^podIP=','') }}"
        sc_node: "{{ (sc_info.stdout_lines | select('match','^node=') | list | first) | regex_replace('^node=','') }}"

    - name: Patch Service to Flux default (port 80 -> targetPort 9090)
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl -n "{{ ns }}" patch svc "{{ svc }}" --type merge -p \
          '{"spec":{"ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":9090}]}}'
      args:
        executable: /bin/bash

    - name: Restart source-controller
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl -n "{{ ns }}" rollout restart deploy/"{{ deploy }}"
        kubectl -n "{{ ns }}" rollout status deploy/"{{ deploy }}" --timeout=180s
      args:
        executable: /bin/bash

    - name: Refresh endpointslice if it doesn't match podIP
      ansible.builtin.shell: |
        set -euo pipefail
        EIP="$(kubectl -n "{{ ns }}" get endpointslice -l kubernetes.io/service-name="{{ svc }}" -o jsonpath='{.items[0].endpoints[0].addresses[0]}' 2>/dev/null || echo NONE)"
        echo "endpointIP=$EIP podIP={{ sc_ip }}"
        if [ "$EIP" != "{{ sc_ip }}" ] && [ "$EIP" != "NONE" ]; then
          kubectl -n "{{ ns }}" delete endpointslice -l kubernetes.io/service-name="{{ svc }}"
          kubectl -n "{{ ns }}" delete endpoints "{{ svc }}" 2>/dev/null || true
        fi
      args:
        executable: /bin/bash

    - name: Run PSA-safe probe on same node as source-controller
      ansible.builtin.shell: |
        set -euo pipefail
        NS="{{ ns }}"
        SVC="{{ svc }}"
        PIP="{{ sc_ip }}"
        NODE="{{ sc_node }}"
        NAME="sc-probe-ansible"

        kubectl -n "$NS" delete pod "$NAME" --force --grace-period=0 >/dev/null 2>&1 || true

        cat <<YAML | kubectl apply -f -
        apiVersion: v1
        kind: Pod
        metadata:
          name: ${NAME}
          namespace: ${NS}
        spec:
          nodeName: ${NODE}
          restartPolicy: Never
          containers:
          - name: curl
            image: curlimages/curl:8.6.0
            command: ["sh","-lc"]
            args:
              - |
                set -eu
                echo "== service =="
                curl -sv --max-time 3 http://${SVC}.${NS}.svc.cluster.local/ -o /dev/null || true
                curl -sv --max-time 3 http://${SVC}.${NS}.svc.cluster.local/healthz -o /dev/null || true
                echo
                echo "== direct podIP =="
                curl -sv --max-time 3 http://${PIP}:9090/ -o /dev/null || true
                curl -sv --max-time 3 http://${PIP}:8080/metrics -o /dev/null || true
                curl -svk --max-time 3 https://${PIP}:9440/healthz -o /dev/null || true
                curl -sv --max-time 3 http://${PIP}:9440/healthz -o /dev/null || true
            securityContext:
              allowPrivilegeEscalation: false
              runAsNonRoot: true
              runAsUser: 65532
              capabilities: { drop: ["ALL"] }
              seccompProfile: { type: RuntimeDefault }
        YAML

        # wait for completion
        for i in $(seq 1 40); do
          PHASE="$(kubectl -n "$NS" get pod "$NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo NA)"
          [ "$PHASE" = "Succeeded" ] && break
          [ "$PHASE" = "Failed" ] && break
          sleep 2
        done

        kubectl -n "$NS" logs "$NAME" || true
        kubectl -n "$NS" delete pod "$NAME" --force --grace-period=0 >/dev/null 2>&1 || true
      args:
        executable: /bin/bash
EOF

# .gitignore helpers (optional but keeps repo clean)
touch .gitignore
grep -q '^\.venv-ansible/$' .gitignore || cat >> .gitignore <<'EOF'

.venv-ansible/
ops/ansible/artifacts/
*.retry
EOF

echo "✅ Wrote ops/ansible/* files"
echo "Next:"
echo "  bash ops/ansible/bootstrap.sh"
echo "  ops/ansible/bin/run-fix-flux-source.sh"
