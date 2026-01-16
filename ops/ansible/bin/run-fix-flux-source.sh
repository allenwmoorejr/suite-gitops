#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

export ANSIBLE_CONFIG="$ROOT/ops/ansible/ansible.cfg"

VENV="$ROOT/.venv-ansible"
# shellcheck disable=SC1090
source "$VENV/bin/activate"

ansible-playbook ops/ansible/playbooks/fix_flux_source_controller.yml
