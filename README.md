# AstraDeployment

**AstraDeployment Portable Local Deployment 1.0** is the reproducible single-node deployment product for AstraVector.

Version 1.0 packages the runtime environment around an already-built AstraVector OCI image. It does not build AstraVector from source and does not include AstraIndexator yet.

## Included

- AstraVector runtime image from the private Astra registry
- PostgreSQL + pgvector as canonical persistence
- Qdrant as rebuildable search projection
- persistent BGE-M3 model cache
- Docker Compose topology
- environment/secrets contract
- health and functional smoke scripts
- persistence/recovery runbook

## Architecture invariant

```text
PostgreSQL = canonical state / source of truth
Qdrant     = rebuildable search projection
Model data = immutable runtime artifact cached locally
```

## Quick path

```bash
cd deploy/local
cp .env.example .env
# edit .env and provide secrets

docker login registry.astrabase.asia -u astra-reader
./scripts/start.sh
./scripts/health.sh
./scripts/smoke.sh
```

Read `deploy/local/README.md` before the first installation.

The system architecture and acceptance contract are defined in `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_SPEC.md`.
