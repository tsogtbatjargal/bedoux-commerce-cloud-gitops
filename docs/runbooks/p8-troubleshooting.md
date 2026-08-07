# P8 troubleshooting runbooks

Four playbooks, one per P8.3 drill (T-802), each written from the actual induce/diagnose/fix
sequence proven live on 2026-08-07 (see `docs/PROGRESS.md`'s session log for full evidence).
Every diagnostic step below uses only `kubectl`/`aws` output — no prior knowledge of the injected
cause is assumed. Use `bedoux-eks` as the kubeconfig context name (set by
`aws eks update-kubeconfig --profile bedoux-admin --region ca-central-1 --name bedoux --alias
bedoux-eks`) and `bedoux-admin` as the AWS CLI profile throughout.

## 1. Unhealthy ALB target

**Symptom:** the public site returns `503`, or `aws elbv2 describe-target-health` shows a target
that is not `healthy`.

**Diagnose:**

```text
kubectl -n bedoux get deployment web
kubectl -n bedoux get endpoints web
aws elbv2 describe-target-health --profile bedoux-admin --region ca-central-1 \
  --target-group-arn <web target group ARN> \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}'
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://<ALB DNS name>/"
```

Find the target group ARN with `aws elbv2 describe-target-groups --query
'TargetGroups[?contains(TargetGroupName, \`k8s-bedoux\`)].TargetGroupArn'`. A target in state
`draining` with reason `Target.DeregistrationInProgress` means the ALB controller has already
started removing a target whose backing pod is gone — check `kubectl get deployment` next. If the
Deployment shows `0/0` available and `kubectl get endpoints` returns none, the root cause is at
the Kubernetes layer (scaled to zero, or every pod failing readiness), not the ALB or AWS Load
Balancer Controller.

**Fix:** restore the Deployment's replica count (`kubectl -n bedoux scale deployment/web
--replicas=1`) or fix whatever is failing readiness. Confirm recovery by polling
`describe-target-health` until the state returns to `healthy`, then re-check the public URL
returns `200`. Recovery is normally visible within 15-30 seconds of the pod becoming Ready.

## 2. Failed pod (CrashLoopBackOff)

**Symptom:** `kubectl -n bedoux get pods` shows a pod with `STATUS` `CrashLoopBackOff` and a
climbing `RESTARTS` count, while the Deployment's other pod(s) — if any — may still be healthy.

**Diagnose:**

```text
kubectl -n bedoux get pods -l app=api
kubectl -n bedoux describe pod <crashing pod name>
kubectl -n bedoux logs <crashing pod name>          # add --previous if the container has already restarted
```

`describe pod`'s Events section shows `BackOff restarting failed container` once Kubernetes gives
up retrying immediately. The crashed container's own log is the fastest path to root cause —
in the drill this showed the exact injected failure text. Do not assume the cause from the pod's
`STATUS` alone; always read the actual container log before proposing a fix. If a rolling update
is in progress, `kubectl get pods` will show the previous-generation pod still `1/1 Running`
alongside the crashing new one — that is Kubernetes' rolling-update `maxUnavailable` default
protecting users, not a second problem.

**Fix:** if the bad state came from a manual `kubectl patch`/`kubectl set` change (as in the
drill), `kubectl -n bedoux rollout undo deployment/api` reverts to the prior working
ReplicaSet. If the bad state came from a real code/config change already on `main`, the fix is a
new commit and a fresh `helm upgrade` (see the "failed rollout" playbook below — the situations
are closely related). Confirm recovery: `kubectl get pods` shows `1/1 Running` with `0` recent
restarts, and `/api/health` returns `200`.

## 3. DB connection error

**Symptom:** API pods stay stuck at `Init:N/5` (the `wait-for-postgres` init container never
completes) and never reach `Running`; `/api/health` and `/api/products` time out or return
`502`/`504` through the ALB.

**Diagnose:**

The `wait-for-postgres` init container retries its connection silently by design (no log line on
each failed attempt), so a stuck `Init` phase alone does not say *why*. Get a direct, independent
read on the network path:

```text
kubectl -n bedoux get pods -l app=api
kubectl -n bedoux run db-debug --image=docker.io/library/postgres:16-alpine --restart=Never \
  --command -- sh -c "timeout 8 pg_isready -h <RDS endpoint> -p 5432; echo exit_code=\$?"
kubectl -n bedoux logs db-debug
kubectl -n bedoux delete pod db-debug
```

Get the RDS endpoint from `terraform -chdir=infra/terraform output -raw rds_address`. A `no
response` result with a non-zero exit code confirms the block is at the network layer, not the
application. Cross-check the actual AWS-side cause:

```text
rds_sg=$(aws rds describe-db-instances --profile bedoux-admin --region ca-central-1 \
  --db-instance-identifier bedoux-postgres --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)
aws ec2 describe-security-group-rules --profile bedoux-admin --region ca-central-1 \
  --filters "Name=group-id,Values=$rds_sg" --query 'SecurityGroupRules[?IsEgress==`false`]'
```

An empty or unexpected result here — no ingress rule allowing TCP 5432 from the EKS cluster
security group — is the concrete root cause. This is exactly the failure mode the drill induced
via `ec2:RevokeSecurityGroupIngress`, but the same diagnostic path applies to any accidental
security-group or network ACL change.

**Fix:** restore the missing rule, sourced from Terraform's own state so the restored value
matches exactly (no drift):

```text
eks_sg=$(aws eks describe-cluster --profile bedoux-admin --region ca-central-1 --name bedoux \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 authorize-security-group-ingress --profile bedoux-admin --region ca-central-1 \
  --group-id "$rds_sg" \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$eks_sg,Description=\"PostgreSQL from EKS workloads\"}]"
```

Before restoring by hand, confirm `$eks_sg` matches Terraform's `module.eks.aws_eks_cluster.this`
`vpc_config.cluster_security_group_id` (`terraform state show module.eks.aws_eks_cluster.this`)
so the fix doesn't diverge from what the next `terraform plan` expects. If the affected pod is
already stuck, no restart is needed — the init container's own retry loop will succeed on its
next attempt once the rule is restored. Confirm recovery: the pod progresses `Init:N/5` → `5/5` →
`Running` → `1/1 Ready`, and `/api/health` returns `200`.

## 4. Failed rollout

**Symptom:** `helm upgrade` returns a non-zero exit and an `UPGRADE FAILED` message; the public
site may show no impact at all if the previous release was still serving.

**Diagnose:**

```text
kubectl -n bedoux get pods -l app=web
kubectl -n bedoux describe pod <new, non-ready pod>
helm -n bedoux history bedoux
```

`describe pod` on the new pod is the fastest signal — in the drill it showed `ErrImagePull` →
`ImagePullBackOff` with the exact missing-tag error from containerd. Other common causes surface
the same way: a bad readiness probe path, a missing ConfigMap/Secret key, or insufficient node
resources all show up as a specific Warning event on the new pod, not a generic timeout. Check
whether the previous-revision pod is still `1/1 Running` — if so, users saw no downtime during
the failed rollout, which is exactly what `--atomic --wait` is for.

**Fix:** if the deploy workflow used `--atomic` (every `deploy-learning.yml` invocation does),
Helm rolls the release back automatically once its `--timeout` is reached — no manual action is
needed. Confirm this happened:

```text
helm -n bedoux history bedoux
```

A `failed` revision immediately followed by a `Rollback to N` revision marked `deployed` confirms
the automatic recovery. If a release was applied without `--atomic` (never do this against the
learning session; only ever use the documented `deploy-learning.yml` path or the exact command in
[`p6-4-ci-deploy.md`](p6-4-ci-deploy.md)), recover manually with `helm -n bedoux rollback bedoux
<last known-good revision>`. Confirm recovery: the previous-revision pod (or the rolled-back
release's pod) is `1/1 Running`, and both `/api/health` and `/` return `200`.
