# AstraDeployment

**AstraDeployment Portable Local Deployment 1.0** is the finalized, reproducible single-node deployment baseline for AstraVector on the currently validated `linux/arm64` environment.

Version 1.0 packages the runtime environment around an already-built AstraVector OCI image. It does not build AstraVector from source and does not include AstraIndexator yet.

## Finalized status

```text
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_FINALIZED
```

Finalization record:

- `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_FINALIZATION.md` — frozen baseline, validated identities, accepted limitations and change-control policy.
- `docs/ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_RESULT.md` — latest full Mac Apple Silicon revalidation; verdict `ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_PASS`.

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
make preflight
make start
make health
make smoke
```

Read `deploy/local/README.md` before the first installation.

## Documentation map

### Architecture and validation

- `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_SPEC.md` — architecture and acceptance contract.
- `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_RESULT.md` — original validated deployment evidence.
- `docs/ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_RESULT.md` — repeated local Mac validation evidence.
- `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_FINALIZATION.md` — final frozen release baseline and change-control rules.
- `docs/architecture/PLATFORM_SERVICE_INTERACTIONS.md` — Spring Boot, Python AstraIndexator and AstraVector interaction model.

### Integration contract governance

- `docs/integration/CONTRACT_GOVERNANCE.md` — source-of-truth hierarchy, contract versioning, compatibility and known gaps.
- `docs/integration/ASTRAVECTOR_RUNTIME_CONTRACT_REFERENCE.md` — runtime ports, health, model/bootstrap and public service reference.
- `docs/integration/EXTERNAL_DTO_REFERENCE.md` — consumer DTO catalogue for Spring retrieval and AstraIndexator ingestion.
- `docs/integration/ACCESS_ZONE_AND_TTL_SEMANTICS.md` — consumer guidance for `accessZoneId(s)`, `accessZoneCode(s)`, `callerAccessLevel` and TTL semantics.

### Spring Boot retrieval

- `docs/integration/SPRING_BOOT_RETRIEVAL_INTEGRATION.md` — retrieval HTTP/JSON contract and operational behavior.
- `docs/integration/SPRING_BOOT_EXAMPLE_PROJECT.md` — reference Spring Boot adapter, DTO boundary, correlation and retry model.
- `docs/integration/SPRING_BOOT_CONTRACT_TEST_GUIDE.md` — DTO serialization, access-zone, retry/error, fixture and real AstraDeployment contract tests.

### Future AstraIndexator ingestion

- `docs/integration/ASTRAINDEXATOR_INTEGRATION_CONTRACT.md` — future Python AstraIndexator → AstraVector responsibility and lifecycle contract.
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
External clients / UI
        |
        v
Spring Boot application/API layer
   |                       |
   | retrieval             | upload/indexing orchestration
   v                       v
AstraVector HTTP      Python AstraIndexator
/api/v1/retrieve             |
                              | gRPC ingestion
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
llm2/proto + actual AstraVector server semantics
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

## Validated baseline

```text
AstraVector image:
registry.astrabase.asia/astravector:sha-f6493fa

Digest:
sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40

Validated architecture:
linux/arm64
```

The Mac revalidation passed all documented G1-G15 gates, including real ingestion, activation, retrieval, restart/persistence and cleanup preservation.

The validated retrieval timeout baseline includes:

```text
ASTRAVECTOR_SINGLE_QUERY_DEADLINE_MS=3000
ASTRAVECTOR_GRPC_QUERY_DEADLINE_MS=3000
```

## Known accepted limitations

- AstraVector graceful shutdown can still end with `ExitCode=137`, `OOMKilled=false`; restart/persistence/repeated smoke pass.
- Cold Nexus delivery of the large `model.onnx_data` artifact is not the 1.0 release gate; the verified warm/preloaded model cache is the validated path.
- The current AstraVector image is validated only on `arm64`.

## Ingestion contract stabilization

AstraVector ingestion is usable for client design, while FIX493 in `llm2` is intended to make the cross-language session contract safer by formally stabilizing:

- byte-precise `batch_content_hash` canonicalization and golden vectors;
- byte-precise `final_content_hash` canonicalization and golden vectors;
- typed ingestion session states;
- typed ingestion error reasons.

AstraIndexator may be developed against the documented architecture now, but production code for those four details should follow the final AstraVector contract rather than duplicating internal Rust behavior.

## AstraIndexator to AstraVector handoff

AstraIndexator does not write to AstraVector PostgreSQL or Qdrant directly. It passes already parsed logical document data to AstraVector over gRPC, then observes publication state before declaring the document searchable.

The minimum smoke-proven sequence is:

```text
IndexLogicalDocument
-> GetDocumentVectorStatus
-> ActivateDocumentVersion
-> POST /api/v1/retrieve
```

AstraIndexator supplies document identity, access-zone metadata, source metadata and ordered logical blocks. AstraVector owns tokenizer-aware chunking, BGE-M3 inference, PostgreSQL canonical persistence, Qdrant projection and retrieval ranking.

## Change control

Version 1.0 is treated as a frozen validated baseline. Do not silently replace validated image identities, model hashes, persistence topology, runtime timeouts or external contract semantics.

Any material change requires a new validation cycle and an explicit documentation update. See `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_FINALIZATION.md`.
