#!/usr/bin/env bash
set -euo pipefail

CHART_TPL="apps/suite/command-center/chart/templates"
SAVE_DIR="apps/suite/command-center/chart/_saved-templates"

mkdir -p "$SAVE_DIR"

echo "== Scanning for non-template/backup files inside $CHART_TPL =="
# Anything not .yaml/.yml/.tpl or not starting with "_" is suspicious in Helm templates/
mapfile -t BAD < <(find "$CHART_TPL" -maxdepth 1 -type f \
  ! -name "*.yaml" ! -name "*.yml" ! -name "*.tpl" \
  -print | sort)

if (( ${#BAD[@]} == 0 )); then
  echo "No obviously-bad files found (by extension)."
else
  printf "Will move these out of templates/ so Helm stops rendering them:\n"
  printf " - %s\n" "${BAD[@]}"
  echo
  for f in "${BAD[@]}"; do
    bn="$(basename "$f")"
    mv -v "$f" "$SAVE_DIR/$bn"
  done
fi

echo
echo "== Also renaming any *.bak* that still end with .yaml/.yml to _*.yaml (Helm ignores leading _) =="
# If you have backups that still end in .yaml/.yml, Helm WILL render them unless they start with "_"
find "$CHART_TPL" -maxdepth 1 -type f \( -name "*.bak*.yaml" -o -name "*.bak*.yml" -o -name "*.yaml.bak*" -o -name "*.yml.bak*" \) \
  -print | while read -r f; do
    bn="$(basename "$f")"
    mv -v "$f" "$CHART_TPL/_$bn"
  done || true

echo
echo "== Quick sanity: list templates now =="
ls -la "$CHART_TPL"
