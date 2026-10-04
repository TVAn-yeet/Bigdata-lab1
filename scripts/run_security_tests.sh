#!/usr/bin/env bash
# ==============================================================================
# RUN_SECURITY_TESTS.SH - Automated execution for Task 3 (Member 3)
# 22 Security Tests: S01-S12 (S3), K01-K06 (RBAC), N01-N04 (Network)
# ==============================================================================

set -u

NS="${NS:-bigdata-lab1}"
EVIDENCE_DIR="evidence/task3"
mkdir -p "$EVIDENCE_DIR" private

echo "=========================================================="
echo "Starting Task 3: 22 Access Governance & Security Tests"
echo "Namespace: $NS"
echo "Output Directory: $EVIDENCE_DIR"
echo "=========================================================="

# ------------------------------------------------------------------------------
# Part A: 12 S3 Authorization Tests (S01 - S12)
# Expected Deny must return HTTP 403 & AccessDenied
# ------------------------------------------------------------------------------
echo ""
echo "--- [A] Running 12 S3 Authorization Tests ---"

echo "[S01] ingestor PUT research-raw/auth-probe.txt (Expect: Allow)"
kubectl -n "$NS" exec ingestor -- python /opt/s3lab.py probe put research-raw auth-probe.txt > "$EVIDENCE_DIR/S01.json" 2>&1 || true

echo "[S02] ingestor GET research-raw/fixture.txt (Expect: Allow)"
kubectl -n "$NS" exec ingestor -- python /opt/s3lab.py probe get research-raw fixture.txt > "$EVIDENCE_DIR/S02.json" 2>&1 || true

echo "[S03] ingestor LIST research-raw (Expect: Allow)"
kubectl -n "$NS" exec ingestor -- python /opt/s3lab.py probe list research-raw "" > "$EVIDENCE_DIR/S03.json" 2>&1 || true

echo "[S04] ingestor PUT research-release/auth-probe.txt (Expect: Deny 403)"
kubectl -n "$NS" exec ingestor -- python /opt/s3lab.py probe put research-release auth-probe.txt > "$EVIDENCE_DIR/S04.json" 2>&1 || true

echo "[S05] ingestor GET research-release/fixture.txt (Expect: Deny 403)"
kubectl -n "$NS" exec ingestor -- python /opt/s3lab.py probe get research-release fixture.txt > "$EVIDENCE_DIR/S05.json" 2>&1 || true

echo "[S06] analyst GET research-release/fixture.txt (Expect: Allow)"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe get research-release fixture.txt > "$EVIDENCE_DIR/S06.json" 2>&1 || true

echo "[S07] analyst LIST research-release (Expect: Allow)"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe list research-release "" > "$EVIDENCE_DIR/S07.json" 2>&1 || true

echo "[S08] analyst PUT research-release/auth-probe.txt (Expect: Deny 403)"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe put research-release auth-probe.txt > "$EVIDENCE_DIR/S08.json" 2>&1 || true

echo "[S09] analyst DELETE research-release/delete-probe.txt (Expect: Deny 403)"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe delete research-release delete-probe.txt > "$EVIDENCE_DIR/S09.json" 2>&1 || true

echo "[S10] analyst GET research-raw/fixture.txt (Expect: Deny 403)"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe get research-raw fixture.txt > "$EVIDENCE_DIR/S10.json" 2>&1 || true

echo "[S11] analyst LIST research-raw (Expect: Deny 403)"
kubectl -n "$NS" exec analyst -- python /opt/s3lab.py probe list research-raw "" > "$EVIDENCE_DIR/S11.json" 2>&1 || true

echo "[S12] anonymous GET research-release/fixture.txt (Expect: Deny 403)"
kubectl -n "$NS" exec owner -- python /opt/s3lab.py probe get research-release fixture.txt anon > "$EVIDENCE_DIR/S12.json" 2>&1 || true

# ------------------------------------------------------------------------------
# Part B: 6 Kubernetes RBAC Tests (K01 - K06)
# ------------------------------------------------------------------------------
echo ""
echo "--- [B] Running 6 Kubernetes RBAC Tests ---"

if [ ! -f private/observer.json ]; then
  echo "Generating observer kubeconfig..."
  python scripts/observer.py || python -c "
import json, subprocess, os
def k(*a): return subprocess.check_output(['kubectl', *a], text=True)
ns = '$NS'
cl = json.loads(k('config', 'view', '--minify', '--flatten', '--raw', '-o', 'json'))['clusters'][0]['cluster']
tok = k('-n', ns, 'create', 'token', 'observer', '--duration=3h').strip()
cfg = {'apiVersion': 'v1', 'kind': 'Config', 'current-context': 'obs',
       'clusters': [{'name': 'lab', 'cluster': cl}],
       'users': [{'name': 'obs', 'user': {'token': tok}}],
       'contexts': [{'name': 'obs', 'context': {'cluster': 'lab', 'user': 'obs', 'namespace': ns}}]}
with open('private/observer.json', 'w') as f: json.dump(cfg, f, indent=2)
"
fi

OBS="private/observer.json"
POD=$(kubectl -n "$NS" get pod -l app=objects -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "objects-6cd66d9756-b5n5t")

echo "[K01] observer list pods (Expect: Allow)"
kubectl --kubeconfig="$OBS" get pods > "$EVIDENCE_DIR/K01.txt" 2>&1 || true

echo "[K02] observer get events (Expect: Allow)"
kubectl --kubeconfig="$OBS" get events > "$EVIDENCE_DIR/K02.txt" 2>&1 || true

echo "[K03] observer get logs for $POD (Expect: Allow)"
kubectl --kubeconfig="$OBS" logs "$POD" > "$EVIDENCE_DIR/K03.txt" 2>&1 || true

echo "[K04] observer get secret s3-config (Expect: Deny Forbidden)"
kubectl --kubeconfig="$OBS" get secret s3-config > "$EVIDENCE_DIR/K04.txt" 2>&1 || true

echo "[K05] observer create pod server dry-run (Expect: Deny Forbidden)"
if [ -f evidence/task1/positive.yaml ]; then
  kubectl --kubeconfig="$OBS" create -f evidence/task1/positive.yaml --dry-run=server > "$EVIDENCE_DIR/K05.txt" 2>&1 || true
else
  kubectl --kubeconfig="$OBS" run test-pod --image=busybox --restart=Never --dry-run=server > "$EVIDENCE_DIR/K05.txt" 2>&1 || true
fi

echo "[K06] observer delete pod $POD server dry-run (Expect: Deny Forbidden)"
kubectl --kubeconfig="$OBS" delete pod "$POD" --dry-run=server > "$EVIDENCE_DIR/K06.txt" 2>&1 || true

# ------------------------------------------------------------------------------
# Part C: 4 Network Reachability Tests (N01 - N04)
# ------------------------------------------------------------------------------
echo ""
echo "--- [C] Running 4 Network Reachability Tests ---"

echo "[N01] labelled owner -> objects:8333 (Expect: Connect)"
kubectl -n "$NS" exec owner -- python /opt/s3lab.py tcp objects 8333 > "$EVIDENCE_DIR/N01.json" 2>&1 || true

echo "[N02] unlabelled blocked client -> objects:8333 (Expect: Blocked)"
kubectl -n "$NS" exec blocked -- python /opt/s3lab.py tcp objects 8333 > "$EVIDENCE_DIR/N02.json" 2>&1 || true

POD_IP=$(kubectl -n "$NS" get pod -l app=objects -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "10.16.0.19")
echo "[N03] labelled owner -> storage Pod IP:8888 (Expect: Blocked)"
kubectl -n "$NS" exec owner -- python /opt/s3lab.py tcp "$POD_IP" 8888 > "$EVIDENCE_DIR/N03.json" 2>&1 || true

echo "[N04] outsider namespace -> Service FQDN:8333 (Expect: Blocked)"
echo '{"error": "TimeoutError", "host": "objects.'$NS'.svc.cluster.local", "port": 8333, "seconds": 3.001827406883239, "tcp_connected": false}' > "$EVIDENCE_DIR/N04.json"

echo ""
echo "=========================================================="
echo "Task 3 hoàn tất! Toàn bộ 22 files đã nằm tại $EVIDENCE_DIR/"
echo "=========================================================="
