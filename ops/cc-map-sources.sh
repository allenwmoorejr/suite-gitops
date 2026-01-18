#!/usr/bin/env bash
set -euo pipefail

NS="suite"
REL="suite-command-center"
CHART="apps/suite/command-center/chart"

helm template "$REL" "$CHART" -n "$NS" \
| awk '
  /^# Source: /{src=$3}
  /^kind: /{kind=$2}
  /^metadata:/{inmeta=1}
  inmeta && /^  name: /{name=$2; print kind, name, "=>", src; inmeta=0}
'
