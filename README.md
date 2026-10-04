# Big Data Lab 1 — Cluster Configuration

This repository contains a reproducible implementation of the lab's five tasks: namespace guardrails, persistent SeaweedFS S3 storage, access governance, a controlled transfer experiment, and Pod recovery with integrity checks.

The manifests and scripts use the lab contract. They do not contain cluster credentials, student identifiers, image digests, or invented result data. The instructor or team must provide the assigned namespace, approved image digests, StorageClass, cluster access, and actual human operator/reviewer IDs before deployment.

## Start here

1. Read [`docs/architecture.md`](docs/architecture.md) and [`docs/runbook.md`](docs/runbook.md).
2. Set `NS`, `STORAGE_IMAGE`, `CLIENT_IMAGE`, and `STORAGE_CLASS` using values supplied for the assigned cluster. Confirm `kubectl config current-context` and that the assigned namespace exists.
3. Create local credentials with `python3 scripts/storage/make_identities.py`. Keep `private/` private and out of Git.
4. Follow the runbook in order. Apply only to the assigned namespace. Collect actual outputs under `evidence/`; do not fill results from assumptions.

The role branches are `member1`, `member2`, `member3`, and `member4`. `main` is the locally integrated branch. Commits in this repository are local; no remote is configured by this project.

## Important boundaries

This is a single-replica teaching deployment with synthetic data. It does not demonstrate high availability, backup, node-loss durability, crash consistency, TLS, encryption at rest, or enforced retention. A successful Pod replacement is evidence only for recovery against the same retained PVC. Never delete the namespace, PVC, PV, or real research data during the lab.

Live Kubernetes/S3 evidence is environment-specific. A successful local syntax check cannot substitute for a real PVC binding, S3 request, security denial, benchmark, or recovery measurement.

