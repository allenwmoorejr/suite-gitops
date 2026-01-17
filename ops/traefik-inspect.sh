#!/usr/bin/env bash
set -euo pipefail

NS="traefik"
SEL='app.kubernetes.io/name=traefik'

echo "== Pods =="
kubectl -n "$NS" get pods -l "$SEL" -o wide
echo

DEPLOY="$(kubectl -n "$NS" get deploy -l "$SEL" -o jsonpath='{.items[0].metadata.name}')"
echo "== Deploy: $DEPLOY =="
kubectl -n "$NS" get deploy "$DEPLOY" -o yaml | sed -n '1,220p'
echo

POD="$(kubectl -n "$NS" get pod -l "$SEL" -o jsonpath='{.items[0].metadata.name}')"
echo "== Pod container ports =="
kubectl -n "$NS" get pod "$POD" -o jsonpath='{range .spec.containers[0].ports[*]}{.name}{"\t"}{.containerPort}{"\n"}{end}'
echo

echo "== Args (one per line) =="
kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].args}' \
| tr ' ' '\n' | sed '/^$/d'
echo
