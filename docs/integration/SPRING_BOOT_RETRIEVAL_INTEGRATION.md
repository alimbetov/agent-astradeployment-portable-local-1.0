# Spring Boot Retrieval Integration Contract

## Purpose

This document defines how a Spring Boot application integrates with AstraVector for retrieval. It is an integration contract, not an AstraVector implementation guide.

AstraVector currently exposes both gRPC services and an internal HTTP retrieval boundary. For Spring Boot, the recommended first integration path is HTTP `POST /api/v1/retrieve` because it minimizes client coupling while preserving the retrieval contract.

## Runtime endpoint

Local AstraDeployment default:

```text
http://127.0.0.1:8080/api/v1/retrieve
```

Inside Docker Compose/Kubernetes service networking, use the AstraVector service DNS name instead of localhost, for example:

```text
http://astravector:8080/api/v1/retrieve
```

## Request contract

Example request:

```json
{
  "question": "Где AstraVector хранит каноническое состояние документов?",
  "accessZoneId": "b4ec78f9-70c3-5264-8b75-1b85f1905e44",
  "callerAccessLevel": "PUBLIC",
  "profile": "SEMANTIC",
  "maxContexts": 3,
  "enableGraphExpansion": false,
  "correlationId": "spring-demo-001"
}
```

Relevant fields:

- `question` — user/search question.
- `accessZoneId` / `accessZoneIds` — retrieval scope.
- `accessZoneCode` / `accessZoneCodes` — optional code-based scope.
- `callerAccessLevel` — visibility boundary such as `PUBLIC`, `INTERNAL`, `CONFIDENTIAL`, `RESTRICTED`.
- `profile` — retrieval profile. For the currently validated dense-only smoke path use `SEMANTIC`.
- `maxContexts` — maximum returned contexts.
- `filters` — optional metadata filters.
- `enableGraphExpansion` — optional graph expansion.
- `correlationId` — tracing/correlation value from the calling application.

## Response contract

A successful response contains retrieved contexts and a summary. The integration should depend on the semantic contract, not on log output.

Important response fields:

```text
contexts[].matchedText
contexts[].parentText
contexts[].citation.documentId
contexts[].citation.documentVersion
contexts[].citation.sourceUri
contexts[].scores.finalScore
summary.returnedContexts
summary.evidenceStatus
summary.degraded
summary.degradationCodes
```

AstraVector is retrieval-only in this boundary. A Spring Boot service may pass the returned context to an LLM, but that is outside AstraVector.

## Recommended Spring Boot adapter

Use a dedicated client boundary:

```text
Controller/Application Service
        |
        v
AstraVectorRetrievalClient
        |
        v
HTTP /api/v1/retrieve
```

Do not spread AstraVector JSON DTOs throughout business code. Map them into application-owned DTOs.

Suggested package layout:

```text
com.example.search
├── application
│   └── RetrievalService.java
├── infrastructure
│   └── astravector
│       ├── AstraVectorClient.java
│       ├── AstraVectorProperties.java
│       ├── AstraVectorRetrieveRequest.java
│       ├── AstraVectorRetrieveResponse.java
│       └── AstraVectorClientException.java
└── web
    └── SearchController.java
```

## Configuration

Example `application.yml`:

```yaml
astravector:
  base-url: ${ASTRAVECTOR_BASE_URL:http://localhost:8080}
  connect-timeout: 2s
  read-timeout: 10s
```

In Docker Compose:

```text
ASTRAVECTOR_BASE_URL=http://astravector:8080
```

In Kubernetes:

```text
ASTRAVECTOR_BASE_URL=http://astravector.<namespace>.svc.cluster.local:8080
```

## Client behavior

The Spring client should:

1. create a correlation ID if one is not already present;
2. set a bounded connect/read timeout;
3. distinguish 4xx contract errors from 5xx/dependency errors;
4. never retry validation/authorization failures;
5. use limited retry only for safe transient connection/5xx failures;
6. propagate `evidenceStatus`, `degraded` and `degradationCodes` to the application layer;
7. not treat an empty context list as a transport failure;
8. log correlation IDs but not sensitive document content by default.

## WebClient skeleton

```java
@ConfigurationProperties(prefix = "astravector")
public record AstraVectorProperties(
        URI baseUrl,
        Duration connectTimeout,
        Duration readTimeout
) {}
```

```java
@Component
@RequiredArgsConstructor
public class AstraVectorClient {

    private final WebClient webClient;

    public Mono<AstraVectorRetrieveResponse> retrieve(AstraVectorRetrieveRequest request) {
        return webClient.post()
                .uri("/api/v1/retrieve")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(request)
                .retrieve()
                .bodyToMono(AstraVectorRetrieveResponse.class);
    }
}
```

For a synchronous Spring MVC application, the adapter may use `RestClient` instead. The important point is preserving the same DTO and failure contract.

## Health integration

AstraVector exposes:

```text
GET /health
GET /ready
```

Spring Boot should use `/ready` for dependency-readiness diagnostics. Do not make every business request perform a readiness call first.

## Security

The current AstraDeployment local profile is internal/local and authentication may be disabled. Customer environments should place AstraVector on an internal network and define gateway/API-key/mTLS policy separately.

Do not infer authorization from `callerAccessLevel`; it is a retrieval visibility input, not a substitute for transport authentication.

## Acceptance test

A Spring Boot integration is accepted when:

1. AstraDeployment is healthy;
2. a known document has been indexed and activated;
3. Spring Boot sends a real retrieval request;
4. `summary.evidenceStatus` is `FOUND` for the known test question;
5. at least one returned context contains the expected evidence;
6. correlation ID is visible end-to-end;
7. timeout/error handling is demonstrated for unavailable AstraVector.
