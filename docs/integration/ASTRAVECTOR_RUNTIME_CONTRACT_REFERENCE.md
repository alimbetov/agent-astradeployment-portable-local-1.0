# AstraVector Runtime Contract Reference

## Purpose

This document captures the deployment-relevant AstraVector runtime contract used by AstraDeployment. It is derived from the validated AstraVector image work in `alimbetov/llm2` PR #40 and from the current AstraVector runtime sources. It exists so integration and operations work in AstraDeployment does not depend on tribal knowledge.

## Runtime boundaries

AstraVector exposes three operational interfaces:

- gRPC on `50051`
- internal HTTP on `8080`
- metrics on `9090`

The HTTP boundary includes:

```text
GET  /health
GET  /ready
POST /api/v1/retrieve
```

The gRPC runtime registers reflection and standard gRPC health. The main service names relevant to integrators are:

```text
astravector.embedding.v1.AstraVectorRuntime
astravector.embedding.v1.AstraVectorV004Control
astravector.embedding.v1.AstraVectorIngestionFacade
astravector.embedding.v1.AstraVectorRetrievalFacade
astravector.embedding.v1.AstraVectorAdminFacade
```

## Retrieval boundary

For Spring Boot and other general application clients, prefer the HTTP retrieval boundary:

```text
POST /api/v1/retrieve
```

This keeps callers decoupled from protobuf generation unless they need a gRPC-specific feature.

The request supports:

```text
question
accessZoneId / accessZoneIds
accessZoneCode / accessZoneCodes
callerAccessLevel
profile
maxContexts
filters
enableGraphExpansion
graphMaxHops
graphMaxRelatedContexts
correlationId
```

Important response fields include:

```text
contexts[].matchedText
contexts[].parentText
contexts[].citation.*
contexts[].scores.*
summary.returnedContexts
summary.evidenceStatus
summary.degraded
summary.degradationCodes
```

`callerAccessLevel` is a retrieval visibility input. It is not transport authentication.

## Ingestion boundary

The preferred ingestion contract for AstraIndexator is gRPC:

```text
AstraVectorIngestionFacade/IndexLogicalDocument
```

The contract receives a logical document, not raw files. AstraIndexator is therefore responsible for parsing/OCR and logical structure extraction before calling AstraVector.

Important request concepts:

```text
RequestContext
access_zone_id / access_zone_code
DocumentIdentity
LogicalBlock[]
TokenAwareChunkingOptions
VectorIndexingOptions
metadata
```

The response includes:

```text
DocumentRef
OperationStatus
IndexingSummary
```

For large documents AstraVector also exposes streamed/session-style ingestion operations:

```text
StartLogicalDocumentIngestion
AppendLogicalDocumentBlocks
FinalizeLogicalDocumentIngestion
AbortLogicalDocumentIngestion
GetLogicalDocumentIngestionStatus
```

AstraIndexator should use the single-call or session path according to document size and operational needs, without moving tokenizer/chunking/embedding responsibility outside AstraVector.

## Vector publication and activation

A document is not assumed searchable immediately after ingestion. The deployment smoke path uses:

```text
IndexLogicalDocument
  ->
GetDocumentVectorStatus
  ->
ActivateDocumentVersion
  ->
Retrieve/Search
```

This sequence is intentional and must be preserved in integration tests.

## Persistence invariant

```text
PostgreSQL = canonical state / source of truth
Qdrant     = rebuildable vector/search projection
```

AstraDeployment must never invert this relationship.

Operational consequences:

- PostgreSQL backup is the primary recovery asset.
- Qdrant may be restored for speed, but can be rebuilt.
- image rollback must not delete PostgreSQL data or Qdrant collections as an automatic side effect.

## Runtime environment contract

The current AstraVector image expects external runtime configuration including:

```text
ASTRAVECTOR_DB_URL
ASTRAVECTOR_QDRANT_URL
ASTRAVECTOR_QDRANT_COLLECTION
ASTRAVECTOR_MODEL_REPOSITORY_URL
ASTRAVECTOR_MODEL_DIR
ASTRAVECTOR_MODEL_PATH
ASTRAVECTOR_TOKENIZER_PATH
ASTRAVECTOR_MODEL_SHA256
ASTRAVECTOR_MODEL_DATA_SHA256
ASTRAVECTOR_TOKENIZER_SHA256
ASTRAVECTOR_NEXUS_USERNAME
ASTRAVECTOR_NEXUS_PASSWORD
```

The model cache is expected at:

```text
/models/bge-m3
```

In the portable local deployment these values are provided by `deploy/local/.env` and injected by Docker Compose. The AstraVector OCI image does not store deployment passwords, PostgreSQL connection strings, Qdrant endpoints or machine-specific model-cache state.

The important local fields are:

```text
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
ASTRAVECTOR_DB_URL
ASTRAVECTOR_QDRANT_URL
ASTRAVECTOR_QDRANT_COLLECTION
ASTRAVECTOR_NEXUS_USERNAME
ASTRAVECTOR_NEXUS_PASSWORD
ASTRAVECTOR_MODEL_*_SHA256
```

PostgreSQL must provide the configured database and role. AstraVector owns its application-level schema and migrations inside that database. Qdrant must be reachable; AstraVector owns collection compatibility checks, auto-create behavior and payload index management according to its runtime configuration.

## AstraIndexator handoff summary

AstraIndexator passes parsed logical content to AstraVector. It must not bypass AstraVector by writing rows into PostgreSQL or points into Qdrant.

Recommended minimum lifecycle:

```text
ParsedDocument
  -> LogicalBlock[]
  -> AstraVectorIngestionFacade/IndexLogicalDocument
  -> GetDocumentVectorStatus
  -> AstraVectorV004Control/ActivateDocumentVersion
  -> retrieval proof through POST /api/v1/retrieve
```

AstraIndexator is responsible for:

- acquiring the source file/object/URL;
- parsing and OCR;
- building stable document identity and metadata;
- selecting the access zone provided by the platform boundary;
- preserving idempotency/session metadata for retries.

AstraVector is responsible for:

- tokenizer-aware chunking;
- embedding generation;
- canonical PostgreSQL persistence;
- Qdrant projection creation/rebuild;
- activation/searchability state;
- retrieval evidence.

Required model files:

```text
model.onnx
model.onnx_data
tokenizer.json
```

Verified SHA-256 values for the current baseline:

```text
model.onnx      f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b
model.onnx_data 1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4
tokenizer.json  21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08
```

## Startup semantics

The image entrypoint performs model/dependency bootstrap before executing the Rust runtime. Current sequence:

```text
validate env
-> prepare model dir
-> lock model cache
-> checksum existing artifacts
-> download missing/invalid artifacts
-> checksum downloaded artifacts
-> verify PostgreSQL TCP reachability
-> verify Qdrant TCP reachability
-> exec astravector-runtime
```

The shell bootstrap only proves reachability. Migrations, collection creation/validation, recovery and application readiness remain AstraVector responsibilities.

## Health semantics

Use these concepts distinctly:

```text
/health = process/service alive
/ready  = application ready for traffic
standard gRPC health = service-level serving state
```

Deployment probes and startup scripts should prefer `/ready` or standard gRPC health over checking only that the TCP port is open.

## Security boundary

AstraVector is designed to live on an internal service network. Production deployments should add transport security at the platform boundary according to the customer environment, for example API key, mTLS, gateway policy, or Kubernetes NetworkPolicy.

Do not use `callerAccessLevel` as a replacement for authentication or authorization.

## Current known limitations

The current validated image baseline still has two operational limitations:

1. cold transfer of the large `model.onnx_data` through the current public Nexus/Caddy path can be interrupted;
2. graceful shutdown is not yet fixed in the AstraVector image baseline; forced termination has been observed after the configured grace period.

These are image/runtime issues, not reasons to alter the integration contracts above.

## Source of truth

For implementation-level details, use the current AstraVector repository and especially the image-contract work merged through PR #40. AstraDeployment should mirror these contracts but should not fork or redefine them.
