#!/bin/sh
set -eu

: "${NS:?Set the instructor-assigned NS}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT="$ROOT/evidence/task2"
mkdir -p "$OUT"
kubectl -n "$NS" get pod,pvc,svc,endpointslice -o wide > "$OUT/topology.txt"
kubectl -n "$NS" get deployment objects -o yaml > "$OUT/deployment.yaml"
kubectl -n "$NS" get pvc object-data -o yaml > "$OUT/pvc.yaml"
kubectl -n "$NS" get pod -l app=objects -o yaml > "$OUT/storage-pod.yaml"
kubectl -n "$NS" get service objects -o yaml > "$OUT/service.yaml"
kubectl -n "$NS" get pods -l app=objects \
  -o jsonpath='{range .items[*]}pod={.metadata.name} pod_uid={.metadata.uid} image={.spec.containers[0].image} image_id={.status.containerStatuses[0].imageID} node={.spec.nodeName}{"\n"}{end}' \
  > "$OUT/storage-provenance.txt"
kubectl -n "$NS" get pvc object-data \
  -o jsonpath='pvc_uid={.metadata.uid} storage_class={.spec.storageClassName} phase={.status.phase} volume={.spec.volumeName}{"\n"}' \
  > "$OUT/pvc-provenance.txt"
printf '%s\n' 'Captured non-secret topology and storage provenance; no Secret object was read.'
