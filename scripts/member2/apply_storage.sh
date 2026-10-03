#!/bin/sh
set -eu

: "${NS:?Set the instructor-assigned NS}" \
  "${STORAGE_IMAGE:?Set the instructor-approved STORAGE_IMAGE digest}" \
  "${STORAGE_CLASS:?Set the instructor-approved STORAGE_CLASS}"
case "$STORAGE_IMAGE" in
  *@sha256:*) ;;
  *) printf '%s\n' 'STORAGE_IMAGE must be an approved immutable digest.' >&2; exit 2 ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
kubectl get storageclass "$STORAGE_CLASS" >/dev/null
envsubst '${STORAGE_IMAGE} ${STORAGE_CLASS}' < "$ROOT/manifests/member2/storage.yaml.tpl" \
  | kubectl -n "$NS" apply -f -
kubectl -n "$NS" rollout status deployment/objects --timeout=120s
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Bound pvc/object-data --timeout=120s
kubectl -n "$NS" get pod,pvc,svc,endpointslice -o wide
