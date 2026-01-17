#!/usr/bin/env bash
set -euo pipefail

curl -s http://127.0.0.1:8080/api/http/routers \
| jq -r '.[] 
  | select(.rule|test("command-center")) 
  | "\(.name)\tprio=\(.priority)\t\(.entryPoints|join(","))\t\(.rule)\t->\t\(.service)"'
