# P13.2 blocked-canary session

Use this runbook for P13.2's local proof and later T-1302 AWS proof. ADR 0023 already declares
the automatic pre-promotion abort path; this drill adds only a narrow canary error injection and
must not introduce a second release or rollback mechanism.

## Expected regression contract

`canary.regressionMode=http-error` changes only `web-canary`'s API upstream to a deliberately
absent API route. Its root page and readiness probe remain healthy, so both canary pods can become
Ready and ALB target health can reconcile normally. Requests through the canary `/api` path return
HTTP errors. The existing direct/public gate must detect those errors before promotion.

The rollout helper treats this as an expected-block drill only when invoked with
`--regression-mode http-error`. A passing gate is a drill failure: the helper refuses promotion,
runs the same ADR 0023 abort path, and exits non-zero. An actual gate block is successful only after
the helper restores both captured stable images, holds reconciled 100/0, removes all canary
resources, verifies stable-only routing, and emits both `ROLLBACK_GATE` and `T1302_GATE` evidence.

## Local-first proof

This is a local Kubernetes drill under [`aws-session.md`](aws-session.md); record it as
`AWS: none`.

1. Run the credential-free state-machine and render checks:

   ```text
   scripts/test-p13-canary-regression-rollback.sh
   helm template bedoux charts/bedoux \
     --set canary.enabled=true \
     --set canary.weight=10 \
     --set canary.regressionMode=http-error
   ```

   The render must contain `API_UPSTREAM: api-canary:8000/__p13-regression`; an unknown mode must
   fail Helm rendering.
2. Start or recover the explicit Calico-backed kind context. Never use the default context, which
   may still point at a deleted EKS endpoint. Confirm the stable release and catalog are healthy,
   then record the exact running stable API/web images.
3. Build and load distinct candidate tags. Review the dry-run, then execute:

   ```text
   scripts/p13-canary-rollout.sh \
     --context kind-bedoux \
     --stable-api-image <exact-running-api-image> \
     --stable-web-image <exact-running-web-image> \
     --candidate-api-image localhost/bedoux-api:p13-2-candidate \
     --candidate-web-image localhost/bedoux-web:p13-2-candidate \
     --values charts/bedoux/values.yaml \
     --values charts/bedoux/values-kind-hpa.yaml \
     --helm-set networkPolicy.enabled=true \
     --weight 10 \
     --attempts 20 \
     --max-errors 0 \
     --drain-seconds 5 \
     --regression-mode http-error \
     --dry-run
   # Replace only --dry-run with --execute after the baseline and images pass.
   ```

4. Require all of the following:

   - both canary Deployments became Ready before the gate;
   - the rendered ingress split was 90/10 and the exact candidate images were staged;
   - `CANARY_GATE` reported errors above the zero allowance;
   - no `PROMOTE:` mutation occurred;
   - `ROLLBACK_GATE stable_images_restored=true canary_resources_absent=true`;
   - `T1302_GATE regression=http-error promotion=blocked rollback=stable-only`;
   - the stable Deployments still use the exact captured images;
   - canary Deployments, Services, ConfigMap, Ingresses, and weighted routes are absent; and
   - stable health and the catalog pass after rollback.

5. Remove only drill-specific images/files and restore any owner-approved temporary host limit.
   Preserve unrelated local data.

## Before the AWS session

Complete every **Before the session** item in [`aws-session.md`](aws-session.md). Also require:

- the focused P13.2 PR remains unmerged while the older `main` baseline is deployed;
- exact-head CI and independent technical review pass;
- an independent four-hour Edmonton alarm with at least 75 minutes reserved for ordered teardown;
- current budget/forecast below the project stop thresholds and a refreshed session estimate
  below USD 4;
- a saved no-NAT temporary-resource plan with zero delete/replace actions, separately approved by
  exact SHA-256 before apply; and
- no authorization is inferred for PR merge, workflow dispatch, or Terraform apply.

## Baseline, merge, and regression dispatch

1. Create the bounded temporary EKS/VPC session and bootstrap the same namespace readiness label,
   target-group-binding reader RBAC, `gp3`, and pinned AWS Load Balancer Controller used by the
   proven P13.1 runbook.
2. While GitHub `main` is still the preceding revision, dispatch **Deploy learning session** with
   `seed_catalog=true` and every optional input false. Require digest-pinned stable images, a
   non-empty catalog, one healthy stable target group with the applied 30-second deregistration
   delay, and healthy injected ALB pod-readiness conditions.
3. Obtain explicit owner approval before marking the unchanged P13.2 PR ready or merging its exact
   head. Verify the resulting `main` merge SHA.
4. Obtain separate owner approval before dispatching from that exact `main` SHA with:

   - `seed_catalog=false`;
   - `canary_regression_drill=true`;
   - `canary_rollout=false`; and
   - `rollback_drill`, RDS, Secrets Manager, S3 images, and custom domain all false.

5. Require the workflow to prove exact staged 90/10, both healthy target groups, applied
   30-second deregistration, and Ready canary pods before the health/error sample. The sample must
   block. Promotion must never begin. The abort must reconcile exact 100/0, hold the bounded drain,
   restore the captured stable digests, remove the canary target group and Kubernetes objects, and
   pass final public health/catalog smoke.
6. Record sanitized `ALB_RECONCILIATION_GATE`, the blocking `PUBLIC_CANARY_GATE`, any
   `CANARY_GATE` reached before a block, `ROLLBACK_GATE`, and `T1302_GATE` lines plus
   Helm/Kubernetes evidence. The AWS gate samples public traffic before its direct sample, so an
   expected public error block may deliberately stop before printing `CANARY_GATE`; the local kind
   proof supplies that deterministic direct-gate evidence. Diagnose the injected failure from
   these outputs alone; do not rely on console inspection.

Stop and preserve canary resources for diagnosis if 100/0 reconciliation or stable target health
cannot be proved. Stop the drill as failed if the gate passes, any promotion mutation occurs, the
stable images differ after abort, cleanup leaves a canary object/target group, or final public
health/catalog fails.

## Teardown

At the cutoff, follow the P13.1 ordered teardown: delete Ingress/ALB first, then application,
namespace/PVC, controller, and `gp3`; prepare persistent state; generate and separately approve an
exact temporary-only destroy-plan SHA-256; apply only the unchanged approved plan; delete the
captured temporary cluster OIDC provider; and run the complete inventory sweep.

Only the approved persistent allowlist may remain. Record final cost, workflow/merge SHAs, clean
AWS inventory, and local temporary-file cleanup before claiming T-1302.
