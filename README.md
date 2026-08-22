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

## Documentation map

### Architecture and validation

- `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_SPEC.md` — architecture and acceptance contract.
- `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_RESULT.md` — validated deployment evidence.

### Integration contracts

- `docs/integration/SPRING_BOOT_RETRIEVAL_INTEGRATION.md` — recommended Spring Boot integration with AstraVector retrieval.
- `docs/integration/ASTRAINDEXATOR_INTEGRATION_CONTRACT.md` — future AstraIndexator → AstraVector ingestion boundary.

### Deployment and operations

- `docs/operations/PLATFORM_DEPLOYMENT_GUIDE.md` — how to install AstraDeployment on a server and how the contract maps to future Kubernetes deployments.
- `docs/operations/DEVOPS_LEARNING_AND_OPERATIONS_GUIDE.md` — practical Docker/Compose/health/persistence/troubleshooting concepts for developers operating the platform.
- `deploy/local/recovery/README.md` — recovery modes and persistence guidance.

## Current scope

```text
AstraDeployment 1.0
├── AstraVector
├── PostgreSQL + pgvector
├── Qdrant
├── BGE-M3 model cache
└── Docker Compose operator bundle
```

AstraIndexator, Kubernetes and Helm remain future milestones; their integration/deployment contracts are documented without claiming they are already implemented.
