#!/usr/bin/env bash
set -euo pipefail

NS="suite"
SECRET="command-center-tls"

echo "== Secret exists? =="
kubectl -n "$NS" get secret "$SECRET" -o wide
echo

echo "== Secret type =="
kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.type}{"\n"}'
echo

echo "== Decode and show cert Subject + SANs =="
kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.crt}' \
| base64 -d \
| openssl x509 -noout -subject -issuer -dates -ext subjectAltName || true
echo
