#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

mkdir -p ops/ansible/{playbooks,bin,artifacts}

# --- bootstrap ---
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

# --- ansible.cfg (picked up via ANSIBLE_CONFIG in run script) ---
cat > ops/ansible/ansible.cfg <<'EOF'
[defaults]
inventory = ops/ansible/inventory.ini
stdout_callback = yaml
retry_files_enabled = False
host_key_checking = False
nocows = 1
timeout = 30
interpreter_python = auto_silent

[privilege_escalation]
become = False
EOF

# --- inventory (force bash so pipefail works) ---
cat > ops/ansible/inventory.ini <<'EOF'
[local]
localhost ansible_connection=local ansible_shell_executable=/bin/bash
EOF

# --- playbook ---
cat > ops/ansible/playbooks/fix_flux_source_controller.yml <<'EOF'
---
- name: Fix Flux source-controller connectivity and unblock HelmReleases
  hosts: local
  gather_facts: false

  vars:
    ns: flux-system
    sc_label: "app=source-controller"
    sc_svc: source-controller
    sc_deploy: source-controller
    probe_image: "curlimages/curl:8.6.0"
    prefer_alt_node: "w7"

  tasks:
    - name: Sanity check kubectl access
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl version --client=true --short
        kubectl get ns {{ ns }} >/dev/null
      args:
        executable: /bin/bash
      changed_when: false

    - name: Discover source-controller pod/ip/node
      ansible.builtin.shell: |
        set -euo pipefail
        POD="$(kubectl -n {{ ns }} get pod -l {{ sc_label }} -o jsonpath='{.items[0].metadata.name}')"
        IP="$(kubectl -n {{ ns }} get pod "$POD" -o jsonpath='{.status.podIP}')"
        NODE="$(kubectl -n {{ ns }} get pod "$POD" -o jsonpath='{.spec.nodeName}')"
        echo "pod=$POD ip=$IP node=$NODE"
      args:
        executable: /bin/bash
      register: sc_ident
      changed_when: false

    - name: Set facts
      ansible.builtin.set_fact:
        sc_pod: "{{ sc_ident.stdout | regex_search('pod=([^ ]+)', '\\1') }}"
        sc_pod_ip: "{{ sc_ident.stdout | regex_search('ip=([^ ]+)', '\\1') }}"
        sc_node: "{{ sc_ident.stdout | regex_search('node=([^ ]+)', '\\1') }}"

    - name: Show service and endpointslice
      ansible.builtin.shell: |
        set -euo pipefail
        echo "== svc =="
        kubectl -n {{ ns }} get svc {{ sc_svc }} -o wide
        echo
        echo "== endpointslice =="
        kubectl -n {{ ns }} get endpointslice -l kubernetes.io/service-name={{ sc_svc }} -o yaml | sed -n '1,220p'
      args:
        executable: /bin/bash
      changed_when: false

    - name: Force Service port 80 -> targetPort http (9090)
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl -n {{ ns }} patch svc {{ sc_svc }} --type merge -p \
          '{"spec":{"ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":"http"}]}}'
      args:
        executable: /bin/bash

    - name: Restart source-controller
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl -n {{ ns }} rollout restart deploy/{{ sc_deploy }}
        kubectl -n {{ ns }} rollout status deploy/{{ sc_deploy }} --timeout=180s
      args:
        executable: /bin/bash

    - name: Decide alternate node for cross-node probe
      ansible.builtin.set_fact:
        alt_node: "{{ prefer_alt_node if sc_node != prefer_alt_node else 'w0' }}"

    - name: Create probe pods (PSA restricted-safe)
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl -n {{ ns }} delete pod sc-probe-same sc-probe-alt --ignore-not-found >/dev/null 2>&1 || true

        cat <<'YAML' | sed \
          -e "s/__NS__/{{ ns }}/g" \
          -e "s/__SAME_NODE__/{{ sc_node }}/g" \
          -e "s/__ALT_NODE__/{{ alt_node }}/g" \
          -e "s/__POD_IP__/{{ sc_pod_ip }}/g" \
          -e "s#__IMAGE__#{{ probe_image }}#g" \
        | kubectl apply -f -
        apiVersion: v1
        kind: Pod
        metadata:
          name: sc-probe-same
          namespace: __NS__
        spec:
          restartPolicy: Never
          nodeName: __SAME_NODE__
          containers:
          - name: curl
            image: __IMAGE__
            command: ["sh","-lc"]
            args:
              - |
                set +e
                echo "NODE=$(cat /etc/hostname)"
                echo "== SVC (80) =="
                curl -sv --max-time 3 http://source-controller.__NS__.svc.cluster.local/healthz -o /dev/null
                echo
                echo "== POD (9090) __POD_IP__ =="
                curl -sv --max-time 3 http://__POD_IP__:9090/healthz -o /dev/null
                echo
                echo "== HEALTHZ (9440) __POD_IP__ =="
                curl -sv --max-time 3 http://__POD_IP__:9440/healthz -o /dev/null
                echo "DONE"
            securityContext:
              allowPrivilegeEscalation: false
              runAsNonRoot: true
              runAsUser: 65532
              capabilities: { drop: ["ALL"] }
              seccompProfile: { type: RuntimeDefault }
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: sc-probe-alt
          namespace: __NS__
        spec:
          restartPolicy: Never
          nodeName: __ALT_NODE__
          containers:
          - name: curl
            image: __IMAGE__
            command: ["sh","-lc"]
            args:
              - |
                set +e
                echo "NODE=$(cat /etc/hostname)"
                echo "== SVC (80) =="
                curl -sv --max-time 3 http://source-controller.__NS__.svc.cluster.local/healthz -o /dev/null
                echo
                echo "== POD (9090) __POD_IP__ =="
                curl -sv --max-time 3 http://__POD_IP__:9090/healthz -o /dev/null
                echo
                echo "== HEALTHZ (9440) __POD_IP__ =="
                curl -sv --max-time 3 http://__POD_IP__:9440/healthz -o /dev/null
                echo "DONE"
            securityContext:
              allowPrivilegeEscalation: false
              runAsNonRoot: true
              runAsUser: 65532
              capabilities: { drop: ["ALL"] }
              seccompProfile: { type: RuntimeDefault }
        YAML

        kubectl -n {{ ns }} wait --for=condition=PodScheduled pod/sc-probe-same --timeout=30s || true
        kubectl -n {{ ns }} wait --for=condition=PodScheduled pod/sc-probe-alt  --timeout=30s || true
        sleep 2
      args:
        executable: /bin/bash

    - name: Print probe logs
      ansible.builtin.shell: |
        set -euo pipefail
        for NAME in sc-probe-same sc-probe-alt; do
          echo "----- logs $NAME -----"
          kubectl -n {{ ns }} logs "$NAME" || true
          echo
        done
      args:
        executable: /bin/bash
      register: probe_logs
      changed_when: false

    - name: Show probe logs
      ansible.builtin.debug:
        msg: "{{ probe_logs.stdout }}"

    - name: Cleanup probe pods
      ansible.builtin.shell: |
        set -euo pipefail
        kubectl -n {{ ns }} delete pod sc-probe-same sc-probe-alt --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
      args:
        executable: /bin/bash
      changed_when: false
EOF

# --- runner (forces ansible.cfg to be used) ---
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
export ANSIBLE_CONFIG="$ROOT/ops/ansible/ansible.cfg"

ansible-playbook -i "$ROOT/ops/ansible/inventory.ini" \
  "$ROOT/ops/ansible/playbooks/fix_flux_source_controller.yml" \
  "$@"
EOF
chmod +x ops/ansible/bin/run-fix-flux-source.sh

# --- gitignore (optional) ---
touch .gitignore
grep -q '^\./\.venv-ansible/$' .gitignore 2>/dev/null || cat >> .gitignore <<'EOF'
./.venv-ansible/
ops/ansible/artifacts/
*.retry
EOF

echo "✅ Rebuilt ops/ansible files."
echo "Next:"
echo "  bash ops/ansible/bootstrap.sh"
echo "  ops/ansible/bin/run-fix-flux-source.sh"
