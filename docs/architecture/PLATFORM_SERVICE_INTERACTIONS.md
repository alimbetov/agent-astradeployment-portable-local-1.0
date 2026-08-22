# Astra Platform Service Interactions

## Purpose

This document defines the intended interaction model between external clients, the Spring Boot application layer, AstraIndexator, and AstraVector.

It is an architectural integration guide for future service development. AstraVector wire-level behavior remains sourced from `alimbetov/llm2` protobuf and runtime semantics; this document defines how platform services should use those contracts without coupling to AstraVector internals.

## High-level topology

```text
External clients / UI
        |
        v
+---------------------+
|    Spring Boot      |
| external API layer  |
+----+------------+---+
     |            |
     |            | indexing command / upload orchestration
     |            v
     |      +------------------+
     |      | AstraIndexator   |
     |      |     Python       |
     |      +--------+---------+
     |               | gRPC ingestion
     |               v
     |        +------------------+
     +------->|   AstraVector    |
 retrieval   +--------+---------+
                      |
              +-------+-------+
              |               |
              v               v
         PostgreSQL         Qdrant
       canonical state   search projection
```

## Service responsibilities

### Spring Boot

Spring Boot is the external application/API boundary.

Primary responsibilities:

- expose external HTTP APIs to frontend, partner, or enterprise clients;
- authenticate callers;
- authorize requested operations;
- resolve which access zones the caller is allowed to use;
- orchestrate document upload/indexing jobs through AstraIndexator;
- send retrieval requests to AstraVector;
- map platform DTOs to external API DTOs;
- propagate correlation IDs;
- apply transport timeout/retry policy;
- optionally compose retrieved contexts into a higher-level LLM answer.

Spring Boot must not:

- write directly to AstraVector PostgreSQL tables;
- access Qdrant directly for business retrieval;
- generate AstraVector vector embeddings;
- reproduce AstraVector chunking logic;
- act as the primary parser/OCR service.

### AstraIndexator

AstraIndexator is a Python service responsible for document acquisition and logical structure extraction.

Primary responsibilities:

```text
file / object / URL
    -> acquire
    -> parse
    -> OCR when needed
    -> normalize document structure
    -> ParsedDocument
    -> LogicalBlock[]
    -> AstraVector ingestion facade
```

AstraIndexator owns:

- file ingestion;
- parser adapters;
- OCR adapters;
- document-type detection;
- structural extraction;
- page/section/table location metadata;
- source links;
- stable document identity mapping;
- ingestion-session orchestration for large documents;
- bounded retries and replay handling;
- Python-side implementation of versioned hash contracts once FIX493 is finalized.

AstraIndexator must not own:

- tokenizer-aware chunking;
- BGE-M3 inference;
- dense/sparse vector generation;
- Qdrant schema or search behavior;
- AstraVector internal PostgreSQL persistence;
- retrieval ranking.

### AstraVector

AstraVector is the semantic/vector runtime.

It owns:

- tokenizer-aware chunking;
- embedding generation;
- document/vector lifecycle;
- canonical vector/application state in PostgreSQL;
- Qdrant projection;
- activation/searchability lifecycle;
- access-zone filtering at retrieval time;
- retrieval and evidence return;
- session-ingestion state machine.

## External API flow: document upload

Recommended external API flow:

```text
Client
  |
  | POST /api/documents
  v
Spring Boot
  |
  | authenticate + authorize
  | resolve access zone
  | create job/correlation ID
  v
AstraIndexator
  |
  | parse/OCR
  | build ParsedDocument
  | map to LogicalBlock[]
  v
AstraVectorIngestionFacade
  |
  | session ingestion / indexing
  v
PostgreSQL + Qdrant
```

Spring Boot should return a platform-level job/document identifier rather than block until all parsing, embedding, publication and activation work finishes.

Recommended public API shape:

```text
POST /api/documents
GET  /api/documents/{documentId}/status
DELETE /api/documents/{documentId}
```

Exact external DTOs are owned by the Spring Boot API contract, not by AstraVector protobuf.

## Small-document ingestion

For sufficiently small parsed documents, AstraIndexator may use:

```text
IndexLogicalDocument
```

Conceptual flow:

```text
ParsedDocument
  -> LogicalBlock[]
  -> IndexLogicalDocument
  -> GetDocumentVectorStatus
  -> ActivateDocumentVersion
```

The threshold for using single-call ingestion vs session ingestion should be an AstraIndexator configuration concern and should not change AstraVector semantics.

## Large-document ingestion

Large documents should use the AstraVector session API:

```text
StartLogicalDocumentIngestion
        |
        v
AppendLogicalDocumentBlocks(batch 0)
        |
        v
AppendLogicalDocumentBlocks(batch 1)
        |
       ...
        |
        v
FinalizeLogicalDocumentIngestion
        |
        v
GetLogicalDocumentIngestionStatus
```

AstraIndexator is responsible for preserving:

- `ingestion_session_id`;
- `batch_index`;
- `idempotency_key`;
- `batch_content_hash`;
- `final_content_hash`;
- `document_id`;
- `document_version`;
- correlation metadata.

After FIX493, hash calculation and typed ingestion state/error semantics must follow the versioned public contract and golden vectors, not AstraVector Rust internals.

## Safe retry model for AstraIndexator

### Start timeout

```text
Start request sent
    -> response lost
```

AstraIndexator should retry the same logical operation with the same idempotency key.

### Append timeout

For the same batch:

```text
same ingestion_session_id
same batch_index
same canonical content
same batch_content_hash
```

A replay with matching identity/hash is expected to be safe.

A replay using the same `batch_index` but different content/hash must be treated as an integrity conflict and must not be silently retried with modified content.

### Finalize timeout

Do not assume failure.

Preferred flow:

```text
Finalize timeout
    -> GetLogicalDocumentIngestionStatus
    -> reconcile actual state
    -> replay finalize only when contract permits
```

## Access-zone ownership

Spring Boot is the main business authorization boundary.

Recommended flow:

```text
Authenticated principal
       |
       v
Spring authorization
       |
       v
Allowed business scopes
       |
       v
resolved accessZoneId(s) / accessZoneCode(s)
       |
       v
AstraVector request
```

Important distinction:

```text
transport authentication != callerAccessLevel
business authorization   != access-zone field itself
```

AstraVector access-zone fields constrain retrieval/indexing scope, but the external application must not use them as a substitute for authenticating and authorizing the caller.

### Ingestion

AstraIndexator receives the already-approved target access zone from the orchestration context. It must not invent access-zone assignment.

Expected ingestion inputs include the singular target form supported by the AstraVector ingestion API:

```text
access_zone_id
access_zone_code
```

### Retrieval

Spring Boot may use:

```text
accessZoneId
accessZoneIds
accessZoneCode
accessZoneCodes
```

Rules and edge cases are defined in `ACCESS_ZONE_AND_TTL_SEMANTICS.md`.

Spring Boot should normally send one selector family when possible. If ID and code selector families are combined, the effective sets must remain consistent with AstraVector contract semantics.

## TTL ownership and flow

TTL is part of document/vector lifecycle, not an HTTP cache control mechanism.

### External client

The external API may expose a business retention policy such as:

```text
retentionDays
expiresAt
retentionPolicy
```

The Spring Boot external API should translate business retention configuration into a platform-level indexing command.

### Spring Boot to AstraIndexator

Spring Boot passes the intended indexing lifecycle policy as job metadata. AstraIndexator maps that policy to the supported AstraVector ingestion contract.

### AstraIndexator to AstraVector

Depending on ingestion path:

```text
single-call ingestion -> TtlPolicy
session ingestion     -> ttl_days
```

The exact meaning of absent/zero/default values must follow `ACCESS_ZONE_AND_TTL_SEMANTICS.md` and the current AstraVector contract.

AstraIndexator must not independently delete Qdrant points on TTL expiry. AstraVector owns vector lifecycle and projection cleanup/reconciliation.

## Retrieval flow

Recommended retrieval path:

```text
Client
  |
  | question + business context
  v
Spring Boot
  |
  | authenticate
  | authorize
  | resolve allowed zones
  | assign correlation ID
  v
POST AstraVector /api/v1/retrieve
  |
  v
AstraVector
  |
  | search/filter/rank/hydrate
  v
contexts + citations + summary
  |
  v
Spring Boot
  |
  | map to public DTO
  | optional LLM composition
  v
Client
```

Spring Boot should consume semantic retrieval outcomes, not only HTTP status.

Important fields include:

```text
contexts[].matchedText
contexts[].parentText
contexts[].citation
contexts[].scores
summary.evidenceStatus
summary.degraded
summary.degradationCodes
```

An empty/insufficient evidence response is a valid semantic outcome and must not automatically be treated as transport failure.

## Spring Boot to AstraVector contract

Preferred first integration boundary:

```text
HTTP POST /api/v1/retrieve
```

Spring Boot adapter layout:

```text
web/controller
    -> application service
    -> AstraVectorRetrievalPort
    -> AstraVector HTTP adapter
```

Do not leak raw AstraVector DTOs through every business layer. Map the infrastructure DTOs into application-owned result objects.

## Spring Boot to AstraIndexator contract

Spring Boot should treat AstraIndexator as an asynchronous indexing subsystem.

Recommended logical commands:

```text
CreateIndexingJob
GetIndexingJobStatus
CancelIndexingJob
ReindexDocument
```

The transport between Spring Boot and AstraIndexator may initially be HTTP/JSON. A queue/event transport can be added later if operational needs justify it.

The service boundary should remain stable regardless of transport:

```text
Spring owns external business API
AstraIndexator owns document-processing workflow
AstraVector owns semantic/vector lifecycle
```

## Correlation and trace identifiers

One correlation ID should be propagated end-to-end when possible:

```text
external request
    -> Spring Boot
    -> AstraIndexator job
    -> AstraVector request/context
```

Recommended logging keys:

```text
correlation_id
document_id
document_version
ingestion_session_id
access_zone_id
job_id
```

Do not log raw confidential document content by default.

## Failure ownership

### Spring Boot failures

Examples:

- caller not authenticated;
- caller lacks permission;
- invalid external DTO;
- downstream timeout;
- unavailable AstraIndexator/AstraVector.

Spring Boot owns external HTTP error mapping.

### AstraIndexator failures

Examples:

- unsupported file type;
- parser failure;
- OCR failure;
- malformed structural output;
- AstraVector ingestion rejected;
- session expired;
- hash mismatch;
- indexing job cancelled.

AstraIndexator owns job-state and document-processing error representation.

### AstraVector failures

Examples:

- invalid ingestion contract;
- access-zone validation failure;
- ingestion session conflict;
- canonical hash mismatch;
- vector/indexing dependency failure;
- retrieval dependency degradation.

Spring Boot and AstraIndexator must map these into their own domain error models rather than exposing internal Rust messages directly to external users.

## Data ownership

```text
Spring Boot DB
    = external users/business jobs/business authorization/application state

AstraIndexator DB
    = indexing jobs/parser/OCR/workflow state/source-object references

AstraVector PostgreSQL
    = canonical semantic/vector/document-version state

Qdrant
    = rebuildable search projection
```

No service should bypass another service's contract by directly writing its database.

## Security boundary

Recommended production boundary:

```text
Internet / enterprise clients
        |
        v
Spring Boot / gateway
        |
    internal network
     /          \
    v            v
AstraIndexator  AstraVector
```

AstraVector should remain an internal service unless a separate security design explicitly exposes it.

AstraIndexator should also normally remain internal because it processes uploaded documents and interacts with AstraVector ingestion APIs.

## Deployment mapping

### Current local deployment

Current AstraDeployment 1.0 contains:

```text
AstraVector
PostgreSQL
Qdrant
model cache
```

Spring Boot and AstraIndexator are external to the current bundle.

### Future full Compose

```text
spring-api
astraindexator
astravector
postgres
qdrant
object storage
```

Services communicate through internal Compose DNS/service names.

### Future Kubernetes

```text
Spring Boot Deployment
AstraIndexator Deployment x N
AstraVector Deployment x N
Services
Secrets
ConfigMaps
PVC/object storage
external or bundled PostgreSQL/Qdrant
```

The same service contracts must survive migration from Compose to Kubernetes.

## Contract source-of-truth hierarchy

```text
AstraVector protobuf + runtime semantics in llm2
        |
        v
AstraDeployment consumer contract documentation
        |
        +------------------+
        |                  |
        v                  v
Python AstraIndexator   Spring Boot
```

No consumer should reverse-engineer AstraVector persistence or Rust implementation when a public contract exists.

## Related documentation

- `docs/integration/CONTRACT_GOVERNANCE.md`
- `docs/integration/EXTERNAL_DTO_REFERENCE.md`
- `docs/integration/ASTRAINDEXATOR_INTEGRATION_CONTRACT.md`
- `docs/integration/ASTRAINDEXATOR_PROTO_MAPPING.md`
- `docs/integration/INGESTION_SESSION_STATE_MACHINE.md`
- `docs/integration/SPRING_BOOT_RETRIEVAL_INTEGRATION.md`
- `docs/integration/SPRING_BOOT_EXAMPLE_PROJECT.md`
- `docs/integration/ACCESS_ZONE_AND_TTL_SEMANTICS.md`
- `docs/operations/SECURITY_BASELINE.md`
- `docs/operations/OBSERVABILITY_GUIDE.md`

## Implementation status

Current status:

```text
AstraVector               implemented and deployment-validated
AstraDeployment local     implemented and validated
Spring Boot external API  architecture/contract stage
AstraIndexator Python     architecture/contract stage
```

The ingestion hash/state/error portion remains subject to FIX493 stabilization before being treated as a frozen cross-language production contract.
