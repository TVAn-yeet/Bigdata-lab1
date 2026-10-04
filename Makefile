.PHONY: help preflight guardrails quota-probes identities secrets storage clients seed task2-evidence access security benchmark benchmark-summary recover

help:
	@printf '%s\n' \
	  'Set NS, STORAGE_IMAGE, CLIENT_IMAGE and STORAGE_CLASS from instructor-provided values.' \
	  'preflight            Check tools, namespace and quota baseline (read-only)' \
	  'guardrails           Apply Task 1 ResourceQuota' \
	  'quota-probes         Run the admitted and quota-rejected Pod probes' \
	  'identities           Generate local random S3 identities (never prints secrets)' \
	  'secrets              Apply the server and per-role Kubernetes Secrets' \
	  'storage              Apply PVC, SeaweedFS Deployment and private Service' \
	  'clients              Apply owner, ingestor, analyst and blocked Pods' \
	  'seed                 Create buckets/fixtures and verify the two role reads' \
	  'task2-evidence       Capture topology and storage identity evidence' \
	  'access               Apply NetworkPolicy and observer RBAC' \
	  'security             Run S3, RBAC and network matrices; needs operator/reviewer IDs' \
	  'benchmark            Run six controlled trials and resource sampling' \
	  'benchmark-summary    Build a CSV from raw benchmark JSONL' \
	  'recover              Replace only the storage Pod and verify persistence'

preflight:
	python3 scripts/member1/preflight.py

guardrails:
	envsubst '$${NS}' < manifests/member1/guardrails.yaml.tpl | kubectl -n "$${NS:?set NS}" apply -f -

quota-probes:
	NS="$${NS:?set NS}" CLIENT_IMAGE="$${CLIENT_IMAGE:?set CLIENT_IMAGE}" scripts/member1/task1.sh

identities:
	python3 scripts/storage/make_identities.py

secrets:
	NS="$${NS:?set NS}" scripts/storage/apply_secrets.sh

storage: secrets
	NS="$${NS:?set NS}" scripts/storage/apply_storage.sh

clients: storage
	NS="$${NS:?set NS}" CLIENT_IMAGE="$${CLIENT_IMAGE:?set CLIENT_IMAGE}" scripts/storage/clients.sh

seed: clients
	NS="$${NS:?set NS}" scripts/storage/seed_and_verify.sh

task2-evidence:
	NS="$${NS:?set NS}" scripts/storage/capture_storage_evidence.sh

access:
	envsubst '$${NS}' < manifests/member3/access.yaml.tpl | kubectl -n "$${NS:?set NS}" apply -f -

security:
	python3 scripts/member3/run_security.py

benchmark:
	NS="$${NS:?set NS}" scripts/member4/run_benchmark.sh

benchmark-summary:
	python3 scripts/member4/summarize_benchmark.py evidence/task4

recover:
	NS="$${NS:?set NS}" scripts/member4/recover.sh
