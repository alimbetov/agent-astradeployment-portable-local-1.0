# Server Installation Runbook

## Purpose

This runbook defines the supported single-node server installation path for AstraDeployment Portable Local Deployment 1.0. It is intended for a Linux host operated by a customer or integrator.

## Scope

Current 1.0 topology:

```text
Linux server
  └── Docker Compose
      ├── PostgreSQL + pgvector
      ├── Qdrant
      ├── AstraVector
      └── persistent model cache
```

AstraIndexator, Kubernetes, Helm and HA databases are outside the current implementation scope.

## Prerequisites

Minimum operational prerequisites:

- Linux x86_64 or arm64 host compatible with the published AstraVector image;
- Docker Engine;
- Docker Compose v2;
- persistent local disk;
- outbound HTTPS access to `registry.astrabase.asia`;
- outbound HTTPS access to `nexus.astrabase.asia` unless a verified model cache is preloaded;
- registry reader credentials;
- Nexus model reader credentials;
- DNS resolution for the required Astra domains;
- enough free disk for images, PostgreSQL, Qdrant and the ~2.2 GB BGE-M3 external tensor file.

Before customer installation, verify the exact AstraVector image architecture and digest recorded by the release bundle.

## Recommended host layout

Keep deployment source and operational data conceptually separate:

```text
/opt/astra/
├── deployment/       # Git checkout / release bundle
├── backups/          # protected backups
└── exports/          # temporary export artifacts
```

Docker named volumes remain managed by Docker unless the customer requires host-mounted storage.

## Installation procedure

Clone or unpack the release:

```bash
sudo mkdir -p /opt/astra
sudo chown "$USER":"$USER" /opt/astra
cd /opt/astra
git clone https://github.com/alimbetov/agent-astradeployment-portable-local-1.0.git deployment
cd deployment/deploy/local
```

Create the environment file:

```bash
cp .env.example .env
chmod 600 .env
```

Set at least:

```text
POSTGRES_PASSWORD=<secret>
ASTRAVECTOR_DB_URL=postgres://astravector_app:<URL-ENCODED-PASSWORD>@postgres:5432/astravector
ASTRAVECTOR_NEXUS_USERNAME=<reader-user>
ASTRAVECTOR_NEXUS_PASSWORD=<reader-secret>
```

Do not commit `.env` and do not copy it into support tickets or logs.

Authenticate to the private registry:

```bash
docker login registry.astrabase.asia -u <reader-user>
```

Run preflight:

```bash
make preflight
```

Preflight must pass before installation continues.

Start the stack:

```bash
make start
```

Verify health:

```bash
make health
```

Run functional smoke:

```bash
make smoke
```

The smoke is the acceptance gate because it proves more than process availability: it exercises ingestion, vector publication, activation and retrieval.

## Expected local bindings

Default bindings are loopback-only:

```text
127.0.0.1:50051 AstraVector gRPC
127.0.0.1:8080  AstraVector HTTP
127.0.0.1:9090  AstraVector metrics
127.0.0.1:6333  Qdrant diagnostics
```

PostgreSQL is not published to the host by default.

For customer-facing exposure, place a reverse proxy, ingress gateway or service mesh in front of AstraVector instead of changing the Compose ports to `0.0.0.0` without a security review.

## Installation acceptance checklist

Installation is accepted when all of the following are true:

- `make preflight` passes;
- AstraVector image digest matches the release contract;
- PostgreSQL is healthy;
- Qdrant is reachable;
- AstraVector `/ready` passes;
- gRPC health reports `SERVING`;
- `make smoke` returns the expected evidence;
- named volumes exist;
- `.env` permissions are restricted;
- no database ports are publicly exposed;
- backup location and operator ownership are agreed with the customer.

## Restart

Normal restart preserves persistent volumes:

```bash
make stop
make start
make health
```

Run `make smoke` after planned maintenance or version upgrades.

## Removal

Remove containers and network while preserving data:

```bash
make cleanup
```

Destructive data removal is intentionally separate:

```bash
make destroy
```

Only use destructive removal after verified backups and explicit customer approval.

## Production hardening notes

For a customer server, additionally define:

- host firewall policy;
- OS patch policy;
- Docker daemon access policy;
- log retention;
- disk monitoring;
- backup schedule;
- secret rotation procedure;
- TLS termination;
- monitoring/alerting destination;
- maintenance window and rollback owner.

## Known limitations

The current AstraVector baseline has a known graceful-shutdown defect where forced termination may occur after the grace period. Cold download of the large model external tensor file through Nexus/Caddy has also been observed to be sensitive to network interruptions. Prefer a verified warm model cache for repeatable customer installations until those runtime issues are closed upstream.
