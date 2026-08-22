# AstraIndexator -> AstraVector Proto Mapping

## Purpose

This document defines the future AstraIndexator anti-corruption layer against AstraVector ingestion. AstraIndexator is not implemented yet; this is a development contract/specification.

Canonical wire API:

```text
astravector.embedding.v1.AstraVectorIngestionFacade
```

External implementation rule:

```text
AstraIndexator domain/application DTO
        ↓ mapper + validation
Generated protobuf DTO
        ↓ gRPC
AstraVector
```

Do not hand-maintain duplicate protobuf wire classes in AstraIndexator.

## Responsibility boundary

AstraIndexator owns:

- file/object acquisition;
- parsing;
- OCR;
- normalization;
- document structure extraction;
- LogicalBlock tree creation;
- source location/provenance;
- upload/session orchestration;
- client-side validation/idempotency/retry.

AstraVector owns:

- tokenizer-aware chunking;
- BGE-M3 dense/sparse embedding generation;
- canonical vector/document state;
- outbox;
- Qdrant projection;
- activation/reconciliation;
- retrieval.

## High-level pipeline

```text
Raw file/object
    ↓
Parser/OCR
    ↓
Normalized document
    ↓
LogicalBlock tree
    ↓
local structural validator
    ↓
AstraVector ingestion adapter
    ↓
gRPC
```

## Document identity mapping

| AstraIndexator concept | AstraVector field | Rule |
|---|---|---|
| stable logical document UUID | `document_id` | stable across versions |
| source revision | `document_version` | `> 0`; increment for changed source |
| upstream/business identifier | `external_document_id` | optional; do not replace stable UUID policy with it accidentally |
| title | `title` | source/user title |
| object/file URI | `source_uri` | provenance, not identity unless explicitly chosen |
| source category | `source_type` | adapter-owned mapping |
| MIME type | `mime_type` | actual source MIME type |
| source/content fingerprint | `content_hash` | use documented contract algorithm |
| links | `source_links` | provenance/navigation; no credentials |

AstraVector can derive an ID in some single-call paths when `document_id` is absent, but AstraIndexator should preferably own a stable UUID explicitly so identity does not depend on a mutable URI.

## LogicalBlock mapping

Canonical structure:

```text
block_id
parent_block_id
block_type
text
order_index
source_location
source_links
metadata
```

Recommended local domain model:

```java
record ParsedBlock(
        String id,
        String parentId,
        ParsedBlockType type,
        String normalizedText,
        long order,
        SourceLocation sourceLocation,
        List<SourceLink> sourceLinks,
        Map<String, String> metadata
) {}
```

Mapper validates then builds generated protobuf `LogicalBlock`.

## Block types

Current externally relevant types include:

```text
DOCUMENT
SECTION
SUBSECTION
PARAGRAPH
TABLE
TABLE_ROW
LIST
LIST_ITEM
FAQ_ITEM
CODE_BLOCK
CAPTION
```

AstraIndexator must never emit UNSPECIFIED.

## Structural validation before network call

Validate locally:

- at least one block;
- exactly one `DOCUMENT` root;
- every `block_id` non-blank;
- block IDs unique in document version;
- non-root block has a valid parent;
- no cycles;
- text non-blank;
- deterministic `order_index`;
- parent-child combinations consistent with the current AstraVector contract.

Server validation remains authoritative, but local validation prevents avoidable network round trips.

## SourceLocation

Preserve provenance whenever available:

```text
pageStart/pageEnd
charStart/charEnd
sectionPath
heading
tableId
rowIndex/columnIndex
```

This data later feeds retrieval citations. Parser/OCR should not discard it after normalization.

## Access zone mapping

Future upstream API should assign the indexing scope explicitly.

Recommended AstraIndexator application model:

```java
sealed interface AccessZoneRef permits AccessZoneId, AccessZoneCode {}
record AccessZoneId(UUID value) implements AccessZoneRef {}
record AccessZoneCode(String value) implements AccessZoneRef {}
```

Normal ingestion operation resolves to one effective access zone.

Do not infer access zone from file content, folder names or metadata unless that behavior is a separately approved platform policy.

## TTL mapping

Session Start uses `ttl_days` semantics:

```text
0  -> inherit zone/platform TTL policy
>0 -> explicit relative lifetime in days
```

Do not implement `0 = forever`.

If a future client uses single-call `TtlPolicy`, keep its second-based semantics separate from session `ttl_days`.

## Session API

Preferred production path for larger documents:

```text
StartLogicalDocumentIngestion
AppendLogicalDocumentBlocks × N
FinalizeLogicalDocumentIngestion
GetLogicalDocumentIngestionStatus
GetDocumentVectorStatus
```

Use `AbortLogicalDocumentIngestion` for abandoned active sessions.

### Start mapping

Application input:

```java
record StartIndexingCommand(
        AccessZoneRef accessZone,
        UUID documentId,
        long documentVersion,
        URI sourceUri,
        String fileName,
        String contentHash,
        String idempotencyKey,
        long totalBytesEstimate,
        long totalBlocksEstimate,
        long totalPagesEstimate,
        Map<String, String> metadata,
        long ttlDays
) {}
```

Recommended idempotency key:

```text
astraindexator:{documentId}:{documentVersion}:{contentHash}
```

Same logical retry must reuse the same key.

### Append mapping

Application batch:

```java
record LogicalBlockBatch(
        UUID sessionId,
        long batchIndex,
        List<ParsedBlock> blocks,
        boolean lastBatch,
        String batchContentHash
) {}
```

Operational client target may be kept below server maxima, e.g. roughly half the configured max batch bytes/block count, but those client targets are policy, not wire contract.

`isLastBatch` must not be treated as implicit finalize in the current implementation.

### Finalize mapping

```java
record FinalizeIndexingCommand(
        UUID sessionId,
        String finalContentHash
) {}
```

After Finalize, always inspect ingestion/vector status rather than assuming searchability.

## Hash canonicalization gap

Two cross-language hashes require formal publication before a Java production client should calculate them independently:

```text
batch_content_hash
final_content_hash
```

The AstraVector implementation calculates canonical forms internally, but external consumers should not reverse-engineer Rust serialization and freeze it as a Java contract.

Required follow-up in AstraVector:

```text
exact input field ordering/normalization
exact JSON/text representation
UTF-8 bytes
SHA-256
lowercase hex representation
published golden vectors
```

Until that exists, mark this portion of AstraIndexator implementation as blocked for strict production interoperability.

## Status handling

Current session strings include:

```text
ACTIVE
FINALIZING
COMPLETED
FAILED
ABORTED
EXPIRED
```

Application adapter should map them defensively:

```java
enum IngestionSessionState {
    ACTIVE,
    FINALIZING,
    COMPLETED,
    FAILED,
    ABORTED,
    EXPIRED,
    UNKNOWN
}
```

Keep raw wire string for diagnostics.

## Completion levels

AstraIndexator should distinguish:

```text
SESSION_ACCEPTED
BLOCKS_STAGED
FINALIZED
VECTOR_READY
SEARCHABLE
FAILED
```

Do not report "indexed" merely because Start/Append succeeded.

`GetDocumentVectorStatus` is the consumer authority for vector/search readiness.

## Security metadata

Local profile may use plaintext/insecure transport inside Docker networking. Production must externalize TLS/trust policy.

When AstraVector security is enabled, trusted gateway/service metadata may be required. Do not hard-code shared secrets in source. Inject via secret management and a gRPC client interceptor.

Conceptual flow:

```text
Kubernetes/Docker secret
      ↓
gRPC ClientInterceptor
      ↓
trusted AstraVector metadata
```

## Retry policy

Mutating operations require idempotency-aware retries:

- Start timeout -> retry same idempotency key;
- Append timeout -> replay same batch index + same hash;
- Finalize timeout -> GetStatus before replay;
- `UNAVAILABLE` -> bounded backoff;
- permanent validation/security errors -> no retry;
- ambiguous session state -> reconcile, do not create another document version.

## Acceptance contract for future AstraIndexator

A development milestone is complete only when a real source file proves:

```text
file
 -> parse/OCR
 -> deterministic LogicalBlock tree
 -> session ingestion
 -> vector status/searchable
 -> retrieval
 -> citation traces back to original page/section/source URI
```

And the test must cover at least:

- access zone by code;
- TTL inheritance (`ttlDays=0`);
- explicit finite TTL;
- retry of Start;
- replay of one Append batch;
- Finalize ambiguity recovery;
- malformed tree rejection;
- source location preservation.
