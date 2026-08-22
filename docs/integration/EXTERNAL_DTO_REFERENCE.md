# AstraVector External DTO Reference

## Purpose

This document is a consumer-oriented DTO reference for future external services. It is derived from the current AstraVector contract and is intentionally split into:

- Spring Boot HTTP retrieval DTOs;
- AstraIndexator application DTOs;
- generated protobuf wire DTOs for ingestion;
- shared semantics such as access zones, visibility and TTL.

The canonical gRPC wire source remains `llm2/proto/astravector_embedding.proto`. This document must not be used to replace generated protobuf classes.

---

# Retrieval DTOs for Spring Boot

## Request

Recommended Java 17 adapter DTO:

```java
public record AstraVectorRetrieveRequest(
        String question,
        String accessZoneId,
        List<String> accessZoneIds,
        String accessZoneCode,
        List<String> accessZoneCodes,
        AccessLevel callerAccessLevel,
        RetrievalProfile profile,
        Integer maxContexts,
        List<Filter> filters,
        Boolean enableGraphExpansion,
        Integer graphMaxHops,
        Integer graphMaxRelatedContexts,
        String correlationId
) {}
```

Enums:

```java
public enum AccessLevel {
    PUBLIC,
    INTERNAL,
    CONFIDENTIAL,
    RESTRICTED
}

public enum RetrievalProfile {
    BALANCED,
    LEGAL,
    TECHNICAL,
    SEMANTIC,
    LEXICAL_STRICT
}
```

Field reference:

| JSON field | Java type | Required | Current semantics |
|---|---|---:|---|
| `question` | `String` | yes | non-blank query text |
| `accessZoneId` | `String` | conditional | singular UUID selector |
| `accessZoneIds` | `List<String>` | conditional | plural UUID selectors |
| `accessZoneCode` | `String` | conditional | singular 4-digit zone code |
| `accessZoneCodes` | `List<String>` | conditional | plural 4-digit zone codes |
| `callerAccessLevel` | `AccessLevel` | no | visibility input; REST default currently `INTERNAL` |
| `profile` | `RetrievalProfile` | no | current default `BALANCED` |
| `maxContexts` | `Integer` | no | `0`/absent falls back to server default; positive value is capped by server limit |
| `filters` | `List<Filter>` | no | metadata filter list |
| `enableGraphExpansion` | `Boolean` | no | default false |
| `graphMaxHops` | `Integer` | no | current implementation effectively supports up to one hop |
| `graphMaxRelatedContexts` | `Integer` | no | bounded by server configuration |
| `correlationId` | `String` | no | request tracing identifier |

At least one access-zone selector must be present.

Recommended client policy:

```text
normal application traffic -> prefer accessZoneCodes
system/internal integration -> accessZoneIds allowed
avoid sending code(s) and ID(s) simultaneously unless verifying consistency
```

### Filter DTO

```java
public record Filter(
        String key,
        String value
) {}
```

Do not assume arbitrary filter operators unless they are explicitly present in the current HTTP contract.

---

## Response

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record AstraVectorRetrieveResponse(
        List<RetrievedContext> contexts,
        RetrievalSummary summary,
        List<Warning> warnings,
        Degradation degradation,
        Diagnostics diagnostics
) {}
```

### Retrieved context

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record RetrievedContext(
        String matchedText,
        String parentText,
        String documentId,
        long documentVersion,
        String sourceBlockId,
        String matchedChunkId,
        String parentChunkId,
        String accessZoneId,
        List<SourceLink> sourceLinks,
        Citation citation,
        Scores scores,
        Map<String, String> metadata
) {}
```

### Citation

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record Citation(
        String documentId,
        long documentVersion,
        String sourceUri,
        String title,
        int pageStart,
        int pageEnd,
        String sectionPath,
        String heading,
        String matchedChunkId,
        String parentChunkId,
        String sourceBlockId
) {}
```

### Scores

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record Scores(
        float denseScore,
        float sparseScore,
        float fusionScore,
        float finalScore
) {}
```

### Retrieval summary

```java
public enum EvidenceStatus {
    FOUND,
    INSUFFICIENT,
    DEGRADED
}

@JsonIgnoreProperties(ignoreUnknown = true)
public record RetrievalSummary(
        int totalCandidates,
        int returnedContexts,
        RetrievalProfile profile,
        EvidenceStatus evidenceStatus,
        boolean degraded,
        List<String> degradationCodes,
        boolean denseBranchExecuted,
        boolean sparseBranchExecuted,
        boolean fusionExecuted,
        int denseBranchCandidateCount,
        int sparseBranchCandidateCount,
        int fusionCandidateCount
) {}
```

Consumer semantics:

```text
FOUND        = evidence was returned
INSUFFICIENT = valid successful search but insufficient/no evidence; not transport failure
DEGRADED     = result exists but retrieval ran in degraded mode
```

Do not convert `INSUFFICIENT` into HTTP 500 in a Spring service.

### Warning/degradation DTOs

```java
public record Warning(String code, String message) {}
```

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record Degradation(
        boolean degraded,
        String degradationClass,
        boolean retryable,
        Integer coverageClass,
        boolean infrastructureFailure,
        boolean fullHydrationFailure,
        List<DroppedParent> droppedParents
) {}
```

```java
public record DroppedParent(
        String parentId,
        String reason,
        String rejectionStage,
        boolean retryable,
        int inputOrdinal
) {}
```

Do not model `degradationCodes` as a closed enum unless there is an UNKNOWN fallback. The server can add new codes.

### Diagnostics

Diagnostics are an observability surface and should be forward-compatible:

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record Diagnostics(
        Long queryEmbeddingMs,
        Long qdrantSearchMs,
        Long parentFetchMs,
        Long totalMs,
        Integer candidateCount,
        Integer finalCandidateCount,
        Long denseSearchMs,
        Long sparseSearchMs,
        Long lexicalSearchMs,
        Long fusionMs,
        Long graphExpansionDurationMs,
        Long graphMergeDurationMs,
        Boolean mmrEnabled,
        Long mmrDurationMs,
        Boolean tokenBudgetEnabled,
        Integer estimatedContextTokensAfter,
        String queryProcessingMode,
        Integer queryOriginalTokenCount,
        Integer querySegmentCount,
        Float queryCoverageRatio,
        Long effectiveQueryTimeoutMs
) {}
```

Client code must not fail when new diagnostics fields appear.

---

# Error DTO for Spring Boot

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record AstraVectorErrorResponse(
        String code,
        String message,
        String correlationId
) {}
```

Current HTTP error mapping should be treated as follows:

| HTTP | Typical gRPC source | Client action |
|---:|---|---|
| 400 | `INVALID_ARGUMENT`, `OUT_OF_RANGE` | permanent request error; no retry |
| 401 | `UNAUTHENTICATED` | auth/config error |
| 403 | `PERMISSION_DENIED` | security/policy error |
| 404 | `NOT_FOUND` | resource/scope problem |
| 409 | `ALREADY_EXISTS`, `FAILED_PRECONDITION`, `ABORTED` | reconcile state; usually no blind retry |
| 429 | `RESOURCE_EXHAUSTED` | bounded retry only if reason is transient/capacity |
| 503 | `UNAVAILABLE` | bounded retry |
| 504 | `DEADLINE_EXCEEDED` | bounded retry within request budget |
| 500 | other | treat as server failure |

---

# AstraIndexator application DTOs

These are **application DTOs**, not wire DTOs. The wire layer must use generated protobuf classes.

## Start ingestion

```java
public record StartIngestion(
        String accessZoneId,
        String accessZoneCode,
        UUID documentId,
        long documentVersion,
        String sourceUri,
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

Recommended invariants:

- `documentId` stable for one logical document across versions;
- `documentVersion > 0`;
- exactly one effective access zone after resolution;
- same operation retry uses the same `idempotencyKey`;
- `ttlDays=0` means inherit effective zone/platform TTL policy, not "forever".

## Start result

```java
public record StartResult(
        UUID ingestionSessionId,
        String status,
        Instant expiresAt,
        List<Warning> warnings
) {}
```

Status is currently a string on the wire; client code should tolerate unknown future states.

## Append batch

```java
public record AppendBlocks(
        UUID ingestionSessionId,
        List<LogicalBlock> blocks,
        long batchIndex,
        boolean lastBatch,
        String batchContentHash
) {}
```

Important current rule:

```text
isLastBatch is informational in the current implementation.
FinalizeLogicalDocumentIngestion is still required.
```

Same `batchIndex` + same hash is the safe replay shape. Same index + different hash is a conflict.

## Finalize

```java
public record FinalizeIngestion(
        UUID ingestionSessionId,
        String finalContentHash
) {}
```

`finalContentHash` must match AstraVector canonicalization. Until byte-precise canonical hashing is formally published with golden vectors, this remains a contract gap for cross-language clients.

## Abort

```java
public record AbortIngestion(
        UUID ingestionSessionId,
        String reason
) {}
```

Recommended client policy: always provide a reason even if the server does not currently require non-blank text.

## Status

```java
public record IngestionStatus(
        UUID ingestionSessionId,
        String status,
        long receivedBatches,
        long receivedBlocks,
        long receivedBytes,
        Instant expiresAt,
        String errorCode,
        String errorMessage
) {}
```

Known server state values currently include:

```text
ACTIVE
FINALIZING
COMPLETED
FAILED
ABORTED
EXPIRED
```

Do not close the Java model around only these strings without an UNKNOWN fallback.

---

# Logical document DTOs

## LogicalBlock

```java
public record LogicalBlock(
        String blockId,
        String parentBlockId,
        BlockType blockType,
        String text,
        long orderIndex,
        SourceLocation sourceLocation,
        List<SourceLink> sourceLinks,
        Map<String, String> metadata
) {}
```

```java
public enum BlockType {
    DOCUMENT,
    SECTION,
    SUBSECTION,
    PARAGRAPH,
    TABLE,
    TABLE_ROW,
    LIST,
    LIST_ITEM,
    FAQ_ITEM,
    CODE_BLOCK,
    CAPTION
}
```

Structural rules expected by AstraVector:

- blocks collection is non-empty;
- `blockId` is non-blank and unique within the document version;
- `blockType` must not be UNSPECIFIED;
- `text` must be non-blank;
- exactly one root `DOCUMENT` block exists;
- non-root blocks reference existing parents;
- block graph must be acyclic and structurally valid.

AstraIndexator should validate these rules locally before the gRPC call.

## SourceLocation

```java
public record SourceLocation(
        long pageStart,
        long pageEnd,
        long charStart,
        long charEnd,
        String sectionPath,
        String heading,
        String tableId,
        long rowIndex,
        long columnIndex
) {}
```

This data should be preserved whenever parser/OCR can provide it because retrieval citations depend on provenance.

## SourceLink

```java
public record SourceLink(
        String type,
        String url,
        String label,
        String mimeType,
        boolean requiresAuth,
        String expiresAt,
        Map<String, String> attributes
) {}
```

Do not place credentials/secrets in URLs or metadata.

---

# Generated protobuf type mapping

| Proto | Generated Java | Application recommendation |
|---|---|---|
| `string` | `String` | `String`, or `UUID`/`Instant` in domain layer after validation |
| `uint32` | Java `int` semantics | use positive `long` in domain DTO if avoiding unsigned confusion |
| `uint64` | `long` | `long` |
| `repeated T` | `List<T>` | `List<T>` |
| `map<string,string>` | `Map<String,String>` | same |
| proto enum | generated enum | map to application enum with explicit UNKNOWN handling |
| gRPC status | `StatusRuntimeException` | map to typed adapter exceptions/retry policy |

---

# DTO boundary rule

Keep three layers distinct:

```text
Business/domain DTO
        ↓ mapper
Adapter DTO / generated proto DTO
        ↓ transport
AstraVector
```

Do not leak generated protobuf classes through the whole Spring/AstraIndexator business model, and do not manually duplicate protobuf wire classes.
