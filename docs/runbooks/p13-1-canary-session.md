# P13.1 canary-promotion session

Use this runbook for P13.1's local proof and later T-1301 AWS proof. ADR 0023 keeps the canary in
the existing chart, Helm release, and manually dispatched deployment workflow. This runbook does
not authorize P13.2's regression injection.

## Local-first proof

This is a local Kubernetes drill under [`aws-session.md`](aws-session.md); it does not open an AWS
session and must be recorded as `AWS: none`.

1. Confirm the explicit kind context is Ready. Never use the default context, which may still
   point at a deleted EKS endpoint.
2. Prove the stable release is healthy through the kind Ingress and record the exact stable API
   and web images.
3. Build and load distinct local candidate tags using the pinned Dockerfiles and the documented
   Podman archive workaround.
4. Review the rollout dry-run, then execute it:

   ```text
   scripts/p13-canary-rollout.sh \
     --context kind-bedoux \
     --stable-api-image <exact-running-api-image> \
     --stable-web-image <exact-running-web-image> \
     --candidate-api-image localhost/bedoux-api:p13-candidate \
     --candidate-web-image localhost/bedoux-web:p13-candidate \
     --values charts/bedoux/values.yaml \
     --values charts/bedoux/values-kind-hpa.yaml \
     --helm-set networkPolicy.enabled=true \
     --weight 10 \
     --attempts 20 \
     --max-errors 0 \
     --dry-run
   # Replace only --dry-run with --execute after the baseline and images pass.
   ```

5. Record the 90/10 rendered split, exact canary images, `CANARY_GATE` sample, 100/0 promotion,
   final candidate images on stable Deployments, retained HPAs/NetworkPolicies, and absence of
   canary Deployments, Services, ConfigMap, and Ingresses after cleanup.
6. Re-run public health/catalog checks and remove only drill-specific images or files. Preserve
   unrelated local containers and data.

The host's normal `fs.inotify.max_user_instances` value is 128. If the already-documented kind
limit is encountered, the owner may temporarily set it to 1024 for the drill; restore 128 after
the local cluster is stopped or proven stable.

## Before the AWS session

Complete every **Before the session** item in [`aws-session.md`](aws-session.md). In addition:

- ADR 0023 must be accepted by the owner.
- Set an independent four-hour Edmonton alarm; reserve at least 75 minutes for ordered teardown.
- Recheck current EKS, ALB, and Spot pricing and the USD 20 budget. Stop if projected monthly cost
  exceeds USD 16 or the session estimate exceeds USD 4.
- Review the exact no-NAT Terraform plan and obtain owner approval of its saved-plan SHA-256 before
  apply. The plan must include the reviewed read-only ELBv2 additions to
  `bedoux-github-actions-policy` (`DescribeLoadBalancers`, `DescribeListeners`, `DescribeRules`,
  and `DescribeTargetHealth`) and no ELB mutation permission. No Route 53 alias is required for
  T-1301; the ALB DNS name is sufficient.
- The persistent allowlist is still detached after P12. Import it through the guarded helper before
  planning, exactly as the AWS session runbook requires.
- PR validation must be green. Do not merge the P13 implementation until the baseline step below
  has successfully deployed the preceding `main` revision; this gives the canary a genuine older
  signed release to run beside.

## Baseline, merge, and canary dispatch

1. Create the bounded temporary EKS/VPC session and bootstrap `gp3` and the pinned AWS Load
   Balancer Controller using [`p6-4-ci-deploy.md`](p6-4-ci-deploy.md). Apply
   `k8s/00-namespace.yaml` before the baseline; its
   `elbv2.k8s.aws/pod-readiness-gate-inject=enabled` label enables target-health readiness gates
   for this IP-target namespace. As the cluster-admin session operator, apply
   `k8s/ci-targetgroupbinding-reader.yaml`; it binds the GitHub access entry's dedicated group to
   namespace-scoped `get/list` on only `targetgroupbindings.elbv2.k8s.aws`. Do not grant CI EKS
   admin access.
2. While the preceding P12 revision is still `main`, dispatch **Deploy learning session** with
   `seed_catalog=true` and every other option, including `canary_rollout`, false. Record the green
   run and exact immutable API/web images. Prove ALB health and a non-empty catalog. Wait for the
   stable `web` `TargetGroupBinding`. Because readiness gates are injected only at pod creation
   after the matching Service/binding exists, restart `deployment/web` once if its initial pods
   have no `target-health.elbv2.k8s.aws/*` gate, then wait for rollout and run:

   ```text
   scripts/p13-alb-pod-readiness-gate.sh \
     --context bedoux \
     --namespace bedoux \
     --execute
   ```

   Do not merge or dispatch the canary until this reports every active stable web pod target-ready.
3. Only after that baseline is healthy, obtain the owner's explicit PR merge approval. Merge the
   unchanged, green P13 branch to `main` and verify the exact merge SHA.
4. Dispatch the new `main` workflow with `seed_catalog=false`, `canary_rollout=true`, and all
   unrelated drill/service options false. The workflow must:

   - capture the exact signed baseline images;
   - fail unless `kubectl auth can-i` confirms the CI identity can `get/list` the namespaced
     target-group bindings through that narrow Role;
   - apply those unchanged stable images through the permanent stable-only action backend and
     require its listener rule plus target health to reconcile before staging any candidate;
   - stage one candidate API/web pair at 10%;
   - map stable/canary Services through their `TargetGroupBinding` objects, then wait for the
     active ALB listener rule to contain the exact 90/10 target-group ARN mapping and for every
     registered target in both non-empty groups to report `healthy`;
   - print a passing 20-request, zero-error `CANARY_GATE` result;
   - send 100 bounded public ALB health requests at 90/10 with zero errors and prove at least one
     request reached `web-canary` through a unique access-log correlation marker;
   - promote the verified candidate through a 100/0 split;
   - require every active replacement stable web pod's injected ALB target-health condition to be
     `True`, both target-group bindings to remain present, the listener to reconcile exact 100/0,
     and the stable target group to be fully healthy before starting the drain timer;
   - remove zero-weight canary resources after the bounded drain hold, retain the same ALB action
     backend with only stable `web` at 100%, and wait for the stable-only listener/health state;
   - pass the existing public ALB health/catalog smoke.

5. Record Helm history, sanitized `ALB_RECONCILIATION_GATE`, `ALB_POD_READINESS_GATE`,
   `PUBLIC_CANARY_GATE`, and Kubernetes output showing stable-only action normalization, stage,
   promotion, cleanup, final stable candidate images, no canary Deployments/Services/Ingresses, no
   canary `TargetGroupBinding`, and the stable-only action. Explicitly verify the stable target
   group was retained throughout the transition and public requests remained healthy. This is
   T-1301 evidence only.

Stop immediately if the baseline is absent, a running image is not digest-pinned, stable web pods
lack a healthy injected ALB readiness gate, the staged weight differs from 10%, the listener rule
is not reconciled, either staged target group is empty or has a non-healthy target, the gate or
public sample reports any error, no public request is correlated to `web-canary`, promotion begins
before the staged gate passes, the exact 100/0 listener/stable-health state is absent before drain,
cleanup changes away from the named action backend, or the public smoke fails. For a pre-promotion
failure, the helper restores the captured stable images through reconciled 100/0 plus the drain hold
before disabling canary. If that reconciliation fails, it preserves canary resources for diagnosis
instead of cleaning them up. Diagnose and recover before teardown; do not begin P13.2.

## Teardown

Delete the Ingress first and wait for all ALB target groups and the ALB to disappear. Then remove
the Helm release, namespace/PVC, controller, and `gp3` StorageClass. Use the guarded persistent-
state preparation and exact saved-plan destroy flow, delete the captured temporary cluster OIDC
provider, and complete every teardown inventory check in [`aws-session.md`](aws-session.md).

The final inventory may contain only the approved persistent state bucket, ECR repositories, IAM
roles/policies, GitHub OIDC provider, and `bedoux.ca` Route 53/ACM validation set. Website aliases,
ALB/target groups, EKS/VPC resources, EBS volumes, and temporary cluster OIDC must all be absent.
