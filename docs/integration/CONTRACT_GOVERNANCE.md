# AstraVector External Contract Governance

## Purpose

This document defines how AstraDeployment publishes consumer-facing integration contracts for external services without becoming a second source of truth for AstraVector behavior.

## Source-of-truth hierarchy

```text
llm2/proto/astravector_embedding.proto
        |
        | canonical gRPC wire contract
        v
llm2/src/grpc/mod.rs + llm2/src/http.rs + access-zone/config implementation
        |
        | authoritative runtime semantics and validation
        v
AstraDeployment integration documentation
        |
        | consumer-oriented specification
        v
Spring Boot adapters / AstraIndexator / other clients
```

AstraDeployment must never silently redefine semantics that differ from AstraVector.

## Contract versioning

External consumers should depend on a versioned AstraVector external contract, not on a moving `main` branch.

Recommended version identifier:

```text
AstraVector External Contract 1.0
```

Every contract release should record:

- AstraVector repository revision/commit;
- protobuf file revision;
- HTTP contract revision;
- validated AstraVector image tag/digest where applicable;
- machine-readable schemas and contract fixtures revision.

## Compatibility rules

Typically backward-compatible:

- adding a new optional protobuf field using a new field number;
- adding new optional response diagnostics;
- adding a new degradation code when clients tolerate unknown values;
- adding metadata keys;
- adding a new optional JSON field when clients ignore unknown fields.

Breaking unless explicitly versioned:

- renaming/removing/reusing a protobuf field number;
- changing field meaning or units;
- changing TTL units or zero/default semantics;
- changing access-zone resolution semantics;
- changing hash canonicalization;
- changing idempotency/retry semantics;
- turning an optional field into a required field;
- changing enum/string state meaning so older clients make unsafe decisions.

## Client rules

External clients must:

- use generated protobuf classes for gRPC ingestion;
- avoid importing Rust implementation/persistence models;
- never read/write AstraVector PostgreSQL or Qdrant directly;
- treat unknown optional JSON response fields as forward-compatible;
- tolerate unknown degradation codes;
- pin a tested contract revision in CI;
- use contract fixtures/golden examples in consumer tests.

## Contract gaps

If AstraVector implementation exposes behavior that is required by clients but not yet formally published, document it as a **contract gap** instead of promoting an inferred behavior to a guarantee.

Current notable gaps identified by research:

1. Canonical cross-language byte specification and golden vectors for `batch_content_hash`.
2. Canonical cross-language specification and golden vectors for `final_content_hash`.
3. Session status is currently surfaced as a string rather than a protobuf enum.
4. Structured typed error reasons are incomplete; some client decisions currently depend on gRPC code plus message/reason text.
5. Session ingestion finalize currently uses its own activation semantics; external clients must observe status instead of assuming a lifecycle state.

These gaps should be resolved in AstraVector before multiple independent production consumers rely on them.
