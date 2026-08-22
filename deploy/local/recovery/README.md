# AstraDeployment 1.0 Recovery Runbook

## Recovery invariant

```text
PostgreSQL = canonical state / source of truth
Qdrant     = rebuildable search projection
Model cache = runtime artifact cache
```

Do not treat the Qdrant volume as the only copy of business/document state.

## Mode A — Empty service

Use when creating a new clean AstraVector environment.

Required:

- AstraVector image access;
- `.env` configuration/secrets;
- Nexus reader access, unless the model cache is preloaded.

Procedure:

```bash
cd deploy/local
cp .env.example .env
# fill secrets
docker login registry.astrabase.asia -u astra-reader
make start
make smoke
```

This creates new PostgreSQL, Qdrant and model-cache volumes.

## Mode B — Fast rebuild with preloaded model cache

Use when network delivery of the ~2.2 GB model data is undesirable.

Required:

- AstraVector image;
- `.env` configuration/secrets;
- verified BGE-M3 cache archive or existing Docker volume.

Expected model files:

```text
model.onnx
model.onnx_data
tokenizer.json
```

Required SHA-256:

```text
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b  model.onnx
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4  model.onnx_data
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08  tokenizer.json
```

A generic named-volume export can be created with an ephemeral container:

```bash
docker run --rm \
  -v astradeployment-model-cache:/source:ro \
  -v "$PWD":/backup \
  alpine:3.22 \
  sh -c 'cd /source && tar czf /backup/astradeployment-model-cache.tgz .'
```

Restore into an empty named volume:

```bash
docker volume create astradeployment-model-cache
docker run --rm \
  -v astradeployment-model-cache:/target \
  -v "$PWD":/backup:ro \
  alpine:3.22 \
  sh -c 'cd /target && tar xzf /backup/astradeployment-model-cache.tgz'
```

Then run `make start`. AstraVector bootstrap must verify the cache before runtime startup.

## Mode C — Restore service with documents

Use when canonical document/application state must survive a host loss.

Primary asset: PostgreSQL backup.

A minimal logical backup example:

```bash
docker compose --env-file ../.env -f ../docker-compose.astravector.yml \
  exec -T postgres pg_dump \
  -U astravector_app -d astravector -Fc > astravector.dump
```

Restore into a clean PostgreSQL volume using the matching PostgreSQL major version and credentials, then start AstraVector. Qdrant may be restored separately or rebuilt using the AstraVector recovery/reconciliation mechanisms from canonical PostgreSQL state.

Do not improvise direct Qdrant reconstruction logic in AstraDeployment.

## Mode D — Full fast restore

Use when the shortest recovery time is preferred.

Restore:

1. PostgreSQL canonical data;
2. Qdrant storage/snapshot if available;
3. verified model cache;
4. declared AstraVector image and `.env`.

Then:

```bash
make start
make health
make smoke
```

## Qdrant recovery policy

Qdrant is a projection. If its data is missing or inconsistent but PostgreSQL is intact, follow the AstraVector-supported compatibility/audit/rebuild/reconciliation procedure. AstraDeployment does not redefine that application recovery contract.

## What must be backed up first

Priority order:

1. PostgreSQL backup — critical.
2. Deployment `.env`/customer secrets — store in the customer's secret-management process, not in this repository.
3. Model cache — optional but highly useful for fast/offline recovery.
4. Qdrant snapshot/volume — optional acceleration for recovery.

Never rely on writable container layers as backup storage.
