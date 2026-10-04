#!/bin/sh
set -eu
set +x

: "${NS:?Set the instructor-assigned NS}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PRIVATE="$ROOT/private"
for path in "$PRIVATE/s3.json" "$PRIVATE/owner.env" "$PRIVATE/ingestor.env" "$PRIVATE/analyst.env"; do
  if [ ! -f "$path" ]; then
    printf 'Missing private credential file: %s\n' "$path" >&2
    exit 2
  fi
done

umask 077
kubectl -n "$NS" create secret generic s3-config \
  --from-file=s3.json="$PRIVATE/s3.json" --dry-run=client -o yaml \
  | kubectl -n "$NS" apply -f -
for role in owner ingestor analyst; do
  kubectl -n "$NS" create secret generic "s3-$role" \
    --from-env-file="$PRIVATE/$role.env" --dry-run=client -o yaml \
    | kubectl -n "$NS" apply -f -
done
printf '%s\n' 'Applied s3-config and three role Secrets; values were not printed.'
