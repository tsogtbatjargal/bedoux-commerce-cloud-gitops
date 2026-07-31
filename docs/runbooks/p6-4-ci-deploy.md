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

3. Install the AWS Load Balancer Controller as the operator. This remains an operator step
   because the CI role has access only to the `bedoux` namespace. Use the existing Terraform-
   managed IRSA role and do not record its ARN in source control:

   ```text
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   controller_role_arn="$(aws iam get-role --profile bedoux-admin \
     --role-name bedoux-alb-controller-role --query 'Role.Arn' --output text)"
   helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
     --namespace kube-system \
     --set clusterName=bedoux \
     --set region=ca-central-1 \
     --set serviceAccount.create=true \
     --set serviceAccount.name=aws-load-balancer-controller \
     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$controller_role_arn"
   kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=5m
   unset controller_role_arn
   ```

4. Set the GitHub Actions repository variable from Terraform's runtime output. It is a role ARN,
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

## Session teardown

Do not leave the workflow's ALB or cluster running. Delete the `bedoux` Ingress and wait for its
ALB to disappear, remove the release and namespace, detach persistent Terraform resources, then
destroy the session infrastructure. Complete every **Teardown** item in
[`aws-session.md`](aws-session.md) and record the clean inventory in `docs/PROGRESS.md`.
