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

Current state as of 2026-08-30T12:13:46-06:00:
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
1. Inspect ADR 0023's existing gate and abort cleanup path, then implement the smallest explicit
   canary-only latency/error regression input without creating a competing deployment path.
2. Prove locally that the gate blocks promotion and automatic cleanup restores stable-only state.
3. Keep T-1302 incomplete until a separately approved alarmed AWS drill proves the behavior live;
   no current authorization covers AWS, workflow dispatch, publication, or merge.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No temporary
AWS resource is currently live.
```
