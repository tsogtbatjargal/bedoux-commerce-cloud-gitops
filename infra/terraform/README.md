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
- `bedoux-iam-scoped` and the EKS node-group service-linked role are account
  foundations from P4/P5 and are deliberately not managed here.
- P6.2 must import the persistent P5 ECR repositories and IAM roles before an
  apply, rather than attempting to create duplicate names. Before `destroy`, run
  `scripts/terraform-persistent-state.sh detach --execute` so Terraform removes
  only session resources while those allowlisted resources remain.
- `bootstrap/` owns the persistent, versioned, encrypted Terraform state bucket.
  It is intentionally never part of the session-environment destroy.
- EBS CSI is pinned to `v1.63.0-eksbuild.1`, verified compatible and default for
  EKS `1.33` in `ca-central-1` on 2026-07-29.

## P6.1 validation

From this directory:

```text
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -refresh=false -out=p6.1.tfplan
```

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
