#!/usr/bin/env bash
set -euo pipefail

NS="suite"
HR="suite-command-center"
CHART_PATH="apps/suite/command-center/chart"

echo "== A) Check HelmRelease for postRenderers (most likely culprit) =="
kubectl -n "$NS" get helmrelease "$HR" -o yaml \
  | sed -n '/^spec:/,/^status:/p' \
  | sed -n '/postRenderers:/,/values:/p' || true
echo

echo "== B) Build FINAL manifests the same way Flux does (includes post-render) =="
if command -v flux >/dev/null 2>&1; then
  flux build helmrelease "$HR" -n "$NS" > /tmp/cc.final.yaml
  echo "Wrote: /tmp/cc.final.yaml"
else
  echo "flux CLI not found; falling back to helm template (NO post-render)."
  helm template suite-command-center "$CHART_PATH" -n "$NS" > /tmp/cc.final.yaml
  echo "Wrote: /tmp/cc.final.yaml"
fi
echo

echo "== C) Show duplicate resource IDs (apiVersion/kind/ns/name) =="
python3 - <<'PY'
import sys
from collections import Counter
try:
  import yaml
except Exception as e:
  print("PyYAML missing. Install with: sudo apt-get install -y python3-yaml")
  sys.exit(2)

p="/tmp/cc.final.yaml"
docs=list(yaml.safe_load_all(open(p,"r")))
keys=[]
for d in docs:
  if not isinstance(d, dict): 
    continue
  api=d.get("apiVersion","")
  kind=d.get("kind","")
  meta=d.get("metadata") or {}
  name=meta.get("name","")
  ns=meta.get("namespace","") or ""
  if api and kind and name:
    keys.append((api,kind,ns,name))

c=Counter(keys)
dupes=[(k,v) for k,v in c.items() if v>1]
if not dupes:
  print("No duplicate IDs found in /tmp/cc.final.yaml")
  sys.exit(0)

print("DUPLICATES:")
for (api,kind,ns,name),v in sorted(dupes, key=lambda x:(x[0][1],x[0][3],x[0][2])):
  print(f"{v}x {api} {kind} {ns or '-'} {name}")
PY
echo

echo "== D) If your dupe is the UI Deployment, show BOTH occurrences with context =="
# This prints line numbers where the UI Deployment starts (in the final YAML)
grep -nE '^(apiVersion:|kind: Deployment|  name: suite-command-center-ui|  namespace: )' /tmp/cc.final.yaml \
  | sed -n '1,220p' || true
echo

echo "== E) Search repo for any SECOND Deployment definition for suite-command-center-ui =="
grep -R --line-number -nE 'kind: Deployment|name: suite-command-center-ui' apps/suite/command-center || true
