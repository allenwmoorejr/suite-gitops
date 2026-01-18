#!/usr/bin/env bash
set -euo pipefail

F="/tmp/cc.final.yaml"

if [ ! -s "$F" ]; then
  echo "ERROR: $F missing/empty. Run ./ops/cc-rebuild-final.sh first."
  exit 1
fi

echo "== Duplicate check (kind + name) =="
awk '
  /^kind: /{k=$2}
  /^metadata:/{inmeta=1}
  inmeta && /^  name: /{print k, $2; inmeta=0}
' "$F" \
| sort \
| uniq -c \
| awk '$1>1{print}'
