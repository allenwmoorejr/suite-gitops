#!/usr/bin/env bash
set -euo pipefail

NS="suite"
HR="suite-command-center"

echo "== HelmRelease status =="
kubectl -n $NS get helmrelease $HR -o wide
echo

echo "== Resources (deployments, pods, services) =="
kubectl -n $NS get deploy,rs,po,svc -o wide | egrep -i 'suite-command-center|NAME' || true
echo

echo "== EndpointSlices (expect ENDPOINTS > 0) =="
kubectl -n $NS get endpointslice -l kubernetes.io/service-name=suite-command-center-ui -o wide || true
kubectl -n $NS get endpointslice -l kubernetes.io/service-name=suite-command-center-api -o wide || true
echo
