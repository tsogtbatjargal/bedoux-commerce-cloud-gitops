# P7.1 RDS learning session

Use this runbook only after manually completing every **Before the session** item in
[aws-session.md](aws-session.md), setting a same-day teardown deadline, and reviewing current
regional RDS pricing. This is a short-lived Single-AZ learning exercise, not a production RDS
configuration.

## Apply the reviewed infrastructure

1. Keep the master password out of source control, shell history, terminal output, and progress
   evidence. Supply it only in the current shell as `TF_VAR_rds_master_password`; never put it in
   `terraform.tfvars`.
2. Create and inspect a plan that explicitly enables RDS. Confirm it has no NAT Gateway and only
   the expected RDS instance, subnet group, and security group in addition to session EKS
   infrastructure. Confirm the instance is Single-AZ, private, encrypted, fixed-size gp3, has no
   final snapshot, and accepts PostgreSQL only from the EKS cluster security group.
3. Apply only the reviewed plan. Do not leave the instance running beyond the session deadline.

## Bootstrap the namespace credential

P7.1 deliberately uses a one-session Kubernetes Secret because Secrets Manager is owned by P7.3.
After Terraform has created RDS, create `rds-credentials` in the `bedoux` namespace with one
`DATABASE_URL` key using the private Terraform `rds_address` output and the out-of-band password.
Do not commit, echo, screenshot, or record the URL. Delete the namespace during teardown; P7.3
will replace this bootstrap mechanism with Secrets Manager.

## Deploy and verify

1. Complete the standard namespace, StorageClass, ALB-controller, and GitHub deployment-role
   setup from [p6-4-ci-deploy.md](p6-4-ci-deploy.md).
2. Dispatch **Deploy learning session** from `main` with `use_rds=true` and `seed_catalog=true`
   for a fresh RDS database. The workflow refuses to proceed unless `rds-credentials` exists.
3. Record T-701 evidence: migration hook completion, API/web readiness, a non-empty catalog, and
   one order flow backed by RDS. Do not record credentials or the private endpoint.

## Teardown

Delete the Helm release and namespace first, then follow the explicit prepare/plan/apply sequence
in [p6-4-ci-deploy.md](p6-4-ci-deploy.md). The session-destroy helper targets `module.rds` with
the temporary EKS/VPC modules. Complete every teardown check in [aws-session.md](aws-session.md),
including RDS instances, snapshots, and subnet groups. `skip_final_snapshot=true` and zero backup
retention are deliberate learning-profile settings, but verify deletion rather than assuming it.
