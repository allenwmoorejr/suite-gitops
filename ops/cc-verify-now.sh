#!/usr/bin/env bash
set -euo pipefail

echo "== HelmRelease status =="
kubectl -n suite get helmrelease suite-command-center -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.reason}{"\t"}{.message}{"\n"}{end}' || true
echo

echo "== Deployments (command-center) =="
kubectl -n suite get deploy -o wide | egrep -i 'command-center|NAME' || true
echo

echo "== Pods (command-center) =="
kubectl -n suite get pods -o wide | egrep -i 'command-center|NAME' || true
echo

echo "== Services =="
kubectl -n suite get svc -o wide | egrep -i 'suite-command-center|NAME' || true
echo

echo "== EndpointSlices (should NOT be empty if pods exist) =="
kubectl -n suite get endpointslice -l kubernetes.io/service-name=suite-command-center-ui -o wide || true
kubectl -n suite get endpointslice -l kubernetes.io/service-name=suite-command-center-api -o wide || true
echo

echo "== Traefik routers containing command-center (rawdata) =="
if curl -fsS http://127.0.0.1:8080/api/rawdata >/dev/null 2>&1; then
  curl -s http://127.0.0.1:8080/api/rawdata | jq -r '.routers | keys[] | select(test("command-center"))' || true
else
  echo "Traefik dashboard API not reachable on 127.0.0.1:8080 (port-forward may be missing)."
fi
