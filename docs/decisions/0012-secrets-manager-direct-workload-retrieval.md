# ADR 0012: Retrieve the database credential directly from Secrets Manager

- Status: Accepted
- Date: 2026-08-03

## Context

P7.1 used a one-session `rds-credentials` Kubernetes Secret because the managed
database credential boundary was intentionally deferred. P7.3 needs to prove
Secrets Manager access without leaving the password in Kubernetes configuration
or creating a long-lived secret synchronization controller for this small
learning profile.

The API, migration hook, and seed hook must all use the same database URL and
must work locally without AWS credentials. P7.2 already has a separate,
session-scoped API ServiceAccount for its S3 image role.

## Decision

Store one JSON `DATABASE_URL` field in a temporary, encrypted Secrets Manager
secret. The API, migration Job, and seed Job retrieve it directly with the AWS
SDK using the `bedoux-api-secrets` ServiceAccount's IRSA role. The role trust is
restricted to that exact ServiceAccount in the `bedoux` namespace, and its only
data permission is `secretsmanager:GetSecretValue` on that exact secret ARN.

Secrets Manager mode injects only the non-secret secret name and region into
Pods. It does not create or synchronize a Kubernetes Secret. Local and kind
profiles continue to use `BEDOUX_DATABASE_URL`, and tests inject a mocked
Secrets Manager client without AWS credentials. P7.3 keeps the S3 and database
identities separate; a combined S3-plus-Secrets Manager session is not part of
this task.

## Consequences

- The credential is not exposed through Kubernetes Secret objects, Helm output,
  CI logs, or the frontend.
- The API image owns one small, testable AWS SDK boundary; migrations and seed
  use the same code path rather than a second shell-specific implementation.
- The temporary secret value is present in encrypted Terraform state, which is
  an accepted consequence of creating the RDS credential and its session secret
  as one reviewed Terraform apply. The state bucket remains on the persistent
  allowlist and is never targeted by session teardown.
- A future production profile may choose a CSI/External Secrets controller if
  it needs rotation without Pod restarts; that is outside this learning task.
