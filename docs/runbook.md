# Runbook

The lab cluster, assigned namespace, approved images and StorageClass are instructor-provided. Do not substitute public image tags for approved immutable digests. The commands below target only `NS`.

## Required inputs and preflight

```sh
export NS='your-assigned-namespace'
export STORAGE_IMAGE='approved-storage-image@sha256:...'
export CLIENT_IMAGE='approved-client-image@sha256:...'
export STORAGE_CLASS='instructor-approved-class'
export HUMAN_OPERATOR='student-id'
export HUMAN_REVIEWER='student-id'
mkdir -p evidence/task1 evidence/task2 evidence/task3 evidence/task4 evidence/task5 private
chmod 700 private
make preflight
```

The `...` above indicates a value to obtain from teaching staff; it is not a valid image reference. `make preflight` checks that required tools and the namespace exist, then records versions and the initial quota/PVC/Pod/Service state. Stop and record `PLATFORM-BLOCKED` if the image, CNI, credentials, StorageClass or permissions prevent a valid preflight.

## Ordered execution

1. `make guardrails quota-probes`: apply the ResourceQuota; prove a valid small Pod is admitted and an otherwise valid over-quota Pod is rejected specifically for quota.
2. `make identities secrets storage clients`: generate local role credentials, create separate Kubernetes Secrets, and deploy the PVC, one SeaweedFS replica, ClusterIP Service and four role Pods.
3. `make seed task2-evidence`: seed both buckets, verify raw/ingestor and release/analyst reads, and capture actual image IDs, Pod/PVC UIDs, StorageClass and non-secret manifests.
4. `make access`: apply the observer RBAC and storage ingress NetworkPolicy. Then run the security script with human operator/reviewer IDs. Keep all initial failures and corrected retests.
5. `make benchmark benchmark-summary`: warm up once, run three trials at concurrency 1 and three at concurrency 4, sample Pod usage/status every five seconds, retain raw outcomes and summarize each trial/phase.
6. `make recover`: verify one completed 32-object trial, record before state, keep the canary in the ingestor Pod, delete only the current storage Pod, verify the new Pod and same PVC, then recheck hashes and S3 controls.
7. Complete governance and contribution records from observed facts. Submit only after the evidence bundle is reviewed. The instructor controls namespace/PVC cleanup.

## Safety and evidence rules

- Never delete the namespace, PVC, PV or real research data. Recovery deletes one disposable storage Pod with normal termination.
- Never print, commit, or submit `private/s3.json`, role environment files, observer kubeconfig, Secret values or operator kubeconfig.
- S3 denial is a pass only for HTTP 403 `AccessDenied` on the intended existing object. Timeout, DNS failure, connection refusal, 404, invalid credentials and signature errors are not authorization passes.
- An unexpected allowed delete targets only `research-release/delete-probe.txt`; retain the failure and reseed the fixture with the owner before continuing.
- Do not claim HA, backup, node-loss durability, TLS, encryption at rest, immutable audit logs or enforced retention.

