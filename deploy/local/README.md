# AstraDeployment Portable Local Deployment 1.0

This directory is the operator bundle for a reproducible single-node AstraVector deployment.

## Included

- `postgres` — `pgvector/pgvector:pg16`
- `qdrant` — `qdrant/qdrant:v1.14.1`
- `astravector` — private OCI image configured by `.env`
- persistent PostgreSQL, Qdrant and model-cache volumes
- preflight, health, smoke, stop and cleanup controls

Not included in 1.0: AstraIndexator, Kubernetes, Helm, HA databases, public ingress.

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose v2
- access to `registry.astrabase.asia`
- Nexus reader credentials for the model repository, unless a valid model cache is already restored
- current validated baseline requires Apple Silicon/`arm64`; amd64 needs a separately published/validated AstraVector image
- recommended free disk for a cold start: at least 12 GiB, preferably more

## First installation

```bash
cp .env.example .env
```

Set at minimum:

```text
POSTGRES_PASSWORD=<local secret>
ASTRAVECTOR_DB_URL=postgres://astravector_app:<URL-ENCODED-PASSWORD>@postgres:5432/astravector
ASTRAVECTOR_NEXUS_PASSWORD=<reader secret>
```

Do not commit `.env`.

Authenticate Docker separately:

```bash
docker login registry.astrabase.asia -u astra-reader
```

Then:

```bash
make preflight
make start
make health
make smoke
```

`make start` pulls the declared images, verifies the recorded AstraVector digest when available, starts the stack and waits for application readiness.

## Local endpoints

Default loopback-only bindings:

```text
AstraVector gRPC    127.0.0.1:50051
AstraVector HTTP    127.0.0.1:8080
AstraVector metrics 127.0.0.1:9090
Qdrant HTTP         127.0.0.1:6333
```

PostgreSQL is not published to the host by default.

## Health

`make health` verifies:

- PostgreSQL `pg_isready`;
- Qdrant HTTP API from the internal network;
- AstraVector `/ready`;
- standard gRPC health for `astravector.embedding.v1.AstraVectorRuntime` = `SERVING`.

## Functional smoke

`make smoke` uses the real AstraVector contracts, not a mocked API:

1. `AstraVectorIngestionFacade/IndexLogicalDocument`;
2. `GetDocumentVectorStatus` until vectors are ready;
3. `AstraVectorV004Control/ActivateDocumentVersion`;
4. HTTP `POST /api/v1/retrieve`.

It indexes Russian text and asks:

```text
Где AstraVector хранит каноническое состояние документов?
```

PASS requires retrieved evidence containing:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

Evidence files are written under `.smoke/` and ignored by Git.

## Persistence

Stable volumes:

```text
astradeployment-postgres-data
astradeployment-qdrant-data
astradeployment-model-cache
```

Criticality:

```text
PostgreSQL = canonical state; primary recovery asset
Qdrant     = rebuildable projection
model cache = immutable artifact cache; useful for fast/offline recovery
```

## Restart and stop

Normal stop preserves all volumes:

```bash
make stop
```

Remove containers/network while preserving data:

```bash
make cleanup
```

Permanent destructive removal requires explicit confirmation:

```bash
make destroy
```

## Model cache behavior

Cold start: if `astradeployment-model-cache` is empty, AstraVector downloads and verifies BGE-M3 from Nexus.

Warm start: valid cached files are checksum-verified and reused; the ~2.2 GB `model.onnx_data` is not downloaded again.

For customer recovery or constrained networks, restoring a verified model-cache volume before `make start` is an intentional supported operational path. See `recovery/README.md`.

## Known limitations

### Current architecture

The tested AstraVector image is currently `linux/arm64`. This bundle must not be advertised as amd64-ready until an amd64 or multi-arch AstraVector image is published and validated.

### Large cold model transfer

Fresh delivery of `model.onnx_data` through the current public Nexus/Caddy path has experienced transport interruption. HTTP Range/resume is not proven end-to-end. Prefer a persistent/preloaded model cache for repeatable customer installations where connectivity is uncertain.

### Graceful shutdown

The current AstraVector baseline previously returned `ExitCode=137` after `docker stop --time 45`, with `OOMKilled=false`. Compose uses a more conservative stop grace period as an operational mitigation, but this repository does not claim the runtime defect is fixed. Validation must record the actual result.

## Upgrade policy

Never silently replace a validated image identity. For an upgrade:

1. publish a new immutable AstraVector tag;
2. record the new digest;
3. update `.env.example`/spec;
4. run the full AstraDeployment validation task;
5. only then designate the new image as the bundle baseline.

## Recovery

See `recovery/README.md` for empty, fast-cache, PostgreSQL restore and full-fast-restore modes.
