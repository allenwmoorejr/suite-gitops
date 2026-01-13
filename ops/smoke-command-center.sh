#!/usr/bin/env bash
set -euo pipefail

BASE="https://command-center.allenwmoorejr.org"

echo "== UI (HEAD) =="
curl -skI "$BASE/" | head -n 12
echo

echo "== API health (GET) =="
curl -sk "$BASE/healthz"; echo
echo

echo "== Sensors (GET) =="
curl -sk "$BASE/v1/iot/sensors"; echo
