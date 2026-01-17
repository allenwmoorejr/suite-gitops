#!/usr/bin/env bash
set -euo pipefail

kubectl -n suite apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: suite-command-center-ui
  namespace: suite
  labels:
    app: suite-command-center-ui
spec:
  selector:
    app: suite-command-center-ui
  ports:
    - name: http
      port: 80
      targetPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: suite-command-center-api
  namespace: suite
  labels:
    app: suite-command-center-api
spec:
  selector:
    app: suite-command-center-api
  ports:
    - name: http
      port: 80
      targetPort: 8000
---
# Some of your IngressRoutes reference this name, so give it a real Service.
apiVersion: v1
kind: Service
metadata:
  name: suite-command-center-api-shim
  namespace: suite
  labels:
    app: suite-command-center-api
spec:
  selector:
    app: suite-command-center-api
  ports:
    - name: http
      port: 80
      targetPort: 8000
YAML

echo
echo "== Services now =="
kubectl -n suite get svc | egrep -i 'suite-command-center|NAME' || true
