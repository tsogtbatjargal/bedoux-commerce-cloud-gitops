# ADR 0002: Defer Route 53/ACM, RDS, S3 images, and Secrets Manager from the MVP

- Status: Accepted
- Date: 2026-07-17

## Context

The first EKS sessions must stay near USD 2–4 each inside a USD 20/month cap, and each new
AWS service in the first cluster session adds cost, IAM surface, and failure modes that slow
the actual learning goal (EKS, networking, the ALB controller). The pasted draft plan
front-loaded Route 53, ACM, RDS, S3, and Secrets Manager into the first deployment.

## Decision

The learning MVP (phases P5–P6):

- is reached by the **raw ALB DNS name over HTTP** — no Route 53 hosted zone, no custom
  domain, no ACM certificate;
- runs **PostgreSQL in-cluster** using the same chart already proven on kind;
- serves product images as **static files in the frontend container**, behind the storage
  adapter boundary from ADR 0001;
- uses **Kubernetes Secrets** for configuration.

The deferred services return in **P7** as short-lived, same-day-teardown exercises (Single-AZ
RDS + migration job, S3 via the adapter with a scoped workload identity, Secrets Manager for
the DB credential). Route 53 + ACM/TLS remain **documented in the production profile** (and in
Terraform/diagrams) but are not deployed on the learning budget. A NAT Gateway is never part
of the learning profile.

## Consequences

- First cluster sessions have one moving part and a predictable ~$2–4 cost.
- The interview story still covers RDS, S3, Secrets Manager, TLS, and DNS — as a deliberate
  cost-versus-scope decision, which is itself demonstrable judgment.
- The demo URL is an unfriendly ALB hostname over HTTP until the production profile is
  exercised; acceptable for a learning environment.
- The adapter boundary (ADR 0001) must be kept honest so the P7 S3 flip stays a config change.
