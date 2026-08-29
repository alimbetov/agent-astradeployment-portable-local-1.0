# AstraVector Image Refresh 2026-08-29

## Source

The AstraVector image was rebuilt from `alimbetov/llm2` `main` at:

```text
f6493fa86d8c7c80678989ffcb8858b5f5b684dd
```

This main includes the session-finalize activation remediation and the follow-up formatting fix required for green CI.

## Published image

```text
registry.astrabase.asia/astravector:sha-f6493fa
registry.astrabase.asia/astravector:0.4.1-image-contract
```

Both tags were pushed to `registry.astrabase.asia/astravector` with digest:

```text
sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
```

## Local image checks

```text
OS/architecture: linux/arm64
Image ID: sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
Approximate size: 101333259 bytes
Runtime user: 10001:10001
```

The final image contains the AstraVector runtime, model bootstrap and entrypoint. The large BGE-M3 model bundle is not embedded in the image and remains a runtime model-cache/Nexus concern.

## Deployment update

`deploy/local` now defaults to the immutable image tag:

```text
ASTRAVECTOR_IMAGE=registry.astrabase.asia/astravector:sha-f6493fa
ASTRAVECTOR_EXPECTED_DIGEST=sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
```

The moving tag `0.4.1-image-contract` is available for operator convenience, but reproducible local deployment should prefer the immutable `sha-f6493fa` tag.

## Integration reminder

AstraIndexator sends logical document content to AstraVector over the public gRPC ingestion facade. It does not connect directly to AstraVector PostgreSQL or Qdrant.

Minimum smoke-proven sequence:

```text
IndexLogicalDocument
-> GetDocumentVectorStatus
-> ActivateDocumentVersion
-> POST /api/v1/retrieve
```
