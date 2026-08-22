# Spring Boot Reference Integration

## Scope

This is a reference adapter design for a Spring Boot service calling AstraVector retrieval over HTTP/JSON.

Canonical endpoint:

```text
POST /api/v1/retrieve
```

The goal is to keep AstraVector transport DTOs inside an infrastructure adapter and expose application-owned DTOs to business code.

## Package layout

```text
com.example.astra
├── application
│   ├── SearchService.java
│   └── SearchResult.java
├── infrastructure
│   └── astravector
│       ├── AstraVectorClient.java
│       ├── AstraVectorClientConfiguration.java
│       ├── AstraVectorClientException.java
│       ├── AstraVectorProperties.java
│       └── dto/
│           ├── AstraVectorRetrieveRequest.java
│           ├── AstraVectorRetrieveResponse.java
│           └── AstraVectorErrorResponse.java
└── web
    └── SearchController.java
```

## Configuration

```yaml
astravector:
  base-url: ${ASTRAVECTOR_BASE_URL:http://localhost:8080}
  connect-timeout: 2s
  read-timeout: 10s
```

```java
@ConfigurationProperties(prefix = "astravector")
public record AstraVectorProperties(
        URI baseUrl,
        Duration connectTimeout,
        Duration readTimeout
) {}
```

For Docker Compose:

```text
ASTRAVECTOR_BASE_URL=http://astravector:8080
```

For Kubernetes:

```text
ASTRAVECTOR_BASE_URL=http://astravector.<namespace>.svc.cluster.local:8080
```

## HTTP client

```java
@Configuration
@EnableConfigurationProperties(AstraVectorProperties.class)
public class AstraVectorClientConfiguration {

    @Bean
    WebClient astraVectorWebClient(
            WebClient.Builder builder,
            AstraVectorProperties properties
    ) {
        HttpClient httpClient = HttpClient.create()
                .option(
                        ChannelOption.CONNECT_TIMEOUT_MILLIS,
                        Math.toIntExact(properties.connectTimeout().toMillis())
                )
                .responseTimeout(properties.readTimeout());

        return builder
                .baseUrl(properties.baseUrl().toString())
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .build();
    }
}
```

## Request construction

Recommended business input:

```java
public record SearchQuery(
        String question,
        List<String> accessZoneCodes,
        AccessLevel effectiveAccessLevel,
        int maxContexts
) {}
```

Do not expose both IDs and codes to every controller unless the application genuinely needs both representations.

Adapter mapping:

```java
AstraVectorRetrieveRequest request = new AstraVectorRetrieveRequest(
        query.question(),
        null,
        List.of(),
        null,
        query.accessZoneCodes(),
        query.effectiveAccessLevel(),
        RetrievalProfile.BALANCED,
        query.maxContexts(),
        List.of(),
        false,
        null,
        null,
        correlationId
);
```

## Correlation ID

Recommended rule:

```text
incoming request correlation ID
        ↓
reuse if valid
        ↓
or generate UUID once
        ↓
X-Correlation-Id header + request.correlationId
```

This makes traces and errors easier to correlate across services.

## Client implementation

```java
@Component
public final class AstraVectorClient {

    private final WebClient client;

    public AstraVectorClient(WebClient astraVectorWebClient) {
        this.client = astraVectorWebClient;
    }

    public Mono<AstraVectorRetrieveResponse> retrieve(
            AstraVectorRetrieveRequest request,
            String correlationId
    ) {
        return client.post()
                .uri("/api/v1/retrieve")
                .header("X-Correlation-Id", correlationId)
                .bodyValue(request)
                .exchangeToMono(response -> {
                    if (response.statusCode().is2xxSuccessful()) {
                        return response.bodyToMono(AstraVectorRetrieveResponse.class);
                    }

                    return response.bodyToMono(AstraVectorErrorResponse.class)
                            .defaultIfEmpty(new AstraVectorErrorResponse(
                                    "UNKNOWN",
                                    "Empty AstraVector error response",
                                    correlationId
                            ))
                            .flatMap(error -> Mono.error(
                                    AstraVectorClientException.from(
                                            response.statusCode(),
                                            error
                                    )
                            ));
                });
    }
}
```

## Retry policy

Retrieval is read-only and can use bounded retry, but retries must stay inside the overall latency budget.

Recommended adapter policy:

```text
retryable:
- network/connect failure
- 429 when interpreted as transient capacity pressure
- 503
- 504

not retryable:
- 400
- 401
- 403
- malformed access zone
- invalid caller access level
```

Example:

```java
.retryWhen(
    Retry.backoff(2, Duration.ofMillis(200))
        .maxBackoff(Duration.ofSeconds(2))
        .jitter(0.20)
        .filter(this::isRetryable)
)
```

Do not automatically retry `DEGRADED` application results as if they were transport failures. The application may still have usable evidence.

## Semantic result handling

```java
return switch (response.summary().evidenceStatus()) {
    case FOUND -> useEvidence(response);
    case INSUFFICIENT -> noEvidence(response);
    case DEGRADED -> useOrEscalateDegradedEvidence(response);
};
```

Key rule:

```text
INSUFFICIENT != HTTP failure
DEGRADED     != necessarily HTTP failure
```

## Access zones

Preferred external business representation:

```json
{
  "accessZoneCodes": ["1500", "1501"]
}
```

Do not simultaneously send IDs and codes unless both are known to resolve to the same set. AstraVector can reject mismatched selectors.

## callerAccessLevel

Never accept a browser-supplied access level as trusted authorization.

Recommended flow:

```text
authenticated principal
        ↓
Spring Security / gateway policy
        ↓
effective AccessLevel
        ↓
AstraVector request
```

`callerAccessLevel` is a retrieval visibility input, not authentication.

## Example controller

```java
@RestController
@RequestMapping("/api/search")
@RequiredArgsConstructor
public class SearchController {

    private final SearchService searchService;

    @PostMapping
    public Mono<SearchResult> search(
            @RequestBody SearchRequest request,
            Authentication authentication,
            @RequestHeader(value = "X-Correlation-Id", required = false)
            String correlationId
    ) {
        return searchService.search(request, authentication, correlationId);
    }
}
```

The service should derive both allowed access zones and effective access level from trusted application/security state.

## Integration test cases

Minimum contract test suite:

1. one access-zone code -> FOUND;
2. plural access-zone codes -> FOUND;
3. no access zone -> 400;
4. malformed code -> 400;
5. mismatched code + ID -> 400/conflict according to server mapping;
6. `INSUFFICIENT` -> application success without evidence;
7. `DEGRADED` -> application receives degradation metadata;
8. unavailable AstraVector -> bounded retry then dependency failure;
9. correlation ID propagated;
10. unknown response fields ignored.

## Health

AstraVector provides:

```text
GET /health
GET /ready
```

Use `/ready` for operational diagnostics/readiness checks. Do not call readiness before every business request.
