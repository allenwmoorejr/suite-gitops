#!/usr/bin/env bash
set -euo pipefail

helm template suite-command-center apps/suite/command-center/chart -n suite \
  | awk '/^kind: /{kind=$2} /^metadata:/{meta=1} meta && /^  name: /{print kind, $2; meta=0}' \
  | sort | uniq -c | awk '$1 > 1'
