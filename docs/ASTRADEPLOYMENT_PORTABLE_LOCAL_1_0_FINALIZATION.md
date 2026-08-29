# AstraDeployment Portable Local Deployment 1.0 — Finalization

## Status

`AstraDeployment Portable Local Deployment 1.0` is finalized as the validated single-node AstraVector deployment baseline for Apple Silicon / Linux `arm64` environments.

This finalization freezes the current deployment scope, operational model, integration documentation and validation evidence. It does not declare Kubernetes, Helm or AstraIndexator as implemented components of version 1.0.

## Final baseline

Validated deployment composition:

```text
AstraDeployment 1.0
├── AstraVector
├── PostgreSQL + pgvector
├── Qdrant
├── persistent BGE-M3 model cache
├── Docker Compose
├── environment/secrets contract
├── preflight/start/health/smoke/stop/cleanup controls
├── recovery documentation
├── operations/security/observability documentation
└── external integration contracts
```

Architecture invariant:

```text
PostgreSQL = canonical state / source of truth
Qdrant     = rebuildable search projection
Model data = immutable runtime artifact cached locally
```

## Validated runtime identity

AstraVector image:

```text
registry.astrabase.asia/astravector:sha-f6493fa
```

Validated digest:

```text
sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
```

Validated platform:

```text
linux/arm64
```

Current bundle must not be advertised as amd64-ready until a matching amd64 or multi-architecture AstraVector image is published and independently validated.

## Validated model artifacts

```text
model.onnx
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b

model.onnx_data
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4

tokenizer.json
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08
```

Warm/preloaded model-cache operation is part of the validated baseline.

Fresh large-file delivery through the current Nexus/Caddy path is not a release gate for this version and remains a documented limitation.

## Functional acceptance

The validated operator path is:

```text
fresh checkout
→ configure .env
→ docker login
→ make preflight
→ make start
→ make health
→ make smoke
```

Functional smoke proves the real integration chain:

```text
IndexLogicalDocument
→ GetDocumentVectorStatus
→ ActivateDocumentVersion
→ POST /api/v1/retrieve
```

Acceptance requires retrieval of the known evidence:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

The latest Mac local revalidation result is:

```text
ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_PASS
```

See:

```text
docs/ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_RESULT.md
```

## Persistence and restart acceptance

The following named volumes are intentionally persistent:

```text
astradeployment-postgres-data
astradeployment-qdrant-data
astradeployment-model-cache
```

Validated restart path:

```text
make stop
→ make start
→ make health
→ make smoke
```

Validated cleanup path:

```text
make cleanup
```

`make cleanup` removes containers/network while preserving persistent volumes.

Destructive deletion requires the explicit guarded path documented by the local operator bundle.

## Runtime timeout baseline

The validated Mac deployment required:

```text
ASTRAVECTOR_SINGLE_QUERY_DEADLINE_MS=3000
ASTRAVECTOR_GRPC_QUERY_DEADLINE_MS=3000
```

The first value was required to prevent the single-query planner from falling back to the image default of `1000 ms`, which reproduced HTTP retrieval `504` during local revalidation.

Any future change to these timeout defaults must be revalidated with the functional smoke path.

## External integration model

The target service interaction model is:

```text
External clients / UI
        ↓
Spring Boot application/API layer
   ├── retrieval → AstraVector HTTP /api/v1/retrieve
   └── upload/indexing orchestration → AstraIndexator
                                      ↓
                               AstraVector gRPC ingestion
```

AstraIndexator is planned as a Python service responsible for document acquisition, parsing/OCR and production of logical blocks.

Spring Boot is the external business/API boundary responsible for authentication, authorization, access-zone resolution, external DTOs, orchestration, correlation and retrieval integration.

AstraVector remains responsible for tokenizer-aware chunking, embeddings, canonical vector state, projection publication and retrieval.

See:

```text
docs/architecture/PLATFORM_SERVICE_INTERACTIONS.md
```

## Contract source of truth

Consumer documentation follows this hierarchy:

```text
llm2/proto + actual AstraVector server semantics
        ↓
AstraDeployment integration documentation
        ↓
Spring Boot / AstraIndexator implementations
```

AstraDeployment must never redefine wire semantics that contradict AstraVector.

The main consumer-facing contract documents are:

```text
docs/integration/CONTRACT_GOVERNANCE.md
docs/integration/ASTRAVECTOR_RUNTIME_CONTRACT_REFERENCE.md
docs/integration/EXTERNAL_DTO_REFERENCE.md
docs/integration/ACCESS_ZONE_AND_TTL_SEMANTICS.md
docs/integration/SPRING_BOOT_RETRIEVAL_INTEGRATION.md
docs/integration/SPRING_BOOT_EXAMPLE_PROJECT.md
docs/integration/SPRING_BOOT_CONTRACT_TEST_GUIDE.md
docs/integration/ASTRAINDEXATOR_INTEGRATION_CONTRACT.md
docs/integration/ASTRAINDEXATOR_PROTO_MAPPING.md
docs/integration/INGESTION_SESSION_STATE_MACHINE.md
```

## Operational documentation baseline

The following documents form the operator baseline for version 1.0:

```text
docs/operations/SERVER_INSTALLATION_RUNBOOK.md
docs/operations/BACKUP_RESTORE_RUNBOOK.md
docs/operations/TROUBLESHOOTING_GUIDE.md
docs/operations/SECURITY_BASELINE.md
docs/operations/OBSERVABILITY_GUIDE.md
docs/operations/PLATFORM_DEPLOYMENT_GUIDE.md
docs/operations/DEVOPS_LEARNING_AND_OPERATIONS_GUIDE.md
deploy/local/recovery/README.md
```

## Known limitations accepted at finalization

### AstraVector graceful shutdown

The validated AstraVector image can still exit with:

```text
ExitCode=137
OOMKilled=false
```

after Compose stop. PostgreSQL stops cleanly and Qdrant may report signal-derived exit status. Restart, persistence and repeated smoke pass.

This is classified as an AstraVector lifecycle defect, not a failure of the current functional deployment baseline.

### Cold Nexus large-file transfer

Fresh download of the large `model.onnx_data` artifact through the current Nexus/Caddy path has previously experienced interrupted transfers. Warm/preloaded verified model-cache operation is therefore the validated deployment/recovery path for this version.

### Architecture support

Only `arm64` has been validated for the current AstraVector image identity.

### Scope exclusions

The following are explicitly outside AstraDeployment Portable Local Deployment 1.0:

```text
AstraIndexator runtime
Kubernetes deployment
Helm chart
HA PostgreSQL
HA Qdrant
public ingress
multi-node scheduling
customer-specific IAM implementation
```

## Change control after finalization

Version 1.0 is now treated as a frozen validated baseline.

Any change to one of the following requires a new validation cycle:

- AstraVector image tag or digest;
- PostgreSQL major image baseline;
- Qdrant version;
- model files or SHA-256 values;
- runtime ports;
- persistence topology;
- access-zone semantics;
- retrieval DTO semantics;
- ingestion DTO semantics;
- timeout defaults;
- startup/readiness/smoke behavior.

Do not silently mutate the baseline.

Recommended evolution model:

```text
1.0.x  documentation-only corrections / non-contract operator fixes
1.1.x  portable server/deployment improvements that preserve external contracts
2.x    Kubernetes/Helm or materially different deployment topology
```

Application-contract changes remain governed by AstraVector contract versioning and must be synchronized into AstraDeployment documentation after validation.

## Handover decision

AstraDeployment Portable Local Deployment 1.0 is ready to be used as:

- the local/reference AstraVector runtime for AstraIndexator development;
- the integration environment for Spring Boot retrieval work;
- the baseline for later full Astra Platform Compose integration;
- the reference source for future Kubernetes/Helm translation.

The next product-development stream may proceed independently with AstraIndexator while this repository remains the frozen deployment and integration reference baseline.

## Final verdict

```text
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_FINALIZED
```
