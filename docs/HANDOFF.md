# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/worktrees/bedoux-commerce-cloud/raspy-lantern/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git and preserve unrelated changes.

Current state as of 2026-08-30T17:34:27-06:00:
- P0-P12 are complete and gate-approved. P13 is active. P13.1 and T-1301 are complete. The owner
  explicitly activated P13.2 on 2026-08-30; T-1302 is the single IN PROGRESS task.
- PR #57 exact head `c58ca0bc24b1fcec1f203f405ef04a0179dae6da` passed all four jobs in run
  `33327244984` and merged to `main` as `c815ecac09e05d44404f477a497e3361457e0833`.
  The worktree is on focused branch `p13-2-blocked-canary` from that exact `origin/main` SHA.
  Never push `main` directly.
- ADR 0023 is Accepted. It keeps one Helm release and implements opt-in stable/canary API+web
  pairs, ALB/ingress-nginx weighting, exact image checks, direct/public health gates, ALB listener
  and target-health reconciliation, injected pod-readiness gates, reconciled 100/0 promotion,
  bounded drain, and stable-only cleanup.
- P13.2's local implementation was prepared after activation checkpoint `cc3f001`. The new
  disabled-by-default `canary.regressionMode=http-error` keeps canary pods Ready while only
  `web-canary` API requests fail. The rollout succeeds in drill mode only after the existing gate
  blocks promotion and the ADR 0023 abort proves captured stable images plus absent canary objects.
  A gate that accepts the regression still triggers abort/cleanup and exits non-zero.
- The first independent review found that generic composite-gate failures could be mistaken for
  the injected regression. Exact local fix `f6b113acdddf96de710d331a4cca3628842601d5`
  now emits reserved status 20 only when correlated access logs prove HTTP errors above the
  allowance after image/readiness/weight and ALB prerequisites pass. Unrelated status 1 still
  rolls back but exits failed without `T1302_GATE`. Real-gate mocks prove HTTP-error, tooling-error,
  and pass classifications; rollout mocks prove unrelated failure cannot produce T-1302 evidence.
- Independent review accepted implementation `f6b113a` and checkpoint `cc2d8e3` after realistic
  nginx-log regex verification. Follow-up `0b9bcee64d7b34b3f01fbd118c16d3b92d4f87a0`
  folds in both review suggestions: rollout success now also requires exactly one structured
  attribution marker, and ordinary-rollout status-20 diagnostics accurately describe a blocked
  HTTP-error promotion outside an authorized drill. Mocks cover unattributed status 20 and the
  corrected normal-rollout path.
- The owner-authorized real local P13.2 drill passed on explicit retained context `kind-bedoux`.
  Helm revision 7 staged both Ready canaries at 10%; 20/20 injected API requests returned
  access-log-correlated HTTP 404s; structured status 20 blocked promotion; revisions 8/9 restored
  the exact captured stable images, held the five-second drain, and removed all canary objects.
  `ROLLBACK_GATE` and `T1302_GATE` printed, no `PROMOTE:` occurred, and independent stable
  health/catalog plus HPA/NetworkPolicy checks passed.
- Local cleanup removed the candidate tags, failed-import aliases, archives, and evidence log.
  The retained node is stopped (`Exited (137)`) with its PVC preserved, and the owner restored
  host inotify from the temporary 1024 to its original 128. AWS: none. A retained-node restart
  snapshotter-service finding and bounded recovery are recorded in `docs/local-tooling.md`.
- The owner authorized feature-branch publication and a draft PR only. Draft PR #58 is open,
  mergeable, and unmerged against exact base `c815ecac09e05d44404f477a497e3361457e0833`.
  Independent technical review accepted exact head
  `f69e680a47f41068efdc135b9c729a8b7f0a0d84`; all four required jobs passed on that exact head in
  run `33341568312`.
- The local drill satisfies T-1302's generic wording, but project completion intentionally also
  requires the AWS-specific ALB public-error path: real listener weighting and target health,
  public-to-canary error correlation, and stable-only ALB cleanup. This stricter evidence boundary
  and the warning against copying deliberate traffic-slice errors into a production/customer
  session are explicit in the P13.2 runbook; ADR 0023 is unchanged.
- `canary_regression_drill` is mutually exclusive with ordinary canary/rollback paths and requires
  every unrelated input false. The state-machine mocks prove expected-block, unrelated-block, and
  regression-escaped paths. Helm renders, shell/YAML syntax, full infrastructure CI commands,
  action pins, docs checks, and whitespace checks pass. No AWS or Kubernetes endpoint was used.
- PR #55 merged the P13.1 implementation and repaired EKS launch-template/ASG tagging path to
  `main` as `5bbf959a689f46e20b7512b2be42c52a148b5c36`. Older-P12 baseline run `33267748556`
  proved the signed stable deployment, public health, six-product catalog, one healthy stable
  target, and an injected `True` ALB target-health readiness condition.
- The first T-1301 run `33277095118` failed closed before staging because ALB normalized its sole
  stable forward target to relative weight 1. No canary object was created and the baseline stayed
  healthy. PR #56 exact head `5b48f81b4f0e7e177f8c066324302b51e50f8faa` preserved exact
  staged/promotion matching while accepting only one positive-weight stable target during cleanup.
  Exact-head run `33278575055` passed all four jobs; the owner approved that exact head and it
  merged to `main` as `68847978e25c0cce7ef0db757a6996004813ce41`.
- Separately authorized T-1301 run `33278906766` used `seed_catalog=false`,
  `canary_rollout=true`, and every unrelated input false. It passed exact 90/10 staging with two
  healthy target groups and applied 30-second deregistration, `CANARY_GATE` 20/20 with zero
  errors, and `PUBLIC_CANARY_GATE` 100/100 with zero errors plus 13 correlated `web-canary` hits.
  Promotion reconciled exact 100/0 and healthy ALB pod-readiness before the 45-second drain.
  Cleanup retained one healthy stable target group and removed every canary Deployment, Service,
  Ingress, and TargetGroupBinding. Final public health and the six-product catalog passed.
- Final stable images matched the exact candidate digests recorded in docs/PROGRESS.md. Helm
  revision 6 had only stable API/web/PostgreSQL workloads before teardown.
- Ordered same-session teardown deleted the Ingress first and waited for zero ALBs/target groups,
  then removed the release, namespace/PVC, AWS Load Balancer Controller 3.4.3, and `gp3`.
  Persistent Terraform state was guarded and detached. The owner approved exact temporary-only
  destroy plan SHA-256 `7f5174b04b66c54eaefdc2617f65599f1ede00b09c8d70007a3363cd919727c4`;
  its unchanged apply destroyed 18 resources, added 0, changed 0, and deleted the captured
  temporary cluster OIDC provider.
- The repeated 21:13 Edmonton authoritative inventory returned zero EKS clusters, ALBs, target
  groups, NAT Gateways, EIPs, non-terminated instances, EBS volumes/snapshots, RDS resources,
  active stacks, project ASGs, launch templates, VPCs, and ENIs. Exact lookup proved the temporary
  cluster OIDC provider absent. The tagging index's stale terminated-instance record was
  authoritatively reconciled as terminated, with its root volume absent; it is indexing lag, not
  billable residue.
- Only the approved persistent allowlist remains. No website alias or temporary AWS resource is
  live. Budget actual is USD 6.002 and forecast USD 6.239 of USD 20. All exact T-1301 files are
  removed from `/tmp`. Persistent resources are detached from session Terraform state.
- The retained local Calico-backed kind node is stopped with its PVC preserved. The host
  `fs.inotify.max_user_instances` value is restored to 128. The default kubeconfig points to a
  deleted EKS endpoint; always use an explicit context.

Next action:
1. Set an independent Edmonton alarm with at least 75 minutes reserved for teardown, then obtain
   explicit authorization for an AWS session only through read-only preflight, persistent-state
   reconciliation, and exact saved-plan generation before any apply.
2. Keep PR #58 draft and unmerged while the older `main` baseline is deployed later.
3. Keep T-1302 incomplete until the separately approved AWS drill also proves the behavior. No
   current authorization covers publication, AWS, dispatch, or merge.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No temporary
AWS resource is currently live.
```
