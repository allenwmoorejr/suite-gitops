#!/usr/bin/env bash
set -euo pipefail

NS_TRAEFIK="traefik"
NS_APP="suite"

echo "== 1) Command-center IngressRoutes exist? =="
kubectl -n "$NS_APP" get ingressroute | egrep -i 'command-center|NAME' || true
echo

echo "== 2) Show the exact IngressRoute specs (external) =="
for r in command-center-external-ui command-center-external-api; do
  echo "-- $r --"
  kubectl -n "$NS_APP" get ingressroute "$r" -o yaml | sed -n '1,220p' || true
  echo
done

echo "== 3) Services exist? =="
kubectl -n "$NS_APP" get svc | egrep -i 'suite-command-center-(ui|api)|NAME' || true
echo

echo "== 4) Traefik sees ANY command-center routers? (rawdata) =="
# assumes you already have port-forward to 127.0.0.1:8080 -> traefik:8080
if ! curl -fsS http://127.0.0.1:8080/api/rawdata >/dev/null; then
  echo "ERROR: cannot reach http://127.0.0.1:8080/api/rawdata"
  echo "Make sure: kubectl -n traefik port-forward pod/<traefik-pod> 8080:8080"
  exit 1
fi

curl -s http://127.0.0.1:8080/api/rawdata \
| jq -r '.routers | keys[] | select(test("command-center"))' || true
echo

echo "== 5) Traefik logs mentioning command-center / kubernetescrd errors (last 30m) =="
kubectl -n "$NS_TRAEFIK" logs deploy/traefik --since=30m \
| egrep -i 'command-center|ingressroute|kubernetescrd|error|warn|middleware|service' \
| tail -n 250 || true
echo

echo "== 6) RBAC: can Traefik SA list IngressRoutes in suite? =="
SA="system:serviceaccount:${NS_TRAEFIK}:traefik"
kubectl auth can-i list ingressroutes.traefik.io -n "$NS_APP" --as="$SA" || true
kubectl auth can-i get ingressroutes.traefik.io -n "$NS_APP" --as="$SA" || true
echo
