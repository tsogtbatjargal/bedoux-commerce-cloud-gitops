# ADR 0011: Keep product-image delivery behind an API-side presigned-S3 adapter

- Status: Accepted
- Date: 2026-08-02

## Context

P6 deliberately served the synthetic catalog images as static files in the web
container. P7.2 adds S3 as a managed-service exercise, but exposing S3 details
to the React application would couple the UI to a storage provider and would
not demonstrate the API workload's AWS identity.

The project needs to keep the bucket private and demonstrate least-privilege
IAM Roles for Service Accounts (IRSA), without proxying image bytes through
FastAPI or persisting short-lived URLs in PostgreSQL.

## Decision

The catalog API exposes one storage-neutral `image_url` field. Product records
retain a stable image key/path, never a presigned URL.

The default `static` adapter returns the existing `/static/products/<file>`
URL. In `s3` mode, the API uses its Kubernetes ServiceAccount's IRSA identity
to generate a short-lived presigned S3 `GetObject` URL for the product-image
key. The API does not proxy image bytes.

The S3 bucket remains private with all public access blocked. The API's IRSA
role receives only `s3:GetObject` on this project's product-image prefix. The
frontend consumes `image_url` only; it has no S3 configuration or AWS SDK.

## Consequences

- Switching static versus S3 delivery is backend configuration, so the
  frontend contract and rendering code stay unchanged.
- A presigned URL can expire normally; the frontend obtains a fresh value on
  the next catalog or product API response rather than storing it.
- P7.2 can prove S3 access through a scoped workload identity (T-702), while
  local tests use the static adapter and a mocked S3 client without AWS
  credentials.
- Uploading or managing product images is outside the application API's scope
  for this learning phase; only the synthetic, version-controlled catalog
  assets are staged into the session bucket.
