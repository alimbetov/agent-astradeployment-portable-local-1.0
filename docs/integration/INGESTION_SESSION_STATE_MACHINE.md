# Ingestion Session State Machine

## Purpose

This document describes the current externally relevant lifecycle of AstraVector session-based logical-document ingestion for the future AstraIndexator.

Canonical transport: `astravector.embedding.v1.AstraVectorIngestionFacade` over gRPC.

## States

Current server-side state strings observed in implementation:

```text
ACTIVE
FINALIZING
COMPLETED
FAILED
ABORTED
EXPIRED
```

The wire contract currently exposes session status as a string. External clients must tolerate unknown future states until AstraVector publishes a typed enum.

## State machine

```text
             Start
               |
               v
            ACTIVE
          /    |    \
     Append   Abort  TTL expiry
       |       |       |
       |       v       v
       |    ABORTED  EXPIRED
       |
       v
    Finalize
       |
       v
   FINALIZING
      /   \
 success failure
    |       |
    v       v
COMPLETED  FAILED
```

## Start

`StartLogicalDocumentIngestion` creates an ingestion session scoped to one document version and one effective access zone.

Recommended client-provided idempotency key:

```text
astraindexator:{documentId}:{documentVersion}:{contentHash}
```

Replay rule:

- same idempotency key + same logical request => return/reuse existing session;
- same key + different request fingerprint => conflict/rejection.

AstraIndexator must not create a new key after a timeout for the same operation unless it has first reconciled state.

## Append

`AppendLogicalDocumentBlocks` stages logical blocks in batches.

Required client behavior:

- use monotonic/deterministic `batchIndex`;
- compute and send `batchContentHash` according to the canonical algorithm once formally published;
- same batch index + same hash may be replayed idempotently;
- same batch index + different hash is an integrity conflict;
- do not assume `isLastBatch=true` finalizes the document.

Current contract rule:

```text
FinalizeLogicalDocumentIngestion is always required.
```

## Finalize

`FinalizeLogicalDocumentIngestion` changes the lifecycle from `ACTIVE` to `FINALIZING`, validates the staged document, and executes the real AstraVector ingestion path.

Important consumer rule:

```text
Finalize accepted != automatically safe to assume searchable.
```

After finalize, AstraIndexator should query document vector status and rely on `searchable`/state information.

Current session-finalize implementation uses auto-oriented activation semantics internally. Therefore client documentation must not promise the same manual activation behavior as the standalone single-call smoke flow.

## Abort

Abort is intended for an active session that the client no longer wants to finish.

Recommended client behavior:

- always provide a useful reason;
- treat repeated abort of an already aborted session as idempotent if server accepts/returns that state;
- do not blindly abort sessions that are already finalizing/completed; reconcile status instead.

## Expiry

Session expiry and document TTL are separate concepts.

- session expiry limits how long a chunked upload session may remain open;
- document TTL controls document lifetime/searchability policy after ingestion.

Do not conflate `expiresAt` of the ingestion session with document expiry.

## Recovery after ambiguous failures

### Timeout during Start

```text
Start -> timeout
   |
   v
retry with SAME idempotency key
```

If server state can be queried by the returned/session identity, reconcile first when possible.

### Timeout during Append

```text
Append(batch N) -> timeout
   |
   v
re-send batch N with SAME batch hash
```

### Timeout during Finalize

```text
Finalize -> timeout
   |
   v
GetLogicalDocumentIngestionStatus
   |
   +--> FINALIZING -> poll
   +--> COMPLETED  -> continue to vector status
   +--> ACTIVE     -> finalize may be retried according to same hash contract
   +--> FAILED     -> inspect error and decide recovery
```

Never create a new document version merely because finalize timed out.

## Vector readiness after ingestion

After successful ingestion/finalization, use:

```text
GetDocumentVectorStatus
```

as the authoritative integration point for readiness/searchability.

Expected consumer-relevant fields include:

```text
state
progress_percent
searchable
ready_to_activate
```

AstraIndexator should report success upstream only according to the agreed business completion level, e.g.:

```text
INGESTED
VECTOR_READY
SEARCHABLE
```

rather than mapping every accepted RPC to "done".

## Retry matrix

| Condition | Recommended action |
|---|---|
| `UNAVAILABLE` | bounded exponential backoff |
| `DEADLINE_EXCEEDED` on mutation | reconcile state first, then replay idempotently |
| `ABORTED` while `FINALIZING` | poll status; do not create new session |
| `RESOURCE_EXHAUSTED` capacity | bounded backoff |
| `RESOURCE_EXHAUSTED` size/blocks | shrink request/batch; no blind retry |
| `INVALID_ARGUMENT` | fix client payload; permanent |
| `FAILED_PRECONDITION` hash mismatch | fix hash/payload |
| `FAILED_PRECONDITION` lifecycle state | reconcile status |
| `PERMISSION_DENIED` | security/configuration error |
| session `NOT_FOUND` | recovery decision; no blind replay |

## Contract gaps

Before multiple independent production clients are implemented, AstraVector should ideally publish:

1. typed session state enum;
2. structured error reason details;
3. byte-precise batch hash canonicalization;
4. byte-precise final content hash canonicalization;
5. explicit activation semantics for session ingestion.
