# AstraIndexator Integration Contract

## Status

AstraIndexator is not implemented yet. This document defines the integration boundary that AstraDeployment and AstraVector should expect from a future AstraIndexator. It is intentionally a contract/specification, not an implementation claim.

## Responsibility split

AstraIndexator owns document acquisition and structural extraction:

```text
Upload / file / object
  ->
AstraIndexator
  -> parser / OCR / structural extraction
  -> LogicalBlock[]
  -> AstraVector ingestion facade
```

AstraVector continues to own:

- tokenizer-aware chunking;
- dense/sparse embedding generation;
- persistence of canonical vector metadata/state in PostgreSQL;
- outbox publication;
- Qdrant projection;
- retrieval.

Do not move tokenizer/chunking/BGE-M3 inference into AstraIndexator.

## Required AstraVector API

Preferred integration endpoint:

```text
astravector.embedding.v1.AstraVectorIngestionFacade
```

Core RPCs:

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

For a first AstraIndexator version, `IndexLogicalDocument` is sufficient for reasonably sized parsed documents. Streaming/session-based ingestion should be used when document size or block count justifies it.

## Logical document contract

AstraIndexator must produce a stable document identity and ordered logical blocks.

Key document fields:

```text
external_document_id
document_id
document_version
title
source_uri
source_type
mime_type
content_hash
source_links[]
```

Each logical block should provide:

```text
block_id
parent_block_id
block_type
text
order_index
source_location
source_links[]
metadata
```

Expected block types include:

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

## Identity rules

AstraIndexator must make retries idempotent.

Recommended rules:

- `document_id` stays stable for the logical document;
- `document_version` increments when source content changes;
- `content_hash` is calculated over the normalized source/parsed content according to one documented algorithm;
- `block_id` must be stable for equivalent parsing where practical;
- `idempotency_key` must uniquely identify one ingestion attempt/version;
- `correlation_id` must be propagated from the upstream request.

## Access boundary

AstraIndexator must provide one of:

```text
access_zone_id
access_zone_code
```

and must not invent caller authorization. Access zone assignment belongs to the platform/customer security model.

## Activation

Recommended default integration flow:

```text
parse
 -> IndexLogicalDocument / finalize
 -> wait for GetDocumentVectorStatus
 -> ready_to_activate
 -> ActivateDocumentVersion
```

Automatic activation may be supported later, but the deployment documentation should keep manual/explicit activation as the clearer reference behavior until production policy is defined.

## Failure semantics

AstraIndexator must distinguish:

- parsing/OCR failure;
- malformed logical document;
- AstraVector unavailable;
- ingestion rejected;
- vector publication incomplete;
- Qdrant/outbox failure;
- activation failure.

Do not report a document as searchable merely because the ingestion RPC accepted it.

A document is search-ready only after the AstraVector status contract says it is searchable/ready and activation policy has completed.

## Retry strategy

Safe retry principles:

- retry transient transport failures with bounded exponential backoff;
- reuse the same idempotency key for retrying the same logical operation;
- do not silently create a new document version after a timeout;
- query ingestion/vector status before replaying an ambiguous request;
- never retry permanent validation failures indefinitely.

## Future deployment contract

When AstraIndexator exists, AstraDeployment should add it as another independently scalable service:

```text
AstraIndexator x N
      |
      v
AstraVector service x N
      |
      +--> PostgreSQL
      +--> Qdrant
```

AstraIndexator should not require direct access to AstraVector's PostgreSQL or Qdrant databases. Its contract boundary is the AstraVector API.

If object storage is introduced, AstraIndexator may own direct access to that storage, but AstraVector should consume source links/metadata rather than becoming a file-storage service.

## Compatibility policy

AstraIndexator should pin and validate:

- AstraVector gRPC contract version;
- expected tokenizer/embedding contract where applicable;
- supported block types;
- maximum request/batch size;
- timeout policy.

Breaking proto changes require a new versioned contract rather than silent field reinterpretation.

## Acceptance criteria for future AstraIndexator

AstraIndexator integration is accepted when an end-to-end test proves:

```text
real file
 -> parse/OCR
 -> LogicalBlock[]
 -> AstraVector ingestion
 -> vector publication
 -> activation
 -> retrieval question
 -> evidence references original document/source location
```

The evidence must retain enough source metadata to trace a retrieval result back to the original document/page/section when that information was available during parsing.
