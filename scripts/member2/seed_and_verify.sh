#!/bin/sh
set -eu

: "${NS:?Set the instructor-assigned NS}" \
  "${HUMAN_OPERATOR:?Set the student ID of the operator}" \
  "${HUMAN_REVIEWER:?Set the student ID of the independent reviewer}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT="$ROOT/evidence/task2"
mkdir -p "$OUT"
printf '%s\n' "operator=$HUMAN_OPERATOR" "reviewer=$HUMAN_REVIEWER" > "$OUT/attribution.txt"

kubectl -n "$NS" exec owner -- python /opt/s3lab.py seed > "$OUT/seed.jsonl"
kubectl -n "$NS" exec ingestor -- python /opt/s3lab.py probe get research-raw fixture.txt \
  > "$OUT/ingestor-raw-read.json"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe get research-release fixture.txt \
  > "$OUT/analyst-release-read.json"
python3 - "$OUT/ingestor-raw-read.json" "$OUT/analyst-release-read.json" <<'PY'
import json
import sys

expected = "9ce4c8bb96c85122c3b386653fbe9150cb2f4df03f25c83408fe11c29b87d6f8"
for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as stream:
        row = json.load(stream)
    if row.get("http") != 200 or row.get("ok") is not True:
        raise SystemExit(f"read failed: {filename}; inspect its non-secret JSON evidence")
    if row.get("sha256") != expected or row.get("hash_ok") is not True:
        raise SystemExit(f"fixture integrity mismatch: {filename}")
print("Both authorized role reads returned the expected fixture SHA-256.")
PY
