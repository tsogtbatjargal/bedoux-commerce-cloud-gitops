# Bedoux learning infrastructure

This is the P6 Terraform definition of the P5 learning environment. The root
configuration starts with a local backend for cold planning; P6.2 bootstraps a
separate persistent state bucket before migrating this root state to S3.

## Design boundaries

- Region is pinned to `ca-central-1`.
- The VPC has public subnets only and **no NAT Gateway resources**. The single
  Spot node uses public IP addressing, matching the verified P5 profile.
- EKS, its managed Spot node group, ECR repositories, cluster/node IAM roles,
  the EKS OIDC provider, the EBS CSI IRSA role/add-on, and the ALB Controller
  IRSA role/policy are represented as code.
- The P6.3 GitHub Actions OIDC provider and `bedoux-github-actions-role` are
  represented as code but first created only in P6.4's live AWS session. Its
  trust is restricted to this repository's protected `main` branch through the
  exact GitHub OIDC subject emitted by this organization's custom numeric-ID
  subject template; its AWS
  permissions are limited to pushing the two ECR repositories and describing
  the learning EKS cluster. EKS grants it edit access only in the `bedoux`
  namespace.
- `bedoux-iam-scoped` and the EKS node-group service-linked role are account
  foundations from P4/P5 and are deliberately not managed here.
- P6.2/P6.4 must import the persistent P5 ECR repositories and IAM roles before an
  apply, rather than attempting to create duplicate names. On P6.4's first session, the
  helper deliberately skips the not-yet-created GitHub OIDC provider, role, and policy; the
  reviewed apply creates and tracks them. Later sessions import those identity resources too.
  Before `destroy`, run
  `scripts/terraform-persistent-state.sh detach --execute` so Terraform removes
  only session resources while those allowlisted resources remain. After P6.4,
  that allowlist also includes the GitHub OIDC provider and deployment role/policy.
- `bootstrap/` owns the persistent, versioned, encrypted Terraform state bucket.
  It is intentionally never part of the session-environment destroy.
- EBS CSI is pinned to `v1.63.0-eksbuild.1`, verified compatible and default for
  EKS `1.34` in `ca-central-1` on 2026-07-30.
- P7.1 adds an **opt-in only** RDS for PostgreSQL 16.14 module. It is disabled
  by default, creates a short-lived encrypted Single-AZ `db.t4g.micro` instance
  with fixed 20 GiB gp3 storage, no public address, no backups/final snapshot,
  and a database security group accepting TCP 5432 only from the EKS cluster
  security group. The two existing public subnets satisfy the RDS subnet-group
  requirement; no NAT Gateway is added. A session enables it with
  `-var=rds_enabled=true` and an out-of-band `TF_VAR_rds_master_password`.
  See [`docs/runbooks/p7-1-rds-session.md`](../../docs/runbooks/p7-1-rds-session.md).
- P7.2 adds an **opt-in only** product-image module. With `s3_images_enabled=true`, it
  creates a private, encrypted, versioned, force-destroyable session bucket, stages only the
  six version-controlled synthetic SVGs under `products/`, and creates a temporary API IRSA
  role with only `s3:GetObject` on that prefix. It is not on the persistent-resource allowlist
  and must be included in the reviewed session-destroy plan.
- P7.3 adds an **opt-in only** Secrets Manager module. With both `rds_enabled=true` and
  `secrets_manager_enabled=true`, it stores one JSON `DATABASE_URL` field in a temporary
  encrypted secret and creates a separate `bedoux-api-secrets` IRSA role with only
  `secretsmanager:GetSecretValue` on that secret. The value is never synchronized into a
  Kubernetes Secret; the API, migration, and seed processes fetch it through the AWS SDK.
  The module is not on the persistent-resource allowlist and must be included in the reviewed
  session-destroy plan. See [`docs/runbooks/p7-3-secrets-manager-session.md`](../../docs/runbooks/p7-3-secrets-manager-session.md).
- P8.2 adds an **opt-in only** observability module. With `observability_enabled=true` and an
  exact, reviewed EKS CloudWatch Observability add-on version, it creates three temporary
  Container Insights log groups with exactly three-day retention, an IRSA-only CloudWatch agent
  role, two JSON-log metric filters, and a small dashboard. A second reviewed apply after the ALB
  exists enables four notification-free alarms. The module, including its CloudWatch resources and
  agent role, is not on the persistent-resource allowlist and the guarded destroy helper removes
  it with the session. See
  [`docs/runbooks/p8-2-cloudwatch-session.md`](../../docs/runbooks/p8-2-cloudwatch-session.md).

## P6.1 validation

From this directory:

```text
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -refresh=false -out=p6.1.tfplan
```

For credential-free local or GitHub Actions validation only, use
`terraform validate -var=skip_aws_credentials_validation=true`. Never pass that
override to a plan or apply against AWS.

The plan is a review artifact only. Do not run `terraform apply` until P6.2
opens an AWS session and the plan has been reviewed against the manual checklist
in `docs/runbooks/aws-session.md`.

## P6.2 state migration

After `bootstrap/` has created its bucket, retrieve the bucket name from the
bootstrap output at runtime and migrate both states with S3-native locking:

```text
terraform init -migrate-state \
  -backend-config="bucket=<bootstrap output>" \
  -backend-config="key=bedoux-commerce-cloud/session.tfstate" \
  -backend-config="region=ca-central-1" \
  -backend-config="profile=bedoux-admin" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
```

Use `key=bedoux-commerce-cloud/bootstrap.tfstate` for the bootstrap directory.
The actual bucket name is intentionally never written into a committed backend
configuration.
