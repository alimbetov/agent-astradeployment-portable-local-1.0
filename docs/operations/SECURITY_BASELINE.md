# Security Baseline

## Purpose

This document defines the minimum security baseline for AstraDeployment Portable Local Deployment 1.0 and the expected hardening direction for customer environments.

## Trust model

The current local profile is designed for trusted local/server networking. It must not be interpreted as Internet-ready simply because the services start successfully.

Security boundaries:

```text
operator credentials
→ Docker/registry/Nexus

service network
→ AstraVector/PostgreSQL/Qdrant

application caller
→ AstraVector API
```

`callerAccessLevel` and access-zone selectors are application visibility inputs. They are not substitutes for authenticating the caller.

## Secrets

Secrets must never be committed to Git.

Secret examples:

- PostgreSQL password;
- Nexus username/password;
- registry credentials/tokens;
- future AstraVector API keys;
- future Qdrant API keys;
- TLS private keys.

Local profile uses `.env`; keep it mode `0600` where practical.

Customer environments should prefer a dedicated secret manager or Kubernetes Secret/external secret system when moving beyond single-node Compose.

## Image supply chain

Use immutable image identity:

```text
repository:tag
+ digest
```

Never promote `latest` as the only production identity.

For every release record:

- image tag;
- digest;
- architecture;
- build/source revision;
- validation evidence.

A deployment script must fail or alert when the pulled digest differs from the approved release contract.

## Registry and model repository

Use separate roles:

```text
reader/puller
publisher
administrator
```

Runtime hosts need reader access only. Publisher/admin credentials must not be distributed to customer runtime nodes.

Use TLS verification. Do not add `--insecure`, disable certificate verification or configure an insecure registry as a routine workaround.

## Container privilege

AstraVector runs as non-root. Preserve that property.

Do not solve volume problems by switching the service permanently to root.

For future Kubernetes hardening prefer:

```text
runAsNonRoot: true
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities.drop: [ALL]
```

with writable storage mounted only where required.

## Network exposure

Current Compose defaults expose application/diagnostic ports only on loopback.

Do not publish PostgreSQL directly to external networks unless the customer architecture explicitly requires it and firewall/TLS/authentication controls are defined.

Recommended customer topology:

```text
client application
      |
      v
reverse proxy / gateway / ingress
      |
      v
AstraVector private service network
   |                 |
PostgreSQL         Qdrant
private            private
```

## Authentication

AstraVector transport authentication is a separate concern from access-zone and access-level filtering.

Until a production transport auth mechanism is formally selected, keep AstraVector on a trusted private network and control ingress externally.

Future acceptable patterns include:

- API key at gateway/service boundary;
- mTLS between services;
- OAuth2/JWT validation at an API gateway;
- service mesh identity.

Do not retrofit several mechanisms simultaneously without a clear trust model.

## Access zones

Access zones are part of data isolation/search scoping. External services must follow the documented selector contract and must not widen scope after receiving a client request.

Security rule:

```text
upstream authorization
→ determine allowed zones/access level
→ AstraVector retrieval scope
```

Do not accept arbitrary `accessZoneIds` from an untrusted end user and forward them without authorization in the calling service.

## Logging

Logs may contain identifiers and operational metadata. Default production logging should avoid full document bodies, secrets and authorization headers.

Safe to log when required:

- correlation ID;
- service/version;
- document ID/version where customer policy permits;
- access-zone identifier where policy permits;
- operation state;
- error code;
- duration.

Avoid logging:

- passwords/tokens;
- `.env`;
- complete confidential document text;
- temporary `.netrc` contents;
- private keys.

## PostgreSQL

PostgreSQL is canonical state and therefore a critical security asset.

Require:

- unique strong credentials;
- private network exposure;
- backup encryption according to customer policy;
- least privilege for application user;
- controlled administrative access;
- audit/logging policy where required.

Do not share one PostgreSQL superuser password between application and operator workflows.

## Qdrant

Qdrant contains a searchable projection and may include payload metadata. Protect it as sensitive data even though it is rebuildable.

Prefer private service networking and authentication/TLS if Qdrant is external to the trusted deployment network.

## Model artifacts

Treat model files as immutable artifacts. Verify SHA256 before use. Do not execute a model downloaded without integrity verification.

For air-gapped customers, transport model cache with a manifest and validate hashes after transfer.

## Host hardening

Customer production baseline should include:

- supported OS version;
- regular security updates;
- SSH key authentication;
- restricted sudo;
- firewall;
- Docker socket restricted to administrators;
- disk encryption where required;
- time synchronization;
- monitoring for disk/memory pressure.

Access to the Docker socket is effectively root-level control of the host and must be treated accordingly.

## Backup security

Backups may contain all customer business data. Protect backup storage with:

- restricted access;
- encryption at rest;
- secure transfer;
- retention/deletion policy;
- restore auditing.

Never copy database backups to public object storage without approved controls.

## Security acceptance checklist

Before customer handover verify:

- no committed secrets;
- `.env` restricted;
- runtime uses reader-only registry/Nexus accounts;
- image digest verified;
- PostgreSQL not publicly exposed;
- Qdrant/AstraVector exposure matches architecture;
- TLS termination defined for remote clients;
- backup storage protected;
- logging excludes secrets;
- access-zone authorization responsibility assigned to upstream service;
- administrator accounts and rotation owner documented.

## Future Kubernetes translation

Compose security concepts translate to Kubernetes as:

```text
.env secrets          → Secret / external secret store
private network       → Service + NetworkPolicy
non-root container    → securityContext
loopback gateway      → Ingress/Gateway/API gateway
named volume          → PVC
registry login        → imagePullSecret
operator RBAC         → Kubernetes RBAC
```

This baseline should be preserved when Kubernetes support is implemented.
