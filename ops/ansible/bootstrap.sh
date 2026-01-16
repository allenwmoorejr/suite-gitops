#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

sudo apt-get update -y
sudo apt-get install -y python3-venv python3-pip jq

VENV="$ROOT/.venv-ansible"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi

# shellcheck disable=SC1090
source "$VENV/bin/activate"

pip install -U pip
pip install -U ansible-core

ansible-playbook --version | head -n 2
