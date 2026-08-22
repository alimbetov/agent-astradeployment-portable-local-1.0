# DevOps Learning and Operations Guide for AstraDeployment

## Why this document exists

AstraDeployment is intentionally designed so that an application developer can operate it without first becoming a full-time DevOps engineer. This guide explains the concepts behind the commands already present in the repository.

## Mental model

Think in four layers:

```text
1. Artifact layer
   Docker images + model artifacts

2. Runtime layer
   containers/processes

3. State layer
   PostgreSQL + Qdrant + model cache

4. Operator layer
   Compose, env, scripts, health, smoke, recovery
```

When troubleshooting, identify the failing layer before changing anything.

## Docker image vs container vs volume

- **Image**: immutable application package.
- **Container**: one running instance of an image.
- **Volume**: persistent data independent of container lifetime.

AstraDeployment relies on this separation:

```text
container deleted        -> data survives
image upgraded           -> data survives
machine disk lost        -> volumes are lost unless backed up
```

## Docker Compose

Compose describes a small multi-container application declaratively.

In this project it defines:

```text
postgres
qdrant
astravector
model-cache-init
network
volumes
health/dependencies
```

Useful commands:

```bash
docker compose config
docker compose ps
docker compose logs -f astravector
docker compose up -d
docker compose stop
docker compose down
```

Do not use `down -v` casually because `-v` deletes named volumes.

## Environment variables

`.env.example` is documentation/template.

`.env` is local configuration and may contain secrets.

Never commit `.env`.

Useful distinction:

```text
configuration = URL, port, collection name
secret        = password, token, API key
```

## DNS inside Compose

Containers do not use `localhost` to reach sibling containers.

Inside the Compose network:

```text
postgres:5432
qdrant:6333
astravector:8080
astravector:50051
```

`localhost` inside AstraVector means AstraVector's own container, not PostgreSQL.

## Health vs readiness vs smoke

These are different tests.

### Process health

"Is the service process alive?"

### Readiness

"Can the service currently serve traffic with required dependencies?"

AstraVector provides `/ready` and gRPC health.

### Smoke test

"Does the business path actually work?"

The AstraDeployment smoke proves:

```text
ingest -> vector publication -> activate -> retrieve
```

A green container is not enough; a deployment is accepted only after smoke.

## Persistent data

### PostgreSQL

Primary recovery asset. Back it up first.

### Qdrant

Search projection. Important operationally, but rebuildable by design.

### Model cache

Large immutable model artifacts. Preserve it to avoid repeated multi-GB transfers.

## Logs

First commands during an incident:

```bash
docker compose ps
docker compose logs --tail=200 postgres
docker compose logs --tail=200 qdrant
docker compose logs --tail=300 astravector
```

Do not post secret-bearing environment dumps into tickets/chats.

## Disk usage

Useful commands:

```bash
df -h
docker system df
docker volume ls
docker image ls
```

Safe cleanup examples:

```bash
docker container prune
docker image prune
docker builder prune
```

Treat volume pruning as destructive.

## Networking troubleshooting

From the host:

```bash
curl http://127.0.0.1:8080/ready
curl http://127.0.0.1:6333/collections
```

From inside Compose network, use service names. If host access works but inter-container access fails, inspect Compose network/DNS. If inter-container access works but host access fails, inspect published ports/firewall.

## Common failure taxonomy

```text
Image pull failure
  -> registry auth/tag/architecture

Model bootstrap failure
  -> model cache permissions/Nexus/network/checksum

PostgreSQL startup failure
  -> credentials/volume/disk/migration

Qdrant startup failure
  -> volume/disk/schema

AstraVector NOT_READY
  -> check PostgreSQL, Qdrant, model, runtime logs

Smoke ingestion failure
  -> API contract/access zone/document identity

Smoke retrieval empty
  -> activation/vector sync/search scope/profile
```

## Version pinning

Never operate production from floating tags such as `latest`.

Record:

```text
image tag
image digest
PostgreSQL image version
Qdrant image version
model version
model hashes
AstraDeployment repository revision/release
```

This makes customer installations reproducible.

## What to learn next

Recommended DevOps learning order for this project:

1. Docker images/containers/volumes/networks.
2. Docker Compose lifecycle and healthchecks.
3. Linux process signals and logs.
4. PostgreSQL backup/restore basics.
5. TCP/DNS/HTTP troubleshooting.
6. Kubernetes Pods/Deployments/Services/ConfigMaps/Secrets/PVCs.
7. readiness/liveness/startup probes.
8. resource requests/limits.
9. Helm templating and values.
10. monitoring/alerting and backup automation.

The repository should remain usable while these skills are learned progressively.
