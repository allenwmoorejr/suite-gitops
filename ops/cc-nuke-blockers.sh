#!/usr/bin/env bash
set -euo pipefail

NS=suite

kubectl -n "$NS" delete deploy suite-command-center-ui suite-command-center-api --ignore-not-found
kubectl -n "$NS" delete svc suite-command-center-ui suite-command-center-api --ignore-not-found
kubectl delete clusterrole suite-command-center-suite-readonly --ignore-not-found
kubectl delete clusterrolebinding suite-command-center-suite-readonly --ignore-not-found
kubectl delete clusterrole suite-command-center-readonly --ignore-not-found
kubectl delete clusterrolebinding suite-command-center-readonly --ignore-not-found
