#!/usr/bin/env bash
set -euo pipefail

echo "== Find traefik pod(s) =="
kubectl -n traefik get pods -o wide

POD="$(kubectl -n traefik get pod -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')"
echo
echo "Using POD=$POD"
echo

echo "== Port-forward traefik dashboard/api to localhost:9000 =="
echo "Leave this running; open a new terminal for curl commands."
kubectl -n traefik port-forward "$POD" 9000:9000
