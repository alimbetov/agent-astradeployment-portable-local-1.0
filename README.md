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
- external integration contracts for Spring Boot retrieval and future AstraIndexator ingestion
- server installation, security, observability, troubleshooting and backup/restore documentation

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

### Integration contract governance

- `docs/integration/CONTRACT_GOVERNANCE.md` — source-of-truth hierarchy, contract versioning, compatibility and known gaps.
- `docs/integration/ASTRAVECTOR_RUNTIME_CONTRACT_REFERENCE.md` — runtime ports, health, model/bootstrap and public service reference.
- `docs/integration/EXTERNAL_DTO_REFERENCE.md` — consumer DTO catalogue for Spring retrieval and AstraIndexator ingestion.
- `docs/integration/ACCESS_ZONE_AND_TTL_SEMANTICS.md` — authoritative consumer guidance for `accessZoneId(s)`, `accessZoneCode(s)`, `callerAccessLevel` and TTL semantics.

### Spring Boot retrieval

- `docs/integration/SPRING_BOOT_RETRIEVAL_INTEGRATION.md` — retrieval HTTP/JSON contract and operational behavior.
- `docs/integration/SPRING_BOOT_EXAMPLE_PROJECT.md` — reference Spring Boot adapter, DTO boundary, correlation and retry model.
- `docs/integration/SPRING_BOOT_CONTRACT_TEST_GUIDE.md` — DTO serialization, access-zone, retry/error, fixture and real AstraDeployment contract tests.

### Future AstraIndexator ingestion

- `docs/integration/ASTRAINDEXATOR_INTEGRATION_CONTRACT.md` — future AstraIndexator → AstraVector responsibility and lifecycle contract.
- `docs/integration/ASTRAINDEXATOR_PROTO_MAPPING.md` — detailed application-to-generated-protobuf mapping and validation rules.
- `docs/integration/INGESTION_SESSION_STATE_MACHINE.md` — Start/Append/Finalize/Abort/Status state machine and retry/recovery behavior.

### Deployment and operations

Start here when installing or operating the platform:

- `docs/operations/SERVER_INSTALLATION_RUNBOOK.md` — deterministic single-node Linux server installation and acceptance checklist.
- `docs/operations/BACKUP_RESTORE_RUNBOOK.md` — PostgreSQL-first backup/recovery strategy, model-cache recovery and Qdrant rebuild/fast-restore modes.
- `docs/operations/TROUBLESHOOTING_GUIDE.md` — infrastructure-to-application diagnostic order and evidence collection.
- `docs/operations/SECURITY_BASELINE.md` — secrets, image supply chain, private networking, access-zone security and host/container hardening baseline.
- `docs/operations/OBSERVABILITY_GUIDE.md` — health/readiness/smoke, logs, metrics, correlation IDs, dashboard and alerting model.
- `docs/operations/PLATFORM_DEPLOYMENT_GUIDE.md` — general deployment architecture and future Kubernetes mapping.
- `docs/operations/DEVOPS_LEARNING_AND_OPERATIONS_GUIDE.md` — practical Docker/Compose/health/persistence concepts for developers operating the platform.
- `deploy/local/recovery/README.md` — local recovery modes and persistence guidance.

## External contract model

```text
                         Astra Platform Contract
                                  |
              +-------------------+-------------------+
              |                                       |
       Retrieval Contract                       Ingestion Contract
              |                                       |
        HTTP / JSON                              Protobuf / gRPC
              |                                       |
       Spring Boot apps                           AstraIndexator
              |                                       |
              +-------------------+-------------------+
                                  v
                             AstraVector
                                  |
                         +--------+--------+
                         |                 |
                    PostgreSQL          Qdrant
                  source of truth   rebuildable projection
```

Contract source-of-truth hierarchy:

```text
llm2/proto + server semantics
        ↓
AstraDeployment consumer documentation
        ↓
Spring Boot / AstraIndexator implementations
```

AstraDeployment documents and version-controls the consumer contract; it must not invent behavior that AstraVector does not guarantee.

## Current scope

```text
AstraDeployment 1.0
├── AstraVector
├── PostgreSQL + pgvector
├── Qdrant
├── BGE-M3 model cache
├── Docker Compose operator bundle
├── versioned integration documentation
└── operational runbooks/security/observability baseline
```

AstraIndexator, Kubernetes and Helm remain future milestones; their integration/deployment contracts are documented without claiming they are already implemented.

## Important contract gaps before AstraIndexator production implementation

The current AstraVector API is sufficiently mature to design clients, but several cross-service details are being formally stabilized in `llm2` before multiple independent ingestion clients rely on them:

- byte-precise `batch_content_hash` canonicalization + golden vectors;
- byte-precise `final_content_hash` canonicalization + golden vectors;
- typed ingestion-session state/error reasons;
- explicitly versioned session activation semantics.

These are documented as gaps rather than silently reverse-engineered into client code.
