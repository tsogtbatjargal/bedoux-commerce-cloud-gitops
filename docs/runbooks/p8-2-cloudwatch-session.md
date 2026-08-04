# P8.2 CloudWatch observability session

Use this runbook only after manually completing every **Before the session** item in
[aws-session.md](aws-session.md), confirming current actual and forecast spend remain below the
USD 16 stop threshold, setting an independently alarmed same-day teardown deadline, and reviewing
the plan. There is no Codex `/aws-session-start` command: manually walk that checklist before any
AWS mutation and manually complete its teardown sweep before the session ends.

This is a short, evidence-focused session. It enables the AWS-supported EKS CloudWatch
Observability add-on through one IRSA role restricted to
`system:serviceaccount:amazon-cloudwatch:cloudwatch-agent`. It deliberately does **not** enable
Application Signals or tracing. Container Insights metrics and the three container log groups are
temporary; all groups have three-day retention and are removed in the same-day Terraform destroy.

## Prepare non-committed inputs

1. Create a fresh RDS password using the established P7 procedure. Keep it only in the current
   shell as `TF_VAR_rds_master_password`; do not reuse a previous session password, print it,
   write it to a tfvars file, or place it in shell history.
2. Select the exact add-on version that EKS reports as the default compatible version for this
   cluster's pinned Kubernetes minor. This is read-only and the value is not secret:

   ```text
   aws eks describe-addon-versions --profile bedoux-admin --region ca-central-1 \
     --addon-name amazon-cloudwatch-observability --kubernetes-version 1.34 \
     --query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion | [0]' \
     --output text
   export TF_VAR_cloudwatch_observability_addon_version='<reviewed exact version>'
   ```

   Record the selected version in the session evidence, never as an unpinned `latest` choice.
3. Keep the initial apply free of alarms that need a dynamically-created ALB:

   ```text
   export TF_VAR_rds_enabled=true
   export TF_VAR_secrets_manager_enabled=true
   export TF_VAR_observability_enabled=true
   export TF_VAR_observability_alarms_enabled=false
   ```

## Apply the reviewed infrastructure

1. Import the persistent allowlist with `scripts/terraform-persistent-state.sh import --execute`.
2. Plan with the four exported session inputs. Confirm it contains the no-NAT EKS profile, one
   short-lived Single-AZ RDS instance, the P7 Secrets Manager identity, and only these P8 resources:
   - three `/aws/containerinsights/bedoux/{application,dataplane,host}` log groups at exactly three
     days retention;
   - one `bedoux-cloudwatch-observability-role` whose OIDC trust has only the CloudWatch agent
     service-account subject, with AWS's documented `CloudWatchAgentServerPolicy` attachment;
   - the exact `amazon-cloudwatch-observability` add-on version;
   - two application-log metric filters and the `bedoux-learning-observability` dashboard.
3. Refuse the plan if it contains a NAT Gateway, a node-role telemetry policy, Application Signals,
   an unreviewed service, log retention above three days, or a resource that cannot be explained.
4. Apply that saved plan. Verify the add-on reaches `ACTIVE`, the CloudWatch agent pods are
   `Running` in `amazon-cloudwatch`, and each expected log group has retention `3`. Do not print
   IAM role ARNs, RDS endpoints, or credentials.

## Deploy data and add alarms

1. Complete the namespace, `gp3` StorageClass, ALB-controller, and GitHub deployment-role setup
   in [p6-4-ci-deploy.md](p6-4-ci-deploy.md). Bootstrap the temporary
   `bedoux-api-secrets` ServiceAccount exactly as described in
   [p7-3-secrets-manager-session.md](p7-3-secrets-manager-session.md).
2. Dispatch **Deploy learning session** from `main` with `use_rds=true`,
   `use_secrets_manager=true`, `use_s3_images=false`, and `seed_catalog=true`. Keep ordering off.
   Record only the successful migration/seed/rollout and public health/catalog evidence.
3. Generate a few normal health and catalog requests. Wait for JSON API completion records to
   appear in the application log group and for Container Insights metrics to arrive. AWS documents
   a short propagation delay; do not create synthetic high traffic to compensate.
4. Discover only the ALB ARN suffix, then make and review a second plan:

   ```text
   export TF_VAR_observability_alb_arn_suffix="$(scripts/discover-alb-arn-suffix.sh)"
   export TF_VAR_observability_alarms_enabled=true
   terraform -chdir=infra/terraform plan -out=/tmp/bedoux-p8-alarms.tfplan
   ```

   The second plan must add only four notification-free alarms: structured-log API 5xx rate,
   ALB unhealthy targets, Bedoux namespace pod restarts, and RDS CPU utilization. Apply only that
   reviewed plan. `scripts/discover-alb-arn-suffix.sh` writes no files and prints no full ARN,
   account ID, or DNS name.
5. Capture the populated dashboard and normal `OK` state. T-801 also needs one alarm to fire and
   recover; P8.3 owns that controlled drill evidence. Do not force an alarm by widening access or
   adding unbounded load.

## Teardown

Delete the Ingress and wait for the ALB to disappear, then remove the Helm release, namespace,
ALB controller, and temporary P7 service account. Use the guarded destroy sequence:

```text
scripts/terraform-session-destroy.sh prepare
scripts/terraform-session-destroy.sh prepare --execute
scripts/terraform-session-destroy.sh plan
scripts/terraform-session-destroy.sh apply --execute
```

The destroy helper detects an observability module in state and includes it. Review the saved plan:
it must delete the CloudWatch add-on, CloudWatch agent IRSA role, three log groups, two metric
filters, dashboard, alarms, RDS/Secrets Manager session resources, EKS/VPC resources, and no
persistent ECR or IAM address. Complete every **Teardown** item in
[aws-session.md](aws-session.md), including a read-only inventory of CloudWatch log groups,
dashboards, alarms, add-ons, ALBs, target groups, RDS remnants, NAT Gateways, EIPs, EBS
volumes/snapshots, and CloudFormation stacks. Unset the password and all `TF_VAR_*` values and
delete the saved `/tmp` plans after the sweep.
