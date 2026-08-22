# Spring Boot Contract Test Guide

## Purpose

This guide defines how a Spring Boot service should verify its integration with AstraVector without coupling tests to AstraVector's internal Rust implementation.

## Test boundary

Recommended Spring Boot integration boundary:

```text
Spring application service
→ AstraVectorRetrievalClient
→ HTTP POST /api/v1/retrieve
```

The Spring service owns adapter DTOs and application semantics. AstraVector owns retrieval semantics.

## Test levels

Use four levels.

### 1. DTO serialization tests

Verify exact JSON field names and enum/string values used on the wire.

Example request fixture:

```json
{
  "question": "Где AstraVector хранит каноническое состояние документов?",
  "accessZoneId": "b4ec78f9-70c3-5264-8b75-1b85f1905e44",
  "callerAccessLevel": "PUBLIC",
  "profile": "SEMANTIC",
  "maxContexts": 3,
  "enableGraphExpansion": false,
  "correlationId": "contract-test-001"
}
```

Tests should detect accidental Java renaming such as `access_zone_id` versus the HTTP JSON contract expected by the REST boundary.

### 2. Client HTTP behavior tests

Use WireMock/MockWebServer or equivalent to prove:

- POST path is `/api/v1/retrieve`;
- content type is JSON;
- timeout is bounded;
- 4xx validation errors are not retried;
- transient 503/504 may be retried according to policy;
- correlation ID is propagated;
- unknown response fields do not break deserialization.

### 3. Consumer contract fixture tests

Keep golden request/response fixtures under the Spring project, versioned with the AstraVector contract version the service supports.

Recommended fixture structure:

```text
src/test/resources/contracts/astravector/
├── retrieve-semantic-single-zone-request.json
├── retrieve-semantic-single-zone-response-found.json
├── retrieve-response-insufficient.json
├── retrieve-response-degraded.json
├── retrieve-multi-zone-request.json
└── error-invalid-access-zone.json
```

Fixtures should be validated against a real AstraVector release before promotion.

### 4. Real integration smoke

Run against AstraDeployment:

```text
AstraDeployment healthy
→ seed/index known document
→ Spring Boot invokes AstraVector
→ response evidenceStatus = FOUND
→ returned context contains expected evidence
```

This is the most important integration proof.

## DTO rules

Adapter DTOs should be tolerant to additive response fields:

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record AstraVectorRetrieveResponse(...) {}
```

Do not use AstraVector transport DTOs as domain objects throughout the Spring application.

Recommended layers:

```text
web DTO
→ application command/query
→ AstraVector adapter DTO
→ mapped application result
```

## Access-zone contract tests

Test selector families explicitly.

### Single ID

```json
{"accessZoneId":"<uuid>"}
```

### Multiple IDs

```json
{"accessZoneIds":["<uuid-1>","<uuid-2>"]}
```

### Single code

```json
{"accessZoneCode":"0488"}
```

### Multiple codes

```json
{"accessZoneCodes":["0488","1024"]}
```

### Mixed selectors

If ID and code selector families are provided simultaneously, tests must follow the AstraVector documented consistency rule. Do not assume the service computes an unrestricted union.

Spring application authorization should determine the allowed zones before calling AstraVector. Contract tests must include at least one case proving an unauthorized/user-supplied zone cannot simply be forwarded without application authorization.

## Access level tests

Test known values used by the client:

```text
PUBLIC
INTERNAL
CONFIDENTIAL
RESTRICTED
```

Do not equate `callerAccessLevel` with authentication.

## Retrieval semantic result tests

Transport success and retrieval evidence are separate.

### FOUND

Expected application behavior: process returned contexts.

### INSUFFICIENT

Expected application behavior: valid response with insufficient evidence. Do not convert to network/server exception.

### DEGRADED

Expected application behavior: process according to product policy while exposing degradation diagnostics when relevant.

At minimum test:

```text
summary.evidenceStatus
summary.degraded
summary.degradationCodes
contexts
```

## Error/retry matrix

Recommended client contract:

| Condition | Retry? | Meaning |
|---|---:|---|
| HTTP 400 | No | invalid request/contract |
| HTTP 401 | No automatic retry | authentication/config |
| HTTP 403 | No | authorization/visibility failure |
| HTTP 404 | Usually no | endpoint/resource contract issue |
| HTTP 429 | Bounded | backpressure/rate limit if policy permits |
| HTTP 500 | Limited | server failure |
| HTTP 503 | Yes, bounded | transient unavailable |
| HTTP 504 | Yes, bounded | timeout/dependency |
| connect timeout | Yes, bounded | transient transport |
| read timeout | bounded, case-specific | ambiguous outcome/read failure |

Never create an infinite retry loop.

## Correlation test

Generate or accept a correlation ID at the Spring boundary and assert it is sent to AstraVector.

Recommended pattern:

```text
incoming X-Correlation-ID
→ application context
→ AstraVector request correlationId
→ logs
```

If no incoming ID exists, generate one.

## Timeouts

Tests should prove timeouts are configuration-driven, not infinite defaults.

Example configuration:

```yaml
astravector:
  base-url: ${ASTRAVECTOR_BASE_URL:http://localhost:8080}
  connect-timeout: 2s
  read-timeout: 10s
```

Tune production values using measured retrieval latency and SLOs.

## Contract evolution tests

When AstraVector changes:

1. pull/update the consumer fixtures;
2. verify additive fields do not break the client;
3. review enum additions carefully;
4. run real integration smoke against the new immutable image;
5. only then update the supported AstraVector version in the Spring service.

Breaking examples:

- removing/renaming a field the client uses;
- changing field meaning;
- changing JSON type;
- reinterpreting access-zone semantics;
- removing an enum value.

Normally compatible examples:

- new optional response field;
- new diagnostics field ignored by older clients;
- new endpoint not used by existing clients.

## CI proposal

Spring service CI should have:

```text
unit tests
→ DTO serialization tests
→ mocked HTTP client tests
→ fixture contract tests
→ optional real AstraDeployment integration job
```

The real integration job should pin an immutable AstraVector image/digest rather than `latest`.

## Acceptance criteria

Spring Boot integration contract is considered proven when:

- request serialization matches the AstraVector HTTP boundary;
- response decoding tolerates additive fields;
- access-zone variants are covered;
- semantic evidence states are covered;
- timeout/retry behavior is covered;
- authentication/authorization errors are not blindly retried;
- correlation is propagated;
- a real AstraDeployment smoke through the Spring adapter returns expected evidence.
