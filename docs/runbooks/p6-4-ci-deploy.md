# P6.4 CI deployment session

Use this runbook only after every **Before the session** item in
[`aws-session.md`](aws-session.md) is complete, the reviewed Terraform plan has no NAT Gateway,
and a same-day teardown time is set. It deploys only to the short-lived P6 learning cluster.

## Session setup by the human operator

1. Import the existing allowlisted resources, then apply the reviewed Terraform plan. On the
   first P6.4 session, `scripts/terraform-persistent-state.sh import --execute` reports that the
   GitHub OIDC resources are absent; that is expected, because this apply creates them.

2. Configure the operator's kubeconfig and create the namespace that CI is intentionally not
   allowed to create:

   ```text
   aws eks update-kubeconfig --profile bedoux-admin --region ca-central-1 --name bedoux
   kubectl apply -f k8s/00-namespace.yaml
   ```

3. Bootstrap the AWS-profile `gp3` StorageClass as the operator, before dispatching CI. A
   StorageClass is cluster-scoped, while the GitHub deployment role intentionally has edit access
   only in namespace `bedoux`. Render just this chart resource with the same AWS values that CI
   uses, then apply and verify it. CI explicitly sets `storageClass.create=false`, so it never
   needs cluster-wide Kubernetes permissions.

   ```text
   helm template bedoux charts/bedoux \
     -f charts/bedoux/values.yaml \
     -f charts/bedoux/values-aws.yaml \
     --show-only templates/storageclass.yaml | kubectl apply -f -
   kubectl get storageclass gp3
   ```

4. Install the AWS Load Balancer Controller as the operator. This remains an operator step
   because the CI role has access only to the `bedoux` namespace. Use the existing Terraform-
   managed IRSA role and do not record its ARN in source control. Pin chart/controller version
   `3.4.3` (selected from the official EKS chart repository on 2026-07-31) and pass the VPC ID
   explicitly: in this public-only learning profile, the controller's instance-metadata VPC
   discovery timed out during the first P6.4 install.

   ```text
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   controller_role_arn="$(aws iam get-role --profile bedoux-admin \
     --role-name bedoux-alb-controller-role --query 'Role.Arn' --output text)"
   vpc_id="$(terraform -chdir=infra/terraform output -raw vpc_id)"
   helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
     --namespace kube-system \
     --version 3.4.3 \
     --set clusterName=bedoux \
     --set region=ca-central-1 \
     --set vpcId="$vpc_id" \
     --set serviceAccount.create=true \
     --set serviceAccount.name=aws-load-balancer-controller \
     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$controller_role_arn"
   kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=5m
   unset controller_role_arn
   unset vpc_id
   ```

5. Set the GitHub Actions repository variable from Terraform's runtime output. It is a role ARN,
   not a secret; never hardcode it or the AWS account number in a workflow or committed document.

   ```text
   github_actions_role_arn="$(terraform -chdir=infra/terraform output -raw github_actions_role_arn)"
   gh variable set AWS_DEPLOY_ROLE_ARN --repo bedoux-tech/bedoux-commerce-cloud \
     --body "$github_actions_role_arn"
   unset github_actions_role_arn
   ```

## Run and assess the deployment workflow

The workflow file must already be merged into `main`: the OIDC trust policy accepts only `main`.
In GitHub Actions, select **Deploy learning session**, choose the `main` branch, and set
`seed_catalog=true` only for a new in-cluster PostgreSQL volume. The workflow:

1. exchanges GitHub's OIDC token for the branch-bound, short-lived deployment role;
2. builds and pushes API/web images tagged with the immutable commit SHA;
3. deploys the AWS Helm profile with ordering still disabled;
4. waits for the workloads and ALB; and
5. verifies public `/api/health` and a non-empty catalog.

The Helm command uses `--atomic`: an ordinary failed install or upgrade is rolled back before the
workflow returns failure. This is a safety property, not P6.5 evidence; P6.5 owns the deliberate
failed-release and CI rollback drill.

## P6.5 CI rollback drill

First dispatch a normal successful run from `main` (with `seed_catalog=true` only when the
session's PostgreSQL volume is new). Do not run the drill against an absent release.

Then dispatch **Deploy learning session** again from the same `main` commit with
`rollback_drill=true` and `seed_catalog=false`. The workflow first captures the web Deployment's
actual pre-drill image. It still builds and pushes its immutable images when absent; on a repeat
dispatch it deliberately reuses existing commit-tagged images. It then passes a unique,
deliberately unavailable **web** image tag to Helm. The valid API image lets the pre-upgrade
migration hook finish; the web Deployment then fails to roll out. The drill uses a three-minute
wait and Helm `--atomic`, which must restore that captured pre-drill image.

The workflow is expected to finish **failed from its Helm step**. Its conditional evidence step
must nevertheless run and show the Helm history/status, current workloads, the restored web image
matching the commit SHA, and a passing public health check. Record the run URL/ID, the
failed-revision and deployed-revision statuses, and that public health remained good in
`docs/PROGRESS.md` as T-602 evidence. If the normal release is not restored, stop and diagnose;
do not retry the drill or continue to teardown until the release is healthy.

## Session teardown

Do not leave the workflow's ALB or cluster running. Delete the `bedoux` Ingress and wait for its
ALB to disappear, then remove the release, namespace, and controller. Keep persistent state
attached while planning and applying the temporary-only Terraform destruction:

```text
scripts/terraform-session-destroy.sh prepare
scripts/terraform-session-destroy.sh prepare --execute
scripts/terraform-session-destroy.sh plan
scripts/terraform-session-destroy.sh apply --execute
```

The state-only `prepare` dry run must be reviewed before `prepare --execute`; the latter detaches
the persistent allowlist and cluster OIDC-provider state before the targeted plan is built. The
helper then targets EKS, RDS, its add-on/access entries, and the VPC only, and deletes the captured
cluster OIDC provider explicitly after the cluster is gone. Do not target
`module.workload_iam`: its cluster OIDC provider is a dependency of persistent IRSA roles, and a
targeted destroy can otherwise delete those roles. Complete every **Teardown** item in
[`aws-session.md`](aws-session.md) and record the clean inventory in `docs/PROGRESS.md`.
