# AstraIndexator Integration Contract

## Status

AstraIndexator is not implemented yet. This document defines the intended integration boundary between a future AstraIndexator and AstraVector. It is a development contract/specification, not an implementation claim.

Detailed companion documents:

- `ASTRAINDEXATOR_PROTO_MAPPING.md`
- `INGESTION_SESSION_STATE_MACHINE.md`
- `ACCESS_ZONE_AND_TTL_SEMANTICS.md`
- `EXTERNAL_DTO_REFERENCE.md`
- `CONTRACT_GOVERNANCE.md`

## Canonical integration boundary

AstraIndexator should integrate through the public gRPC facade:

```text
astravector.embedding.v1.AstraVectorIngestionFacade
```

Do not create a duplicate custom REST contract between AstraIndexator and AstraVector unless there is a separate architectural decision to do so.

The generated protobuf client should remain the wire-level contract.

## Responsibility split

AstraIndexator owns:

```text
Upload/file/object acquisition
 -> parser
 -> OCR
 -> normalization
 -> structural extraction
 -> LogicalBlock tree
 -> client validation/idempotency/session orchestration
```

AstraVector owns:

```text
tokenizer-aware chunking
embedding generation
canonical vector/document state
outbox
Qdrant projection
activation/reconciliation
retrieval
```

Do not move tokenizer/chunking/BGE-M3 inference into AstraIndexator.

## Public ingestion RPCs

Current relevant facade operations include:

```text
IndexLogicalDocument
StartLogicalDocumentIngestion
AppendLogicalDocumentBlocks
FinalizeLogicalDocumentIngestion
AbortLogicalDocumentIngestion
GetLogicalDocumentIngestionStatus
GetDocumentVectorStatus
DeleteDocumentVectorsFacade
```

For small/medium documents a single-call ingestion path can be sufficient. For larger documents, session ingestion should be treated as the production-oriented path.

## Document identity

AstraIndexator should own a stable document identity policy.

Recommended rules:

- `document_id` is a stable UUID for one logical document;
- `document_version > 0` and increments for a changed source revision;
- `external_document_id` may preserve upstream/business identity;
- `source_uri` is provenance/navigation and should not be the only identity if it can change;
- `content_hash` fingerprints the source/normalized input according to an explicitly documented algorithm;
- retries of one logical operation reuse the same idempotency identity.

AstraVector can derive document identity in some ingestion paths, but AstraIndexator should preferably supply its own stable UUID explicitly.

## Logical document model

AstraIndexator produces ordered logical blocks with fields such as:

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

Current block types include:

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

Local validation should run before the network call:

- non-empty block collection;
- exactly one root `DOCUMENT` block;
- unique non-blank block IDs;
- non-blank text;
- non-UNSPECIFIED type;
- valid parent references;
- acyclic hierarchy;
- deterministic ordering.

Server validation remains authoritative.

## Access-zone contract

Each indexed document version belongs to one effective access zone.

AstraIndexator should pass one of:

```text
access_zone_id
access_zone_code
```

and should not invent authorization or access-zone assignment from file content.

Recommended upstream design:

```text
business/platform layer decides zone
        ↓
AstraIndexator receives zone reference
        ↓
forwards it to AstraVector
```

See `ACCESS_ZONE_AND_TTL_SEMANTICS.md` for code/ID rules.

## TTL contract

For session ingestion the relevant external field is:

```text
ttl_days
```

Semantics:

```text
0  -> inherit zone/platform TTL policy
>0 -> explicit relative lifetime in days
```

`0` must not be exposed as "never expire".

Single-call `TtlPolicy` uses separate semantics/units and must not be conflated with session `ttl_days`.

## Session ingestion lifecycle

Preferred flow for large documents:

```text
parse/OCR
 -> normalize/build LogicalBlock tree
 -> StartLogicalDocumentIngestion
 -> AppendLogicalDocumentBlocks x N
 -> FinalizeLogicalDocumentIngestion
 -> GetLogicalDocumentIngestionStatus as needed
 -> GetDocumentVectorStatus
 -> report readiness/searchability upstream
```

### Start

Recommended explicit idempotency key:

```text
astraindexator:{documentId}:{documentVersion}:{contentHash}
```

Reuse it for retries of the same logical operation.

### Append

Each append batch uses:

```text
ingestion_session_id
blocks[]
batch_index
is_last_batch
batch_content_hash
```

Important current behavior:

```text
is_last_batch is informational only.
FinalizeLogicalDocumentIngestion is still required.
```

Same `batch_index` + same hash is the safe replay shape. Same index + different hash is an integrity conflict.

### Finalize

Finalize transitions the session into finalization and invokes the real ingestion path.

Do not assume:

```text
Finalize RPC success == searchable
```

After finalize, inspect `GetDocumentVectorStatus`.

Current session-finalize activation behavior is not identical to the explicit manual activation sequence used by the local smoke example. Therefore AstraIndexator must observe actual status instead of assuming a lifecycle state.

### Abort

Use Abort for an active session that should not complete. Reconcile status before aborting a session that may already be finalizing/completed.

## Hashing contract gap

The current session protocol requires:

```text
batch_content_hash
final_content_hash
```

AstraVector implementation computes canonical representations internally, but a byte-precise cross-language specification and golden test vectors must be published before a Java AstraIndexator should independently freeze this logic.

Required follow-up artifact:

```text
INGESTION_HASH_CANONICALIZATION specification
+ golden fixtures for Java/Rust parity
```

Until then, treat cross-language strict session hashing as a P0 contract gap.

## Session states

Known current state strings:

```text
ACTIVE
FINALIZING
COMPLETED
FAILED
ABORTED
EXPIRED
```

Because the wire field is currently a string rather than an enum, clients should preserve the raw value and map unknown values to `UNKNOWN` instead of failing deserialization.

## Search readiness

Use:

```text
GetDocumentVectorStatus
```

as the authoritative integration check for vector/search readiness.

Consumer-relevant fields include state/progress/searchability/activation-readiness information.

Do not report a document as searchable merely because Start/Append/Finalize was accepted.

## Retry strategy

Safe mutation retry requires idempotency and state reconciliation:

- Start timeout -> retry same idempotency key;
- Append timeout -> replay same batch index + same hash;
- Finalize timeout -> query status before replay;
- `UNAVAILABLE` -> bounded exponential backoff;
- validation/security failures -> no blind retry;
- ambiguous lifecycle state -> reconcile instead of creating a new document version.

See `INGESTION_SESSION_STATE_MACHINE.md` for the detailed matrix.

## Security

Local deployments may use plaintext service networking. Production transport/security policy should come from AstraDeployment/environment.

If AstraVector trusted gateway/service metadata is enabled, inject it via secrets and a gRPC interceptor. Do not hard-code trust tokens/roles in AstraIndexator source.

## Future deployment model

When AstraIndexator is implemented:

```text
AstraIndexator x N
      |
      | gRPC
      v
AstraVector x N
      |
      +--> PostgreSQL
      +--> Qdrant
```

AstraIndexator should never require direct access to AstraVector PostgreSQL or Qdrant.

If object storage is introduced, AstraIndexator may own it; AstraVector should consume source links/metadata rather than becoming a file-store service.

## Compatibility

AstraIndexator should pin and validate:

- AstraVector protobuf contract revision;
- supported block types;
- configured server limits;
- TTL/access-zone semantics;
- hash canonicalization revision once published;
- retry/error semantics.

Breaking protobuf/semantic changes require a new contract version, not silent reinterpretation.

## Acceptance criteria for future AstraIndexator

The first production-grade E2E should prove:

```text
real file
 -> parse/OCR
 -> deterministic LogicalBlock tree
 -> AstraVector session ingestion
 -> vector status/searchability
 -> retrieval
 -> citation traces back to original source/page/section
```

Minimum edge cases:

- access zone by code;
- TTL inheritance (`ttlDays=0`);
- explicit finite TTL;
- Start retry with same idempotency key;
- Append replay;
- Finalize timeout/status reconciliation;
- malformed logical tree rejection;
- source-location preservation.
