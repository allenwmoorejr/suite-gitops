#!/usr/bin/env bash
set -euo pipefail
echo "== head of /tmp/cc.final.yaml =="
nl -ba /tmp/cc.final.yaml | sed -n '1,40p'
