# Bedoux learning infrastructure

This is the P6 Terraform definition of the P5 learning environment. The root
configuration intentionally uses a local backend during P6.1 so a cold plan does
not require a state bucket or create any AWS resource.

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
  apply, rather than attempting to create duplicate names.
- The EBS CSI add-on version is left as an explicit input because AWS publishes
  compatible versions per Kubernetes minor version. P6.2 must query the pinned
  EKS version, select a compatible exact version, and record it before apply.

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

