#!/usr/bin/env bash
set -euo pipefail

NS="suite"
REL="suite-command-center"
CHART="apps/suite/command-center/chart"
OUT="/tmp/cc.final.yaml"

echo "== helm template -> $OUT =="
helm template "$REL" "$CHART" -n "$NS" > "$OUT"

echo "wrote: $OUT"
echo "== head (sanity) =="
nl -ba "$OUT" | sed -n '1,20p'
