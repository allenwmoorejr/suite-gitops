#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fix_file () {
  local f="$1"
  [ -f "$f" ] || return 0
  python3 - <<PY
from pathlib import Path
import re
p = Path("$f")
s = p.read_text()
# Fix: sc_node:"..." -> sc_node: "..."
s2 = re.sub(r'(^\s*sc_node):"', r'\1: "', s, flags=re.M)
if s2 != s:
    p.write_text(s2)
    print(f"✅ patched {p}")
else:
    print(f"ℹ️  no change needed {p}")
PY
}

fix_file "ops/ansible/playbooks/fix_flux_source_controller.yml"
fix_file "ops/ansible/00_write_all.sh"

echo "== quick syntax check =="
VENV="$ROOT/.venv-ansible"
if [ -d "$VENV" ]; then
  # shellcheck disable=SC1090
  source "$VENV/bin/activate"
  ansible-playbook --syntax-check -i ops/ansible/inventory.ini ops/ansible/playbooks/fix_flux_source_controller.yml
else
  echo "ℹ️  venv not found (.venv-ansible). Run: bash ops/ansible/bootstrap.sh"
fi
