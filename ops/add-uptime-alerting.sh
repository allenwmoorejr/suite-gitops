#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

NS="observe"

mkdir -p apps/observe/monitoring apps/observe/uptime clusters/home/apps/observe ops

# ---------------------------
# observe: monitoring stack
# ---------------------------
cat > apps/observe/monitoring/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrepo-prometheus-community.yaml
  - helmrelease-kube-prometheus-stack.yaml
YAML

cat > apps/observe/monitoring/namespace.yaml <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: observe
YAML

cat > apps/observe/monitoring/helmrepo-prometheus-community.yaml <<'YAML'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: observe
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
YAML

# kube-prometheus-stack release (minimal/noisy bits off for K3s)
# Chart versions move fast; using a semver range keeps it stable within major.
# Example tag seen recently: kube-prometheus-stack-80.13.3 :contentReference[oaicite:1]{index=1}
cat > apps/observe/monitoring/helmrelease-kube-prometheus-stack.yaml <<'YAML'
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: observe
spec:
  interval: 30m
  timeout: 15m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: ">=80.0.0 <81.0.0"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: observe
  install:
    createNamespace: true
    crds: CreateReplace
  upgrade:
    crds: CreateReplace
  values:
    # Keep it quiet on K3s (those components often aren't scrapeable like vanilla kubeadm)
    kubeEtcd:
      enabled: false
    kubeControllerManager:
      enabled: false
    kubeScheduler:
      enabled: false
    kubeProxy:
      enabled: false

    # Avoid a wall of default alerts until you want them
    defaultRules:
      create: false

    grafana:
      enabled: true
      # change later if you want; this is just to get you in fast
      adminPassword: "changeme-now"
      service:
        type: ClusterIP

    alertmanager:
      enabled: true

    prometheus:
      prometheusSpec:
        retention: 7d
        # IMPORTANT: allow Prometheus to pick up ServiceMonitors/Rules we create in other releases
        # (These fields are commonly used with kube-prometheus-stack to avoid strict label matching.) :contentReference[oaicite:2]{index=2}
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false
        probeSelectorNilUsesHelmValues: false
        ruleSelectorNilUsesHelmValues: false
YAML

# ---------------------------
# observe: uptime probes + alerts (blackbox)
# ---------------------------
cat > apps/observe/uptime/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease-blackbox.yaml
YAML

# Blackbox chart supports targets + ServiceMonitor + PrometheusRule out of the box. 
cat > apps/observe/uptime/helmrelease-blackbox.yaml <<'YAML'
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: blackbox-exporter
  namespace: observe
spec:
  interval: 15m
  timeout: 10m
  dependsOn:
    - name: kube-prometheus-stack
      namespace: observe
  chart:
    spec:
      chart: prometheus-blackbox-exporter
      version: ">=5.8.0 <6.0.0"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: observe
  install:
    createNamespace: true
  values:
    # Keep modules explicit so behavior is predictable
    config:
      modules:
        http_2xx:
          prober: http
          timeout: 10s
          http:
            method: GET
            valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
            preferred_ip_protocol: "ip4"

    serviceMonitor:
      enabled: true
      defaults:
        module: http_2xx
        interval: 30s
        scrapeTimeout: 10s

    targets:
      - name: command-center-ui
        url: https://command-center.allenwmoorejr.org/
      - name: command-center-api-healthz
        url: https://command-center.allenwmoorejr.org/healthz
      - name: command-center-api-sensors
        url: https://command-center.allenwmoorejr.org/v1/iot/sensors

    prometheusRule:
      enabled: true
      rules:
        - alert: CommandCenterEndpointDown
          expr: probe_success{instance=~"https://command-center\\.allenwmoorejr\\.org.*"} == 0
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Command Center endpoint down"
            description: "Probe failed for {{ $labels.instance }}"

        - alert: CommandCenterEndpointSlow
          expr: probe_duration_seconds{instance=~"https://command-center\\.allenwmoorejr\\.org.*"} > 2
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Command Center endpoint slow"
            description: "{{ $labels.instance }} latency is {{ $value }}s"
YAML

# ---------------------------
# Wire into clusters/home/apps
# ---------------------------
cat > clusters/home/apps/observe/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../apps/observe/monitoring
  - ../../../../apps/observe/uptime
YAML

# Ensure clusters/home/apps/kustomization.yaml includes "observe"
if [ ! -f clusters/home/apps/kustomization.yaml ]; then
  cat > clusters/home/apps/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - suite
  - observe
YAML
else
  if ! grep -qE '^\s*-\s*observe\s*$' clusters/home/apps/kustomization.yaml; then
    # append under resources (simple + safe)
    echo "  - observe" >> clusters/home/apps/kustomization.yaml
  fi
fi

echo "✅ Wrote monitoring + uptime resources under apps/observe and wired into clusters/home/apps."
echo "Next: git add/commit/push + flux reconcile."
