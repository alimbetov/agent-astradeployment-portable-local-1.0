# Access Zone and TTL Semantics

## Purpose

This document is the consumer-facing reference for access-zone and TTL behavior that external services must understand when integrating with AstraVector.

It summarizes current AstraVector behavior observed in `llm2/main`. Where behavior is not sufficiently formalized for safe cross-service use, it is marked as a contract gap.

---

## Access zones

### Representations

AstraVector supports two representations of the same retrieval/ingestion scope:

```text
access_zone_id    = UUID-backed internal identifier
access_zone_code  = short immutable code
```

For HTTP retrieval the request surface currently supports both singular and plural forms:

```text
accessZoneId
accessZoneIds
accessZoneCode
accessZoneCodes
```

For ingestion/session APIs, the canonical operation is scoped to one access zone and accepts one ID and/or one code according to the protobuf request.

### Code format

A valid access-zone code is four ASCII digits:

```text
0000 .. 9999
```

Recommended client-side validation:

```regex
^[0-9]{4}$
```

### Retrieval resolution rules

A retrieval request must provide at least one access-zone selector.

The server resolves IDs and codes to UUIDs. If both code-based and ID-based selectors are supplied, they are not treated as independent unions. They must resolve to the same effective set of access zones; otherwise the request is rejected as an access-zone ID/code mismatch.

Consumer rule:

```text
Prefer ONE representation in normal calls.
Do not send IDs and codes together unless intentionally performing a consistency check.
```

Recommended Spring-facing API:

```json
{
  "accessZoneCodes": ["1500", "1501"]
}
```

Use UUID selectors for internal/system integrations that already own the canonical UUIDs.

### Singular and plural semantics

Singular values should be understood as convenience selectors for one zone. Plural values represent a set of zones.

External services should normalize their own application request into one collection before constructing the AstraVector wire request, for example:

```java
record AccessZoneScope(
    List<String> ids,
    List<String> codes
) {}
```

Avoid embedding business authorization logic into this DTO. It is only a search/indexing scope.

### Maximum zones

The current deployment default allows up to 50 access zones in a retrieval request. This is a configuration limit, not an eternal protocol constant. Client applications should avoid hard-coding it as a business invariant.

### `callerAccessLevel`

Current values:

```text
PUBLIC
INTERNAL
CONFIDENTIAL
RESTRICTED
```

`callerAccessLevel` is a **visibility input**, not authentication.

Never implement:

```text
browser/user input -> callerAccessLevel -> trusted authorization
```

Production systems should derive the effective access level from an authenticated/trusted principal or gateway policy and then pass it to AstraVector.

### Ingestion scope

A document version is indexed inside one effective access zone. The future AstraIndexator should receive access-zone assignment from the platform/business boundary and forward it; it must not invent access zones from document content.

---

## TTL: two distinct contracts

AstraVector currently exposes two TTL-shaped concepts that must not be conflated.

### 1. Full ingestion TTL policy

Single-call/full ingestion uses a TTL policy concept with fields such as:

```text
mode
ttl_seconds
expires_at
```

Current relevant semantics:

```text
TTL_MODE_RELATIVE + ttl_seconds > 0
```

is the supported relative TTL form.

The current implementation converts relative seconds into its internal day-based lifetime policy with upward rounding. Therefore consumers must not assume that arbitrary second precision is preserved end-to-end as an exact expiry timestamp.

`TTL_MODE_ABSOLUTE`/`expires_at` may exist in the wire model, but current implementation support is not sufficient to promise absolute-expiry semantics to external clients. Treat absolute TTL as unsupported until AstraVector explicitly stabilizes it.

### 2. Session ingestion `ttl_days`

Chunked/session ingestion uses:

```text
ttl_days
```

in days.

Important zero-value rule:

```text
ttl_days = 0
```

does **not** automatically mean "never expire".

It means: use the access-zone/default TTL policy. Only if the resolved policy itself permits a non-expiring document may the effective result become non-expiring.

Consumer rule:

```text
0 = inherit zone/platform TTL policy
>0 = request explicit relative lifetime in days
```

Do not expose `0 = forever` in a Spring or AstraIndexator business API.

### Current default bounds

The current implementation/configuration uses bounded TTL values, with a typical overall range of approximately 1..3650 days for finite lifetimes and a default policy around 90 days before access-zone-specific resolution.

These values are deployment/configuration defaults, not permanent protocol constants. External DTOs should validate only clearly stable rules and keep operator limits configurable.

### Access-zone TTL policy

Access zones can have their own `default_ttl_days`. Code ranges may influence auto-created access-zone policy, but downstream services should **not duplicate the code->TTL matrix**.

Correct dependency direction:

```text
AstraVector/access-zone registry resolves policy
        ↓
external client consumes effective behavior
```

Incorrect:

```text
Spring/AstraIndexator hard-codes code ranges and reimplements TTL policy
```

---

## TTL lifecycle expectations

The architectural contract remains:

```text
PostgreSQL = canonical document/vector state
Qdrant     = rebuildable search projection
```

External services should therefore treat AstraVector as owner of:

- effective document expiry;
- expired-document search exclusion;
- projection reconciliation;
- cleanup/recovery behavior;
- republishing/removal in Qdrant.

A client should never try to delete Qdrant points itself when a TTL expires.

### Reindex/version guidance

Recommended external service policy:

- keep `document_id` stable across revisions of the same logical document;
- increment `document_version` when source content changes;
- set TTL policy explicitly according to the business rule for the new version;
- do not infer that a previous version's remaining lifetime is automatically inherited unless AstraVector contract explicitly guarantees that behavior.

---

## Spring Boot retrieval examples

### One code

```json
{
  "question": "Каков срок действия документа?",
  "accessZoneCode": "1500",
  "callerAccessLevel": "INTERNAL",
  "profile": "BALANCED"
}
```

### Multiple codes

```json
{
  "question": "Найди регламент",
  "accessZoneCodes": ["1500", "1501"],
  "callerAccessLevel": "INTERNAL",
  "profile": "SEMANTIC",
  "maxContexts": 5
}
```

### Invalid mismatch pattern

Do not intentionally construct requests like this unless the ID is known to correspond to the same code:

```json
{
  "question": "...",
  "accessZoneId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  "accessZoneCode": "1500"
}
```

If the code resolves to another UUID, AstraVector rejects the request.

---

## AstraIndexator session example

Recommended business-level intent:

```text
accessZoneCode = 1500
documentId = stable UUID
documentVersion = 3
ttlDays = 0
```

means:

```text
index document version 3 in zone 1500
using the effective TTL policy of that zone/platform
```

It does NOT mean:

```text
keep forever
```

---

## Contract gaps to resolve before wider external adoption

1. Publish an explicit externally versioned TTL contract, including supported modes and rounding semantics.
2. Add contract tests for `ttl_days=0`, explicit finite TTL, zone default TTL and non-expiring policy.
3. Publish access-zone selector test vectors covering singular/plural and ID/code mismatch behavior.
4. Keep authorization/authentication separate from `callerAccessLevel` and access-zone selectors in all client SDKs.
