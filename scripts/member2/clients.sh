#!/bin/sh
set -eu
set +x

: "${NS:?Set the instructor-assigned NS}" "${CLIENT_IMAGE:?Set the approved CLIENT_IMAGE digest}"
case "$CLIENT_IMAGE" in
  *@sha256:*) ;;
  *) printf '%s\n' 'CLIENT_IMAGE must be an approved immutable digest.' >&2; exit 2 ;;
esac

for role in owner ingestor analyst blocked; do
  ACCESS_LABEL=
  CREDS=
  if [ "$role" != blocked ]; then
    ACCESS_LABEL='    access: s3'
    CREDS=$(cat <<EOF
      envFrom:
        - secretRef:
            name: s3-$role
EOF
)
  fi
  # The blocked Pod intentionally gets neither the policy label nor credentials.
  kubectl -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $role
  labels:
    role: $role
$ACCESS_LABEL
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
  containers:
    - name: client
      image: $CLIENT_IMAGE
      imagePullPolicy: IfNotPresent
      command: ["sleep", "infinity"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
      env:
        - name: S3_ENDPOINT
          value: http://objects:8333
        - name: PRINCIPAL
          value: $role
$CREDS
EOF
done
kubectl -n "$NS" wait --for=condition=Ready pod/owner pod/ingestor pod/analyst pod/blocked --timeout=120s
