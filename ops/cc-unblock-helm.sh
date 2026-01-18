#!/usr/bin/env bash
set -euo pipefail

NS="suite"
REL="suite-command-center"
CHART="apps/suite/command-center/chart"

echo "== 0) Sanity: Helm render duplicate IDs (should print NOTHING) =="
HELM_RENDER="$(helm template "$REL" "$CHART" -n "$NS" --debug 2>&1)"
HELM_STATUS=$?
if [ "$HELM_STATUS" -ne 0 ]; then
  echo "ERROR: helm template failed; cannot check for duplicate IDs."
  echo "$HELM_RENDER"
  exit 1
fi

DUPES="$(printf '%s\n' "$HELM_RENDER" \
  | awk '/^kind: /{k=$2} /^  name: /{print k,$2}' \
  | sort | uniq -c | awk '$1>1{print "DUP:",$0}')"
if [ -n "$DUPES" ]; then
  echo "$DUPES"
  echo
  echo "ERROR: Duplicate Kubernetes IDs detected in Helm render."
  echo "       This usually means backup files are being rendered."
  echo "       Run ops/fix-command-center-helm-duplicate-templates.sh and re-run."
  echo
  echo "Details (duplicate resources with source files):"
  printf '%s\n' "$HELM_RENDER" \
    | awk '
        /^# Source: /{source=$3}
        /^kind: /{kind=$2}
        /^  name: /{
          name=$2
          if (kind != "" && source != "") {
            key=kind" "name
            count[key]++
            sources[key]=(sources[key] ? sources[key] ", " : "") source
          }
        }
        END {
          for (k in count) {
            if (count[k] > 1) {
              print " - " k " -> " sources[k]
            }
          }
        }'
  exit 1
fi
echo

echo "== 1) If any cluster-scoped RBAC already exists, delete it (common Helm blocker) =="
RBAC_NAME="${REL}-${NS}-readonly"
if [ "${#RBAC_NAME}" -gt 63 ]; then
  RBAC_NAME="${RBAC_NAME:0:63}"
fi
RBAC_NAME="${RBAC_NAME%-}"

kubectl get clusterrolebinding "$RBAC_NAME" >/dev/null 2>&1 && \
  kubectl delete clusterrolebinding "$RBAC_NAME" || true
kubectl get clusterrole "$RBAC_NAME" >/dev/null 2>&1 && \
  kubectl delete clusterrole "$RBAC_NAME" || true
echo "done"
echo

echo "== 2) Delete any leftover namespaced objects that might conflict =="
kubectl -n "$NS" delete deploy \
  suite-command-center-ui suite-command-center-api \
  --ignore-not-found

kubectl -n "$NS" delete svc \
  suite-command-center-ui suite-command-center-api suite-command-center-api-shim \
  --ignore-not-found

kubectl -n "$NS" delete sa \
  suite-command-center-api suite-command-center-ui \
  --ignore-not-found
echo "done"
echo

echo "== 3) Delete any stale Helm release secrets for this release (rare, but nasty) =="
kubectl -n "$NS" get secret -o name \
  | grep -E "^secret/sh\\.helm\\.release\\.v1\\.${REL}\\." \
  | xargs -r kubectl -n "$NS" delete
echo "done"
echo

echo "== 4) Reconcile with a real timeout (Flux waits can time out even when retries are ongoing) =="
echo "== 4a) Quick Flux source-controller check (service port + endpoints) =="
if kubectl -n flux-system get svc source-controller >/dev/null 2>&1; then
  SVC_PORT="$(kubectl -n flux-system get svc source-controller -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo UNKNOWN)"
  if [ "$SVC_PORT" != "9090" ]; then
    echo "WARN: flux-system/source-controller service targetPort is '$SVC_PORT' (expected 9090)."
    echo "      Run ops/ansible/bin/run-fix-flux-source.sh to patch + restart source-controller."
  fi

  ENDPOINT_IP="$(kubectl -n flux-system get endpointslice -l kubernetes.io/service-name=source-controller -o jsonpath='{.items[0].endpoints[0].addresses[0]}' 2>/dev/null || echo NONE)"
  if [ "$ENDPOINT_IP" = "NONE" ]; then
    echo "WARN: no endpoints found for source-controller; reconcile requests may time out."
  fi
else
  echo "WARN: flux-system/source-controller service not found."
fi

if ! flux reconcile source git flux-system -n flux-system --timeout=5m; then
  echo "ERROR: flux source reconcile failed."
  echo "== source-controller logs (last 5m) =="
  kubectl -n flux-system logs deploy/source-controller --since=5m || true
  exit 1
fi

if ! flux reconcile helmrelease "$REL" -n "$NS" --with-source --timeout=15m; then
  echo "ERROR: flux helmrelease reconcile failed."
  echo "== helmrelease status =="
  kubectl -n "$NS" get helmrelease "$REL" -o wide || true
  kubectl -n "$NS" describe helmrelease "$REL" || true
  echo
  echo "== helm-controller logs (last 10m) =="
  kubectl -n flux-system logs deploy/helm-controller --since=10m || true
  exit 1
fi

echo
echo "== 5) Quick status =="
kubectl -n "$NS" get helmrelease "$REL" -o wide || true
kubectl -n "$NS" get deploy,po,svc -o wide | egrep -i 'command-center|NAME' || true

echo
echo "== 6) Endpointslices (should NOT be empty once pods exist) =="
kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=suite-command-center-ui -o wide || true
kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=suite-command-center-api -o wide || true
