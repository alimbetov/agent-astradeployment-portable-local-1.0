# AstraDeployment Platform Deployment Guide

## Purpose

This guide explains how to deploy AstraVector as a platform component on a single server today and how the same deployment contract should evolve toward Kubernetes.

Current production of this repository is **Portable Local Deployment 1.0**. Kubernetes/Helm are future profiles, not yet claimed implemented here.

## Deployment modes

AstraDeployment should support two infrastructure patterns.

### Bundled dependencies

Use when the customer does not provide PostgreSQL/Qdrant:

```text
single Docker host / future Kubernetes namespace
  ├── PostgreSQL + pgvector
  ├── Qdrant
  └── AstraVector
```

This repository currently implements this mode with Docker Compose.

### External dependencies

Preferred for larger customers:

```text
AstraVector
  ├── customer PostgreSQL
  └── customer Qdrant
```

In this mode, AstraDeployment must not install or own the customer databases. It receives connection endpoints and credentials.

## Single-server deployment

### Prerequisites

- Docker Engine / Docker Desktop
- Docker Compose v2
- sufficient disk for image + database data + model cache
- access to private Docker registry
- model cache or Nexus reader credentials

### Install

```bash
git clone https://github.com/alimbetov/agent-astradeployment-portable-local-1.0.git
cd agent-astradeployment-portable-local-1.0/deploy/local
cp .env.example .env
```

Fill the required secrets and database URL, then authenticate:

```bash
docker login registry.astrabase.asia -u astra-reader
```

Run:

```bash
make preflight
make start
make health
make smoke
```

### Normal operations

Status:

```bash
make health
```

Functional verification:

```bash
make smoke
```

Stop while preserving data:

```bash
make stop
```

Remove containers/network but keep data:

```bash
make cleanup
```

## Customer installation checklist

Before installation collect:

```text
Deployment type: Docker server / Kubernetes
CPU architecture: arm64 / amd64
CPU/RAM available
Disk/storage class
PostgreSQL: bundled / external
Qdrant: bundled / external
Internet access: online / restricted / air-gapped
Model delivery: Nexus / preloaded cache / future model PVC
Registry access
DNS / ingress requirements
Backup destination
Monitoring/logging requirements
Security requirements
```

Do not start installation before these inputs are known.

## Networking

For local single-node deployment, ports should remain loopback-only unless explicitly required.

For Kubernetes, expected service pattern is:

```text
Spring Boot / AstraIndexator
        |
        v
AstraVector ClusterIP Service
        |
   AstraVector pods
        |
   +----+----+
   |         |
PostgreSQL  Qdrant
```

AstraVector itself should normally not be exposed directly to the public Internet.

## Persistence model

Critical recovery priority:

```text
1. PostgreSQL
2. model cache
3. Qdrant
```

PostgreSQL is canonical state.

Qdrant is a rebuildable projection and can be reconstructed from canonical state using AstraVector recovery/reconciliation mechanisms.

Model cache is an immutable runtime artifact cache. It can be reacquired from Nexus or transferred offline.

## Backup baseline

At minimum customer operations must define:

- PostgreSQL logical/physical backup schedule;
- restore test schedule;
- retention policy;
- encryption/access to backups;
- optional Qdrant snapshot/volume backup;
- optional model cache archive for offline/fast recovery.

A backup that has never been restored in a test is not considered proven.

## Upgrade process

Never replace an image implicitly.

Recommended sequence:

```text
publish immutable new image
 -> record digest
 -> test in non-production
 -> database backup
 -> deploy new image
 -> health
 -> smoke
 -> monitor
 -> retain rollback image/config
```

Database migrations must be reviewed for backward/rollback compatibility before customer rollout.

## Toward Kubernetes

The Compose reference maps directly to Kubernetes concepts:

```text
Docker Compose            Kubernetes
--------------            ----------
service                   Deployment/StatefulSet
network DNS               Service
.env                      ConfigMap + Secret
named volume              PVC
healthcheck               startup/readiness/liveness probes
restart policy            controller reconciliation
image tag/digest           image + imagePullSecrets
```

### AstraVector

Use a `Deployment` with multiple replicas only after the image is available for the customer's architecture and shutdown/readiness behavior is acceptable.

Expected pod contract:

- immutable image by digest;
- non-root runtime;
- PostgreSQL/Qdrant via service DNS or external endpoints;
- model mounted/readable at `/models/bge-m3`;
- readiness tied to actual AstraVector readiness;
- graceful termination budget greater than application drain timeout;
- resource requests/limits based on measured inference usage.

### Model provisioning

For multiple AstraVector pods, avoid every pod independently downloading 2.2 GB.

Preferred future patterns:

```text
model init/provision job
      |
      v
shared/preloaded model storage
      |
      +--> AstraVector pod 1
      +--> AstraVector pod 2
      +--> AstraVector pod N
```

Storage choice depends on the customer's cluster. If a shared RWX filesystem is unavailable, pre-provision per-node/per-pod caches or use an object/model registry with controlled init downloads.

### PostgreSQL

For serious production customers, prefer their managed/HA PostgreSQL rather than embedding a single PostgreSQL pod inside the application chart.

A future Helm profile should support:

```yaml
postgresql:
  enabled: false
externalPostgresql:
  host: ...
```

and a bundled development/small-install mode separately.

### Qdrant

Use the same principle:

```yaml
qdrant:
  enabled: false
externalQdrant:
  url: ...
```

A bundled Qdrant is acceptable for small installations, but HA/cluster sizing should be treated as a separate infrastructure concern.

## Observability

Minimum operational signals:

- AstraVector `/ready`;
- gRPC health;
- process/container restart count;
- CPU/RAM;
- request latency/error count;
- PostgreSQL connectivity/pool saturation;
- Qdrant availability/latency;
- outbox backlog/failures;
- disk usage for PostgreSQL/Qdrant/model cache.

Centralized logs and metrics should be integrated with the customer's platform rather than forcing a proprietary observability stack.

## Security baseline

- keep PostgreSQL/Qdrant private;
- use least-privilege DB accounts;
- store secrets outside Git;
- use Kubernetes Secrets/external secret manager in Kubernetes;
- use private image registry credentials via imagePullSecrets;
- TLS at ingress/gateway boundaries;
- define API authentication separately from retrieval `callerAccessLevel`;
- rotate Nexus/registry/customer credentials.

## Air-gapped installations

For restricted customers prepare an offline kit containing at least:

```text
AstraVector OCI image(s)
PostgreSQL/pgvector image
Qdrant image
helper images used by deployment
BGE-M3 model bundle
SHA256 manifest
AstraDeployment repository/release bundle
customer .env/Secret templates without secrets
```

Load images into the customer's internal registry and pre-populate model storage before startup.

## Definition of Done for a customer deployment

A deployment is accepted only when:

1. required containers/pods are healthy;
2. PostgreSQL is reachable and migrations are complete;
3. Qdrant collection is compatible;
4. BGE-M3 artifacts match expected checksums;
5. AstraVector readiness is healthy;
6. the canonical functional smoke passes;
7. restart preserves data/model cache;
8. backup/restore responsibility is assigned;
9. image/config versions are recorded;
10. known limitations are documented for the customer.
