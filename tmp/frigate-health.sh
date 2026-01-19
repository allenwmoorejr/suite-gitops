#!/usr/bin/env bash
set -euo pipefail

NS="${1:-observe}"
LABEL='app.kubernetes.io/instance=frigate'

POD="$(kubectl -n "$NS" get pod -l "$LABEL" -o jsonpath='{.items[0].metadata.name}')"

echo "== Pod status =="
kubectl -n "$NS" get pod -l "$LABEL" \
  -o 'custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
echo

echo "== Watchdog / segment errors (last 800 lines) =="
kubectl -n "$NS" logs "$POD" --tail=800 \
  | egrep -i "No new recording segments|watchdog" \
  || echo "None ✅"
echo

echo "== PPS / decode spam (last 800 lines) =="
kubectl -n "$NS" logs "$POD" --tail=800 \
  | egrep -i "non-existing PPS|decode_slice_header|no frame" \
  || echo "None ✅"
echo

echo "== Recordings disk usage =="
kubectl -n "$NS" exec "$POD" -- sh -lc 'du -sh /media/frigate/recordings 2>/dev/null || true'
echo

echo "== Newest 20 segments =="
kubectl -n "$NS" exec "$POD" -- sh -lc '
  find /media/frigate/recordings -type f -printf "%T@ %p\n" 2>/dev/null \
  | sort -n | tail -n 20 | cut -d" " -f2-
'
