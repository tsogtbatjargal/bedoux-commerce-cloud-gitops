# ADR 0023: Controller-native weighted canary extends the existing Helm deployment path

- Status: Proposed
- Date: 2026-08-27

## Context

P13 requires a candidate to run beside the current release, receive a small percentage of real
traffic, pass an automated health/error gate, and only then become the 100% release. The existing
delivery path is a manually dispatched, push-based GitHub Actions workflow that verifies signed
immutable images and runs one Helm release with `--atomic`. P13 must extend that path rather than
add a second GitOps controller or another independently managed release.

The AWS and kind request paths intentionally differ because of ADR 0008. AWS uses one ALB rule to
the web Service, whose nginx proxies `/api`; kind uses ingress-nginx with separate web and rewritten
API paths. Both installed controllers already support weighted routing to Kubernetes Services.

## Decision

Keep `api` and `web` as the stable Deployments and add opt-in `api-canary` and `web-canary`
Deployments plus matching Services inside the same Helm release. The canary web pod points only to
`api-canary`, so one routed web request cannot silently cross back to the stable API.

When canary mode is enabled:

- the AWS ALB Ingress uses one advanced forward action with stable/canary target-group weights;
- the kind ingress-nginx profile emits one canary Ingress for each existing stable path;
- the initial weight is fixed by the workflow at 10%; and
- the candidate migration image runs before the staged resources, preserving ADR 0005's
  schema-before-code ordering. Migrations remain forward/backward compatible because rollback never
  runs a database downgrade.

The existing GitHub workflow remains the only AWS deployment entry point. Its canary option must
refuse a missing baseline release and must preserve the exact immutable images currently running as
the stable side. Before staging on AWS, it applies those same stable images through the permanent
stable-only action backend and requires the listener plus stable target health to reconcile. It then
stages the verified candidate at 10%, runs a direct canary gate against the
canary web-to-API path, and independently verifies that the ALB has reconciled the exact listener
rule and that every registered target in both controller-owned target groups is healthy. A bounded
public sample must have zero errors and at least one request correlated in the `web-canary` access
log, proving the declared split carried real listener traffic. Only then may it promote by setting
the stable Deployments to the candidate while changing the split to 100/0.

The gate checks the exact expected canary images, Ready/available state, rendered traffic weight,
health response, catalog response, and a bounded request sample with zero allowed errors. On AWS it
also maps the stable and canary Services through their `TargetGroupBinding` objects, discovers the
active ALB without printing its ARN, polls `DescribeRules` for the exact 90/10 target-group ARN
mapping, and polls `DescribeTargetHealth` until both non-empty groups are fully healthy. The GitHub
OIDC role receives only the four ELBv2 read actions needed for this proof; ELB Describe APIs require
`Resource: *`. Because `AmazonEKSEditPolicy` does not include controller custom resources, the EKS
access entry also joins one dedicated Kubernetes group whose session-bootstrapped, namespace-scoped
Role grants only `get/list` on `targetgroupbindings.elbv2.k8s.aws`.

The AWS session labels the application namespace
`elbv2.k8s.aws/pod-readiness-gate-inject=enabled` before the baseline. Because the controller injects
target-health readiness gates only when a pod is created after its IP-mode Service and
`TargetGroupBinding` exist, the baseline web Deployment is restarted once after the initial binding
appears when necessary. The rollout refuses unless every active stable web pod actually contains a
`target-health.elbv2.k8s.aws/*` gate whose condition is `True`; the label alone is not evidence.
This makes Kubernetes rollout readiness include ALB target readiness when promotion replaces the
stable web pod.

A failure before promotion automatically restores the captured stable images while retaining the
canary at 0%, requires the same promotion-state reconciliation and drain hold, and only then disables
the canary. If reconciliation cannot prove 100/0, cleanup is blocked and the canary resources remain
for diagnosis. Helm `--atomic` remains active for every revision. The AWS Ingress preserves backend service name
`web` and uses matching annotation `actions.web`: stable mode is one `web` target at 100%, canary
mode adds `web-canary`, and cleanup returns to stable-only. The normalization step privately
compares the stable `TargetGroupBinding` ARN before and after applying the action and blocks if the
controller replaced it. This avoids the documented connection-dropping service-name change and
never changes back to a direct Service during cleanup. Cleanup is complete only after the canary
Deployments, Services, ConfigMap, Ingresses, and canary `TargetGroupBinding` are absent, the
listener rule is stable-only, and the remaining stable target group is fully healthy.

After applying the candidate to stable at 100/0, the workflow does not start its 45-second drain
timer from Kubernetes rollout status. It first reasserts the stable web pod's injected target-health
condition, requires both stable and canary `TargetGroupBinding` objects to remain present, polls the
listener for the exact stable/canary 100/0 mapping, and requires the stable target group to be fully
healthy. A listener still at 90/10 therefore blocks drain and cleanup. Only a passing promotion-state
gate starts the timer; cleanup then removes the zero-weight canary resources and proves the separate
stable-only state.

P13.2 may add a narrowly scoped regression injection to exercise this already-declared abort path;
it must not introduce a different rollback mechanism.

## Consequences

- Progressive delivery stays in one workflow, one chart, and one Helm release.
- A successful kind rollout creates three auditable Helm revisions: stage, 100/0 promotion, and
  cleanup. The first AWS adoption adds one stable-only action-normalization revision before those
  three so the direct-Service-to-action transition occurs and recovers before any candidate is
  staged.
- The 10% split is probabilistic for user traffic. The gate combines deterministic direct-canary
  health with exact ALB configuration/target reconciliation and a bounded 100-request public sample
  that must include a correlated canary access-log hit.
- Canary capacity is bounded to one API pod and one web pod. It adds no autoscaler or second
  database.
- ALB canary mode temporarily creates one additional target group, so live proof still requires an
  alarmed AWS session and same-session teardown.
- The stable ALB target group and action backend persist across stage, promotion, and cleanup;
  only the temporary canary target group is removed.
- Acceptance of this ADR permits the live T-1301 plan review; it does not authorize AWS apply or
  dispatch by itself.

## References

- AWS Load Balancer Controller weighted forward actions:
  <https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/use_cases/blue_green/>
- AWS Load Balancer Controller pod readiness gates:
  <https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/>
- Amazon EKS access-policy permissions:
  <https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html>
- ingress-nginx canary annotations:
  <https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#canary>
