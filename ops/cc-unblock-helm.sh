#!/usr/bin/env bash
set -euo pipefail

NS="suite"
REL="suite-command-center"
CHART="apps/suite/command-center/chart"

echo "== 0) Sanity: Helm render duplicate IDs (should print NOTHING) =="
helm template "$REL" "$CHART" -n "$NS" \
  | awk '/^kind: /{k=$2} /^  name: /{print k,$2}' \
  | sort | uniq -c | awk '$1>1{print "DUP:",$0}' || true
echo

echo "== 1) If any cluster-scoped RBAC already exists, delete it (common Helm blocker) =="
kubectl get clusterrolebinding suite-command-center-readonly >/dev/null 2>&1 && \
  kubectl delete clusterrolebinding suite-command-center-readonly || true
kubectl get clusterrole suite-command-center-readonly >/dev/null 2>&1 && \
  kubectl delete clusterrole suite-command-center-readonly || true
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
flux reconcile source git flux-system -n flux-system --timeout=5m
flux reconcile helmrelease "$REL" -n "$NS" --with-source --timeout=15m

echo
echo "== 5) Quick status =="
kubectl -n "$NS" get helmrelease "$REL" -o wide || true
kubectl -n "$NS" get deploy,po,svc -o wide | egrep -i 'command-center|NAME' || true

echo
echo "== 6) Endpointslices (should NOT be empty once pods exist) =="
kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=suite-command-center-ui -o wide || true
kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=suite-command-center-api -o wide || true
