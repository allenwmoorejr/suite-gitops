#!/usr/bin/env bash
set -euo pipefail

# --- config (override via env if you want) ---
UI_DIR="${UI_DIR:-$HOME/dashboard-k3s/suite-command-center/services/command-center-ui}"
REGISTRY_HOST="${REGISTRY_HOST:-registry.suite.home.arpa:5000}"
IMAGE_REPO="${IMAGE_REPO:-$REGISTRY_HOST/suite-command-center-ui}"
THEME="${THEME:-boss}"

# --- derive a unique tag ---
GIT_SHA="$(git -C "$UI_DIR" rev-parse --short=7 HEAD)"
STAMP="$(date +%Y%m%d-%H%M%S)"
NEW_TAG="${THEME}-${GIT_SHA}-${STAMP}"

echo "UI_DIR=$UI_DIR"
echo "IMAGE_REPO=$IMAGE_REPO"
echo "NEW_TAG=$NEW_TAG"
echo

# --- build + push (single-arch by default; add buildx platforms if you want) ---
cd "$UI_DIR"
docker build -t "${IMAGE_REPO}:${NEW_TAG}" .
docker push "${IMAGE_REPO}:${NEW_TAG}"

echo
echo "Built+Pushed: ${IMAGE_REPO}:${NEW_TAG}"
echo "$NEW_TAG"
