# Architecture and control boundaries

## Data path

An authorized client Pod sends S3 requests to the in-namespace `objects` ClusterIP Service on TCP 8333. The Service selects the single SeaweedFS Pod. S3 credentials authorize the object operation. The storage process reads and writes object data and metadata below `/data`, which is backed by the `object-data` PVC and its bound PV.

The Kubernetes API is the management path: `kubectl` applies and observes Kubernetes objects. S3 object payloads do not pass through the Kubernetes API. The `observer` ServiceAccount has read-only access to Pods, Pod logs, and events; that does not grant S3 access.

## Independent controls

1. **Kubernetes admission and ResourceQuota** constrain declared resources and object counts in the namespace.
2. **S3 identity policies** constrain operations by role and bucket.
3. **Ingress NetworkPolicy** constrains new network connections into the storage Pod. The lab policy permits in-namespace Pods labelled `access: s3` to TCP 8333. A label is a selector, not a cryptographic identity.
4. **PVC/PV** provide the filesystem backing store. A claim is not a network endpoint and is not an S3 permission.

## Deliberate scope limits

One replica and graceful Pod replacement on the same PVC do not demonstrate high availability, backup restore, crash consistency, node-loss durability, or zero downtime. The teaching setup uses in-cluster HTTP and Kubernetes Secrets; it does not demonstrate TLS or encryption at rest. Retention is documented as a commitment and is not automatically enforced.

