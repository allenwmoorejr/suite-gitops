#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
OUTDIR="_support/${TS}"
mkdir -p "$OUTDIR"

echo "== Collecting repo files =="
mkdir -p "$OUTDIR/repo"
cp -a apps/suite/command-center "$OUTDIR/repo/" 2>/dev/null || true
cp -a apps/traefik "$OUTDIR/repo/" 2>/dev/null || true
cp -a clusters "$OUTDIR/repo/" 2>/dev/null || true

echo "== Collecting cluster snapshots =="
{
  echo "### kubectl version"
  kubectl version --short || true
  echo
  echo "### nodes"
  kubectl get nodes -o wide || true
  echo
  echo "### flux objects"
  kubectl -n flux-system get gitrepositories,kustomizations,helmreleases -o wide || true
  echo
  echo "### suite command-center objects (wide)"
  kubectl -n suite get helmrelease,deploy,po,svc,endpointslice,netpol,ingressroute,middleware -o wide || true
  echo
  echo "### helmrelease describe"
  kubectl -n suite describe helmrelease suite-command-center || true
  echo
  echo "### suite events"
  kubectl -n suite get events --sort-by=.metadata.creationTimestamp || true
} > "$OUTDIR/cluster.txt"

echo "== Controller logs (recent) =="
kubectl -n flux-system logs deploy/source-controller --since=30m > "$OUTDIR/source-controller.log" 2>&1 || true
kubectl -n flux-system logs deploy/kustomize-controller --since=30m > "$OUTDIR/kustomize-controller.log" 2>&1 || true
kubectl -n flux-system logs deploy/helm-controller --since=30m > "$OUTDIR/helm-controller.log" 2>&1 || true
kubectl -n traefik logs deploy/traefik --since=30m > "$OUTDIR/traefik.log" 2>&1 || true

echo "== Bundle it up =="
tar -czf "_support/support-bundle-${TS}.tar.gz" -C "_support" "${TS}"

echo
echo "Created: _support/support-bundle-${TS}.tar.gz"
echo "Tip: you can upload that tar.gz here, or paste cluster.txt + helm-controller.log excerpts."
