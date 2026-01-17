#!/usr/bin/env bash
set -euo pipefail

NS="traefik"
SEL='app.kubernetes.io/name=traefik'

POD="$(kubectl -n "$NS" get pod -l "$SEL" -o jsonpath='{.items[0].metadata.name}')"
echo "Using POD=$POD"
echo "Forwarding http://127.0.0.1:8080 -> $NS/$POD:8080"
echo "Leave this running."
kubectl -n "$NS" port-forward "$POD" 8080:8080
