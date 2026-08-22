# Backup and Restore Runbook

## Purpose

This runbook defines backup priorities and recovery procedures for AstraDeployment Portable Local Deployment 1.0.

## Recovery invariant

```text
PostgreSQL = canonical state / primary recovery asset
Qdrant     = rebuildable projection
Model cache = reproducible runtime artifact cache
```

Therefore backup priority is:

1. PostgreSQL;
2. deployment configuration and release identity;
3. model cache when fast/offline recovery matters;
4. Qdrant volume when rapid recovery is preferred over rebuild.

## What must be recorded with every backup

Record:

```text
AstraDeployment version
AstraVector immutable tag
AstraVector digest
PostgreSQL image/tag
Qdrant image/tag
model bundle identity + SHA256
backup timestamp UTC
source host/customer/environment
```

Without release identity, a backup may restore data but not a reproducible runtime.

## PostgreSQL backup

Preferred logical backup:

```bash
docker exec astradeployment-postgres-1 \
  pg_dump -U astravector_app -d astravector -Fc \
  > astravector-$(date -u +%Y%m%dT%H%M%SZ).dump
```

Verify the resulting file is non-empty and store it outside the Docker volume.

For large production databases, customer policy may require physical backup tooling or managed PostgreSQL backup instead of `pg_dump`.

## PostgreSQL restore

Start PostgreSQL without assuming Qdrant state is authoritative. Restore into an empty/approved target database:

```bash
cat astravector-YYYYMMDDTHHMMSSZ.dump | \
  docker exec -i astradeployment-postgres-1 \
  pg_restore -U astravector_app -d astravector --clean --if-exists
```

Exact restore flags must be reviewed for the customer's environment. Never run destructive restore against a production database without explicit approval.

After restore:

```text
PostgreSQL restored
→ AstraVector start
→ health/readiness
→ reconciliation/rebuild if Qdrant was not restored
→ smoke test
```

## Qdrant backup

Qdrant is not the canonical source of truth. There are two supported recovery approaches.

### Rebuild approach

Preferred when correctness is more important than recovery speed:

```text
restore PostgreSQL
→ start empty/clean Qdrant
→ AstraVector reconciliation/rebuild
→ validate retrieval
```

### Fast restore approach

If operational recovery time matters, back up the Qdrant volume or use Qdrant snapshot facilities appropriate to the customer environment. The Qdrant backup must correspond closely to the PostgreSQL backup timestamp.

After restoring both, still run health and retrieval validation because projection drift is possible.

## Model cache backup

The model cache is not canonical business data, but it is valuable for constrained or air-gapped installations.

Verify hashes before export:

```text
model.onnx
model.onnx_data
tokenizer.json
manifest.sha256
```

A model cache backup is accepted only when all expected SHA256 values match the release contract.

Conceptual export:

```text
astradeployment-model-cache
→ archive/export
→ checksum archive
→ store with release metadata
```

On restore, place the verified files in the model cache volume and ensure UID/GID ownership is compatible with the AstraVector runtime user before startup.

## Configuration backup

Back up the non-secret deployment repository revision and separately preserve secret/config values according to customer policy.

Never use Git as a secret backup system.

Recommended split:

```text
Git/release bundle:
- Compose
- scripts
- version pins
- documentation

Secret store/password vault:
- PostgreSQL password
- Nexus credentials
- registry credentials/tokens
- future API keys
```

## Recovery modes

### Mode A — Empty service

Use when no customer documents need recovery:

```text
release bundle
+ secrets
+ model source/cache
→ start PostgreSQL empty
→ start Qdrant empty
→ start AstraVector
```

### Mode B — Business-data recovery

```text
release bundle
+ PostgreSQL backup
+ model source/cache
→ restore PostgreSQL
→ rebuild Qdrant
→ smoke/retrieval verification
```

### Mode C — Fast full recovery

```text
release bundle
+ PostgreSQL backup
+ Qdrant snapshot/volume
+ model cache
→ restore all
→ consistency validation
```

### Mode D — Offline customer recovery

```text
OCI image available locally/private registry
+ PostgreSQL backup
+ verified model cache
+ deployment bundle
→ no Nexus dependency during recovery
```

## Recovery acceptance criteria

A recovery is not complete merely because containers are running. Require:

- PostgreSQL healthy;
- AstraVector ready;
- gRPC `SERVING`;
- expected model SHA256 values;
- document/vector status coherent;
- retrieval of a known recovered document succeeds;
- no unexpected data-loss/reconciliation errors in logs;
- current backup metadata recorded.

## Backup schedule guidance

The repository does not prescribe a universal schedule. Customer RPO/RTO must determine it. At minimum define:

- backup frequency;
- retention period;
- off-host/off-site copy;
- encryption at rest;
- restore test cadence;
- responsible operator;
- alert when backups fail.

A backup that has never been restore-tested should not be treated as proven recovery capability.
