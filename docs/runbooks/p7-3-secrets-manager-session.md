# P7.3 Secrets Manager learning session

Use this runbook only after manually completing every **Before the session** item in
[aws-session.md](aws-session.md), confirming current spend remains below the USD 16 stop
threshold, setting an independently alarmed same-day teardown deadline, and reviewing the
Terraform plan. This is a short-lived Secrets Manager and IRSA exercise, not a persistent
database credential deployment.

## Apply the reviewed infrastructure

1. Keep the RDS master password out of source control, shell history, terminal output, and
   progress evidence. Supply it only in the current shell as `TF_VAR_rds_master_password`.
2. Plan with both `rds_enabled=true` and `secrets_manager_enabled=true`. Review the plan for:
   - the existing no-NAT EKS/VPC learning profile;
   - one private Single-AZ RDS instance and its subnet/security-group resources;
   - one encrypted Secrets Manager secret named from the reviewed `bedoux-*` value;
   - one `bedoux-*` IRSA role and one `secretsmanager:GetSecretValue` policy scoped to that
     exact secret ARN;
   - no `aws_nat_gateway`, public secret policy, or unrelated service.
3. Apply only that reviewed plan. The secret, version, role, and policy are temporary session
   resources and are not persistent-resource exceptions.

The secret JSON contains one `DATABASE_URL` field assembled from the RDS endpoint and the
out-of-band password. Terraform state is encrypted in the persistent state bucket, and the
workload fetches the value through the AWS SDK. Do not print the secret, URL, endpoint, or role
ARN.

## Bootstrap the Secrets Manager workload identity

After Terraform applies, create only the ServiceAccount needed by this profile. It is not a
credential store and carries no secret data:

```text
secret_role_arn="$(terraform -chdir=infra/terraform output -raw database_secrets_api_role_arn)"

kubectl -n bedoux create serviceaccount bedoux-api-secrets
kubectl -n bedoux annotate serviceaccount bedoux-api-secrets \
  eks.amazonaws.com/role-arn="$secret_role_arn"

unset secret_role_arn
```

The trust policy must match only `system:serviceaccount:bedoux:bedoux-api-secrets`. The role
policy must grant only `secretsmanager:GetSecretValue` on the session secret. The API, migration
hook, and seed hook use this same ServiceAccount. Do not create `rds-credentials` as a
Kubernetes Secret in this profile.

## Deploy and prove P7.3

1. Complete the standard namespace, `gp3` StorageClass, ALB-controller, and GitHub deployment-role
   setup from [p6-4-ci-deploy.md](p6-4-ci-deploy.md).
2. Confirm the namespace has `bedoux-api-secrets` and does **not** have the P7.1
   `rds-credentials` Secret.
3. Dispatch **Deploy learning session** from `main` with `use_rds=true`,
   `use_secrets_manager=true`, and `seed_catalog=true`. Keep `use_s3_images=false` for this
   focused identity proof; P7.2 uses a separate API role and is already complete.
4. Record evidence without sensitive values: migration hook completed, seed completed, API/web
   readiness passed, catalog returned six products, and `/api/health` passed through the ALB.
5. Inspect the API Pod's ServiceAccount and role annotation. If a direct identity assertion is
   needed, print only a fixed success sentence after checking the expected role suffix; never
   print the caller ARN, account ID, token, secret name plus value, or database URL.

## Teardown

Delete the Ingress and wait for its ALB to disappear, then remove the Helm release and namespace.
Delete `bedoux-api-secrets` if it remains, and run the guarded sequence:

Keep the same out-of-band password available only in the current shell as
`TF_VAR_rds_master_password` while the destroy plan is generated; the configuration must still
validate the enabled RDS/Secrets Manager inputs. Do not print or persist it.

```text
scripts/terraform-session-destroy.sh prepare
scripts/terraform-session-destroy.sh prepare --execute
scripts/terraform-session-destroy.sh plan
# Review the saved plan: it must include the RDS and Secrets Manager modules, no persistent
# addresses, and no NAT Gateway.
scripts/terraform-session-destroy.sh apply --execute
```

Complete every teardown check in [aws-session.md](aws-session.md), including RDS instances,
manual snapshots, automated-backup leftovers, subnet groups, Secrets Manager secrets, IAM role
and policy, ALBs, target groups, NAT gateways, EIPs, EBS volumes/snapshots, and CloudFormation
stacks. Confirm only the persistent-resource allowlist remains. Delete temporary plans, logs,
password variables, and any local secret material before closeout.
