# Troubleshooting Guide

## Purpose

This guide provides a deterministic troubleshooting order for AstraDeployment Portable Local Deployment 1.0. Diagnose from infrastructure upward; do not start by changing application code.

## Golden troubleshooting order

```text
Host resources
→ Docker daemon
→ image identity
→ Compose render
→ volumes/permissions
→ PostgreSQL
→ Qdrant
→ model cache/bootstrap
→ AstraVector readiness
→ functional smoke
```

## 1. Host resource checks

```bash
df -h
docker system df
free -h 2>/dev/null || true
uname -m
```

Typical failures:

- disk full during image pull/model download;
- insufficient memory during ONNX model initialization;
- host architecture incompatible with published image.

Do not delete Docker volumes during emergency cleanup unless recovery requirements are understood.

## 2. Docker daemon

```bash
docker info
docker version
docker compose version
```

If Docker is unavailable, AstraDeployment cannot start. Fix Docker before investigating PostgreSQL/Qdrant/AstraVector.

## 3. Compose configuration

From `deploy/local`:

```bash
docker compose --env-file .env -f docker-compose.astravector.yml config
```

Check for:

- missing environment values;
- malformed `ASTRAVECTOR_DB_URL`;
- accidental public port bindings;
- wrong image tags.

## 4. Image pull/authentication

```bash
docker login registry.astrabase.asia -u <reader-user>
docker pull <ASTRAVECTOR_IMAGE>
docker image inspect <ASTRAVECTOR_IMAGE>
```

Verify architecture and RepoDigest against the release contract.

`401 Unauthorized` normally means registry credentials are missing/incorrect. It is not an AstraVector application error.

## 5. Stack state

```bash
docker compose ps
docker compose logs --tail=200 postgres
docker compose logs --tail=200 qdrant
docker compose logs --tail=300 astravector
```

Use timestamps and correlation IDs when comparing events.

## 6. PostgreSQL

Check health:

```bash
docker compose exec postgres pg_isready -U astravector_app -d astravector
```

Common failures:

- password mismatch between `POSTGRES_PASSWORD` and `ASTRAVECTOR_DB_URL`;
- URL password not URL-encoded;
- damaged/unexpected persistent data;
- disk exhaustion;
- migration failure.

PostgreSQL is canonical state. Do not solve DB errors by deleting the PostgreSQL volume.

## 7. Qdrant

Check service from the Compose network or local diagnostic binding:

```bash
curl -fsS http://127.0.0.1:6333/ >/dev/null
```

If Qdrant data is lost but PostgreSQL is intact, treat Qdrant as a rebuild/reconciliation problem, not immediate business-data loss.

## 8. Model cache and Nexus

AstraVector bootstrap requires valid:

```text
model.onnx
model.onnx_data
tokenizer.json
```

Inspect AstraVector logs for:

```text
cache valid
downloading
checksum mismatch
download failed
model directory is not writable
```

If the cache exists, verify file hashes against the release contract. If the cache is empty, check DNS/TLS/Nexus credentials.

Known limitation: long cold transfer of `model.onnx_data` can fail on unstable networks. Prefer preloaded verified model cache for customer installs where reliability matters.

## 9. Permission problems

The AstraVector image runs as non-root UID/GID `10001`. The Compose bundle contains `model-cache-init` to prepare ownership.

If logs show permission denied:

- verify `model-cache-init` completed;
- inspect mounted volume ownership;
- do not change the application to root as the first workaround.

## 10. AstraVector readiness

HTTP:

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/ready
```

The distinction matters:

```text
health = process/service alive
ready  = ready to serve application traffic
```

Do not use `/health` as proof that model/DB/Qdrant initialization has completed.

## 11. gRPC health

Use the project's health script:

```bash
make health
```

Expected service:

```text
astravector.embedding.v1.AstraVectorRuntime = SERVING
```

If HTTP readiness passes but gRPC health fails, inspect AstraVector gRPC listener/health registration rather than PostgreSQL first.

## 12. Functional smoke

```bash
make smoke
```

Smoke failure must be classified by stage:

```text
ingestion rejected
vector status never ready
activation failed
retrieval transport error
retrieval returned no expected evidence
```

Preserve `.smoke/` evidence before modifying the environment.

## 13. Access-zone errors

If retrieval or ingestion reports access-zone validation/conflict problems, compare the caller payload with the documented contract:

- `accessZoneId`/`accessZoneIds` are UUID selectors;
- `accessZoneCode`/`accessZoneCodes` are code selectors;
- ID and code selector families are not an arbitrary union;
- `callerAccessLevel` is a visibility input, not authentication.

Do not fix access-zone errors by widening access levels or removing filters without understanding the security contract.

## 14. TTL/lifecycle surprises

When a document unexpectedly disappears from retrieval, inspect:

- effective TTL;
- document version lifecycle state;
- expiration timestamp;
- activation state;
- legal-hold/update operations if used;
- Qdrant projection state.

PostgreSQL remains the source of truth for lifecycle metadata.

## 15. Shutdown exit 137

Known current behavior:

```text
docker stop
→ AstraVector may exceed grace period
→ forced SIGKILL
→ ExitCode 137
→ OOMKilled=false
```

Do not diagnose this as OOM solely from exit code 137. Check `OOMKilled` and shutdown logs. The defect belongs to the AstraVector runtime lifecycle and is recorded separately.

## 16. What to collect for escalation

Collect without secrets:

```text
Git revision/release version
AstraVector image tag + digest
host architecture
Docker/Compose version
docker compose ps
relevant service logs
health output
smoke output/evidence
free disk/memory
problem timestamp and correlation ID
```

Never attach `.env`, Nexus passwords, DB passwords, registry tokens or Authorization headers.

## 17. Do not do these first

Avoid these destructive shortcuts:

```text
docker volume prune
rm -rf Docker data
recreate PostgreSQL volume
turn off TLS validation
run everything as root
publish DB ports to the Internet
replace immutable image tag with latest
```

Escalate with evidence before destroying canonical state.
