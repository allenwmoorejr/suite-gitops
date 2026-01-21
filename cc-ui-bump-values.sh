#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <NEW_TAG>"
  exit 1
fi

NEW_TAG="$1"

VALUES="apps/suite/command-center/chart/values.yaml"

echo "==> Updating ui.tag → $NEW_TAG"
echo

perl -0777 -i -pe '
  s/(ui:\s*\n(?:[^\n]*\n)*?\s*tag:\s*).*/${1}'"$NEW_TAG"'/m
' "$VALUES"

echo "==> Diff"
git diff "$VALUES" || true

git add "$VALUES"
git commit -m "command-center-ui: bump image to ${NEW_TAG}" || true
git push

echo
echo "==> Done. Flux will reconcile automatically."
echo "Optional manual kick:"
echo "  flux reconcile kustomization flux-system -n flux-system --with-source"
