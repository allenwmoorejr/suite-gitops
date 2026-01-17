#!/usr/bin/env bash
set -euo pipefail

NS="traefik"
SEL='app.kubernetes.io/name=traefik'

DEPLOY="$(kubectl -n "$NS" get deploy -l "$SEL" -o jsonpath='{.items[0].metadata.name}')"
echo "Patching deployment $NS/$DEPLOY to enable dashboard/api..."

kubectl -n "$NS" patch deploy "$DEPLOY" --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--api.dashboard=true"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--api=true"}
]'
echo "Restarting rollout..."
kubectl -n "$NS" rollout restart deploy "$DEPLOY"
kubectl -n "$NS" rollout status deploy "$DEPLOY" --timeout=180s

echo
echo "Done. Now apply the IngressRoute for api@internal (if you haven't) and test /api/http/routers."
