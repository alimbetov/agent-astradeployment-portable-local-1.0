# Observability Guide

## Purpose

This guide defines the minimum observability model for AstraDeployment Portable Local Deployment 1.0 and the information an operator should capture before escalating an incident.

## Observability layers

Observe the platform in layers:

```text
host
→ Docker/Compose
→ PostgreSQL
→ Qdrant
→ AstraVector process
→ AstraVector readiness
→ ingestion/retrieval business path
```

A green container state alone is not sufficient evidence that the platform is usable.

## Signals

Use the standard three signal families:

```text
logs
metrics
health/readiness/smoke
```

Tracing/correlation should connect application calls to AstraVector operations even before a full distributed tracing stack is introduced.

## Health and readiness

AstraVector exposes:

```text
GET /health
GET /ready
```

Interpretation:

- `/health`: service process is alive;
- `/ready`: service is ready to accept application traffic.

The deployment health gate also checks gRPC health for:

```text
astravector.embedding.v1.AstraVectorRuntime = SERVING
```

Operational rule: do not route customer traffic based on process liveness alone.

## Functional smoke as synthetic monitoring

`make smoke` is a synthetic transaction:

```text
ingestion
→ vector status
→ activation
→ retrieval
```

It proves the complete local path across AstraVector, PostgreSQL and Qdrant.

For a customer environment, run smoke:

- after initial installation;
- after upgrades;
- after restore/recovery;
- after major database/Qdrant maintenance.

Do not run destructive/high-volume smoke continuously in production unless a dedicated test tenant/access zone exists.

## Logs

Basic commands:

```bash
docker compose logs --tail=200 postgres
docker compose logs --tail=200 qdrant
docker compose logs --tail=500 astravector
```

Follow AstraVector:

```bash
docker compose logs -f astravector
```

Useful log dimensions:

```text
timestamp
service
correlation_id
document_id/document_version where permitted
access_zone_id where permitted
operation/state
error code
duration
```

Never log credentials or full confidential document content by default.

## Correlation IDs

Every external service should propagate a correlation identifier into AstraVector requests where the contract provides one.

Recommended flow:

```text
HTTP request to Spring Boot
→ correlation ID
→ AstraVector retrieval request
→ AstraVector logs
```

For future AstraIndexator:

```text
upload request
→ correlation ID
→ parse/OCR
→ ingestion session
→ AstraVector
```

A correlation ID is for observability, not uniqueness/idempotency. Do not reuse it as an idempotency key unless the contract explicitly says so.

## Metrics endpoint

The local bundle exposes AstraVector metrics on loopback:

```text
127.0.0.1:9090
```

Inspect manually during diagnostics:

```bash
curl -fsS http://127.0.0.1:9090/metrics | head
```

Do not expose metrics publicly. Future production deployment should have Prometheus or an equivalent collector scrape it over the private service network.

## Metric categories to monitor

Exact metric names may evolve upstream; operators should monitor these semantic categories:

- request throughput;
- request latency;
- errors by operation/code;
- retrieval degraded/insufficient outcomes;
- admission/backpressure rejection;
- ingestion failures;
- outbox/publisher lag or failures;
- Qdrant dependency failures;
- PostgreSQL dependency failures/timeouts;
- model/bootstrap failures;
- process memory/CPU;
- container restarts.

Where upstream exposes exact metric names, dashboards should pin them to the validated AstraVector release.

## PostgreSQL observability

At minimum observe:

- `pg_isready`;
- disk usage;
- active connections;
- connection saturation;
- query latency/slow queries when tooling exists;
- backup success;
- database size growth.

PostgreSQL is canonical state. Alerting on disk pressure and backup failure has high priority.

## Qdrant observability

At minimum observe:

- HTTP/API reachability;
- collection availability;
- disk usage;
- memory usage;
- restart count;
- projection/reconciliation errors from AstraVector.

Qdrant being rebuildable does not mean outages are harmless; retrieval depends on it.

## Host and Docker observability

Useful commands:

```bash
docker stats --no-stream
docker system df
df -h
docker compose ps
```

Alerting priorities for a single server:

1. disk nearly full;
2. PostgreSQL unavailable;
3. AstraVector not ready;
4. Qdrant unavailable;
5. repeated container restarts;
6. backup failures;
7. high memory pressure.

## Retrieval semantic monitoring

A successful HTTP 200 does not always mean useful evidence exists. External applications must distinguish semantic result from transport result.

Monitor at least:

```text
evidenceStatus = FOUND
INSUFFICIENT
DEGRADED
summary.degraded
degradationCodes
```

This distinction is important for customer-facing search quality and for diagnosing partial infrastructure failures.

## Ingestion monitoring

For ingestion, separate:

```text
request accepted
≠ vectors ready
≠ document activated
≠ searchable
```

Monitor/document status through the AstraVector status contract. Future AstraIndexator must not report success at the first accepted RPC if vector publication/activation is still incomplete.

## Suggested customer dashboard

Initial dashboard panels:

```text
AstraVector readiness
AstraVector request rate/error rate
retrieval latency
retrieval evidence status distribution
retrieval degradation count
PostgreSQL availability/connections/disk
Qdrant availability/disk
container CPU/memory/restarts
host disk free
last successful backup timestamp
```

## Alert severity proposal

### Critical

- PostgreSQL unavailable;
- AstraVector not ready for sustained interval;
- filesystem nearly full with risk of database failure;
- restore/backup failure when RPO is at risk.

### High

- Qdrant unavailable;
- repeated AstraVector restarts;
- persistent retrieval degradation due to infrastructure;
- outbox/projection processing stalled.

### Warning

- model cold bootstrap retrying;
- disk growth trend;
- elevated latency;
- increased `INSUFFICIENT` rate requiring product/search-quality review.

## Incident evidence package

Before escalation capture:

```text
deployment Git SHA/version
AstraVector image tag + digest
incident time range UTC
correlation IDs
compose ps
health output
relevant logs
metrics snapshots
host disk/memory
docker stats
last known successful smoke
last known successful backup
```

Remove secrets before sharing.

## Future Kubernetes mapping

The same model maps naturally to Kubernetes:

```text
Compose health       → readiness/liveness/startup probes
Docker logs          → centralized pod logs
9090 metrics         → ServiceMonitor/Prometheus scrape
container stats      → kubelet/cAdvisor metrics
host disk            → node/PVC alerts
smoke                → post-deploy Job / controlled synthetic test
correlation IDs      → distributed tracing/log correlation
```

Do not wait for Kubernetes to establish these observability semantics; use the same concepts in the current single-node bundle.
