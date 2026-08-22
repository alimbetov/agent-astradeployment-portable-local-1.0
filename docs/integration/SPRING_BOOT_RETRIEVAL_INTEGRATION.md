# Spring Boot Retrieval Integration Contract

## Purpose

This document defines how a Spring Boot application integrates with AstraVector retrieval. It is a consumer contract and onboarding guide, not an AstraVector implementation guide.

The canonical endpoint for Spring Boot integration is:

```text
POST /api/v1/retrieve
```

Use HTTP/JSON for Spring retrieval clients. Do not depend on internal Rust structs or AstraVector PostgreSQL/Qdrant schemas.

For the full DTO field reference see:

- `EXTERNAL_DTO_REFERENCE.md`
- `ACCESS_ZONE_AND_TTL_SEMANTICS.md`
- `SPRING_BOOT_EXAMPLE_PROJECT.md`
- `CONTRACT_GOVERNANCE.md`

## Runtime endpoint

Local AstraDeployment default:

```text
http://127.0.0.1:8080/api/v1/retrieve
```

Inside Docker Compose/Kubernetes service networking, use service DNS:

```text
http://astravector:8080/api/v1/retrieve
```

or:

```text
http://astravector.<namespace>.svc.cluster.local:8080/api/v1/retrieve
```

## Request contract

Example:

```json
{
  "question": "Где AstraVector хранит каноническое состояние документов?",
  "accessZoneCodes": ["1500"],
  "callerAccessLevel": "INTERNAL",
  "profile": "SEMANTIC",
  "maxContexts": 3,
  "enableGraphExpansion": false,
  "correlationId": "spring-demo-001"
}
```

Current request surface includes:

```text
question
accessZoneId
accessZoneIds
accessZoneCode
accessZoneCodes
callerAccessLevel
profile
maxContexts
filters
enableGraphExpansion
graphMaxHops
graphMaxRelatedContexts
correlationId
```

### Access-zone rules

A request must contain at least one access-zone selector.

AstraVector supports both UUID selectors and four-digit codes. Singular and plural forms are convenience representations of one/effective multiple zones.

Recommended external policy:

```text
business-facing Spring API -> prefer accessZoneCodes
internal/system integration -> UUIDs allowed
```

If ID-based and code-based selectors are sent together, AstraVector resolves both and expects them to describe the same effective zone set. A mismatch is rejected. Therefore do not routinely send both representations.

See `ACCESS_ZONE_AND_TTL_SEMANTICS.md` for detailed rules.

### callerAccessLevel

Current values:

```text
PUBLIC
INTERNAL
CONFIDENTIAL
RESTRICTED
```

This value is a retrieval visibility input. It is not authentication and must not be trusted directly from a browser/user request in production.

Recommended flow:

```text
authenticated principal
 -> Spring Security/gateway policy
 -> effective callerAccessLevel
 -> AstraVector
```

### Retrieval profiles

Current public profiles include:

```text
BALANCED
LEGAL
TECHNICAL
SEMANTIC
LEXICAL_STRICT
```

For the validated dense-only path use `SEMANTIC`. Applications should not infer internal candidate counts/search branches from the profile name as a permanent business contract; server implementation can evolve while preserving profile semantics.

### maxContexts

`maxContexts=0`/absent uses server default behavior. Positive values are bounded by server configuration. The current deployment default maximum is not a permanent protocol invariant.

### correlationId

Recommended behavior:

1. reuse incoming trusted correlation ID if present;
2. otherwise generate a UUID;
3. send the same value in `X-Correlation-Id` and body `correlationId`;
4. log it on client failures.

## Response contract

Successful retrieval returns:

```text
summary
contexts[]
warnings[]
degradation
diagnostics
```

Important context fields include:

```text
matchedText
parentText
documentId
documentVersion
sourceBlockId
matchedChunkId
parentChunkId
accessZoneId
citation
scores
metadata
```

Important summary fields include:

```text
totalCandidates
returnedContexts
profile
evidenceStatus
degraded
degradationCodes
denseBranchExecuted
sparseBranchExecuted
fusionExecuted
```

### evidenceStatus

```text
FOUND        = evidence returned
INSUFFICIENT = valid successful retrieval but evidence is insufficient/empty
DEGRADED     = result produced under degraded retrieval conditions
```

`INSUFFICIENT` is not a transport/server failure. Do not map it to HTTP 500 in a calling Spring service.

`DEGRADED` is also not automatically a transport failure. The caller may still use returned evidence with warnings according to business policy.

### Forward compatibility

Use Jackson models with unknown-field tolerance, for example:

```java
@JsonIgnoreProperties(ignoreUnknown = true)
```

Do not model `degradationCodes` as a closed enum without `UNKNOWN`, because the server may add new diagnostic codes.

## Recommended Spring adapter boundary

```text
Controller/Application Service
        |
        v
AstraVectorRetrievalClient
        |
        v
HTTP /api/v1/retrieve
```

Keep transport DTOs inside `infrastructure/astravector`. Map them into application-owned DTOs.

Suggested package layout:

```text
com.example.search
├── application
│   ├── RetrievalService.java
│   └── SearchResult.java
├── infrastructure
│   └── astravector
│       ├── AstraVectorClient.java
│       ├── AstraVectorProperties.java
│       ├── AstraVectorClientException.java
│       └── dto/...
└── web
    └── SearchController.java
```

See `SPRING_BOOT_EXAMPLE_PROJECT.md` for a concrete implementation skeleton.

## Configuration

```yaml
astravector:
  base-url: ${ASTRAVECTOR_BASE_URL:http://localhost:8080}
  connect-timeout: 2s
  read-timeout: 10s
```

## Error model

AstraVector HTTP errors use a stable consumer shape similar to:

```json
{
  "code": "INVALID_ARGUMENT",
  "message": "question is required",
  "correlationId": "..."
}
```

Typical handling:

```text
400 -> permanent request/contract error
401/403 -> security/configuration problem
404 -> missing resource/scope
409 -> state conflict/reconciliation
429 -> bounded retry only when transient capacity pressure
503 -> bounded retry
504 -> bounded retry inside latency budget
500 -> server failure
```

Never blindly retry validation/security errors.

## Retry policy

Retrieval is semantically read-only, so bounded retry is acceptable for transient failures.

Recommended policy:

- connect failure -> retry with backoff;
- 503/504 -> retry with backoff;
- 429 -> retry only with bounded policy;
- 400/401/403 -> no retry;
- `INSUFFICIENT` -> no transport retry;
- `DEGRADED` -> application decision, not automatic transport retry.

## Health integration

AstraVector exposes:

```text
GET /health
GET /ready
```

Use `/ready` for dependency diagnostics/readiness. Do not make every business request call readiness first.

## Security

The local profile is internal and may run without HTTP authentication. Customer production environments should provide transport security/authentication through gateway/mTLS/API policy as appropriate.

Never confuse:

```text
transport identity/authentication
```

with:

```text
callerAccessLevel + access zones
```

The latter define retrieval visibility/scope, not caller identity.

## Minimum acceptance tests

A Spring integration should prove:

1. known document retrieval returns `FOUND`;
2. one access-zone code works;
3. multiple access-zone codes work;
4. missing zone is rejected;
5. mismatched code+ID is rejected;
6. `INSUFFICIENT` is handled as semantic success;
7. `DEGRADED` metadata reaches application layer;
8. unavailable AstraVector triggers bounded dependency handling;
9. correlation ID is propagated;
10. unknown response fields do not break deserialization.
