# Member 2 — persistent storage and S3

Member 2 owns the object-data PersistentVolumeClaim and the storage/S3 path after the team's PVC handoff. The manifest uses the assigned StorageClass, requests 4Gi with ReadWriteOnce, and mounts the claim at /data. SeaweedFS runs as one replica with the Recreate strategy; its data and metadata stay under /data. The Pod runs non-root with user/group/fsGroup 1000, drops all capabilities, disables ServiceAccount token mounting, and exposes only the S3 Service on TCP 8333.

The identity generator creates unique owner, ingestor and analyst credentials. The server policy is mounted from s3-config; each client receives only its own role Secret. The blocked client gets neither credentials nor the access:s3 network-policy label. Never commit private credentials. The --rotate option intentionally changes keys and therefore requires updating Secrets and restarting storage.

The owner creates or repairs the two bucket fixtures. Task 2's positive reads use ingestor on research-raw/fixture.txt and analyst on research-release/fixture.txt; both must match SHA-256 9ce4c8bb96c85122c3b386653fbe9150cb2f4df03f25c83408fe11c29b87d6f8. A listening port alone is not evidence of an authenticated S3 read.

Task 2 evidence records the actual image ID, Pod UID, PVC UID, StorageClass, bound volume and non-secret manifests. The independent check traces an object through Service to Pod to PVC. During Task 5, the Pod UID should change while this claim UID stays the same and all 32 benchmark objects remain verifiable. Do not delete the PVC.
