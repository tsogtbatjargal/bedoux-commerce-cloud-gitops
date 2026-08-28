# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/worktrees/bedoux-commerce-cloud/raspy-lantern/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git; preserve unrelated changes.

Current state as of 2026-08-28:
- P0-P12 are complete and gate-approved. The owner explicitly approved the P12 gate on
  2026-08-26 and activated P13. P13.1 is the sole `IN PROGRESS` item; P13.2 remains gated.
- ADR 0022 supersedes ADR 0021: the owner retired Shopify, selected the `bedoux.ca` apex plus
  `www`, and explicitly approved hosted-zone/certificate persistence.
- PR #53 passed all four jobs in final run `33006117123` and merged the P12.2 HTTPS/redirect,
  certificate-discovery, staged-alias, proof-helper, and guarded-session path to `main` as
  `775dfe1`.
- T-1201 remains proven: the public Route 53 zone is delegated and the Amazon-issued certificate
  is `ISSUED` for exactly `bedoux.ca` and `www.bedoux.ca`, with two DNS validation records.
- T-1202 passed in bounded workflow run `33013651632`: signed immutable images deployed through
  the HTTPS ALB; system, Cloudflare, Google, and Quad9 resolved both aliases; the fail-closed
  helper proved trusted HTTPS and HTTP 301 redirects for both names; real Google Chrome loaded
  the apex without a certificate warning and rendered the seeded catalog.
- T-1203 passed: exact approved plans removed the apex/`www` aliases before deleting the Ingress,
  ALB, application, controller, EKS, cluster OIDC provider, and no-NAT VPC. The 18:56 Edmonton
  sweep returned zero temporary compute, network, storage, database, load-balancing, alias, and
  cluster-OIDC resources.
- The persistent allowlist is exactly one protected/versioned state bucket, two ECR repositories,
  six persistent IAM roles, GitHub OIDC provider, and the delegated `bedoux.ca` zone with issued
  certificate/validation records. The zone has no website `A` aliases and the certificate is not
  attached to deleted infrastructure. Budget actual was USD 5.384 of USD 20.
- All exact `/tmp/bedoux*` session files are removed. Persistent resources are intentionally
  detached from session Terraform state; any future AWS session must run the guarded persistent
  import first. No AWS call ran after the clean closeout sweep.
- PR #54 passed all four jobs in run `33036631123` at exact head `38999f2` and merged the P12
  completion/gate checkpoint as `386f66e`. `origin/main` and the primary `main` worktree match
  that merge. Merged P12 branches are deleted locally/remotely; the registrar export in the
  primary worktree remains intentionally untracked and untouched.
- This worktree is on feature branch `p13-1-canary` from exact merge `386f66e`, with the expected
  post-merge checkpoint and focused P13.1 implementation. Verify its publication state from Git;
  never push `main`.
- Proposed ADR 0023 keeps one Helm release and adds opt-in stable/canary API+web pairs,
  controller-native ALB/ingress-nginx weighting, an exact-image/health/error gate, and an automated
  stage → gate → reconciled 100/0 promotion → cleanup helper. The existing signed-image deployment
  workflow gains only an opt-in `canary_rollout` input.
- Helm lint/renders, shell syntax/help/dry-runs, workflow YAML, action pins, `git diff --check`, and
  toolbox `make docs-check` pass. No AWS endpoint was contacted.
- The P13.1 local canary rehearsal passed on explicit context `kind-bedoux`: ingress-nginx staged
  the exact candidate API/web images at weight 10; the direct gate returned 20/20 healthy samples,
  zero errors, and a non-empty catalog; promotion reached 100%; final health/catalog passed; and
  canary Deployments, Services, and Ingresses were absent after cleanup. Existing HPAs and the
  default-deny NetworkPolicies remained enabled.
- The two temporary image archives and redundant host-side candidate tags are gone. The retained
  kind node is stopped with its PVC, node-local candidate images, and promoted local release
  preserved. The owner restored the host inotify limit to 128.
- Independent reviews withheld ADR 0023 acceptance for asynchronous ALB races. The local
  hardening now maps Services through `TargetGroupBinding`, proves real 90/10 public traffic through
  a correlated canary access-log hit, requires injected stable-pod ALB readiness, and blocks the
  drain/cleanup block until the listener is exactly 100/0 with a healthy stable target group. It
  then proves stable-only cleanup and complete canary-object removal. Staged, promotion, cleanup,
  lingering-90/10, and pod-readiness mocks are fail-closed. The latest re-review found that ALB's
  default 300-second deregistration delay could race the gate's 300-second deadline; the P13 helper
  now pins the already-proven 30-second value and every ALB gate verifies the applied target-group
  attribute. A mock left at 300 seconds fails promotion closed.

Next action:
1. Obtain independent technical re-review of hardened Proposed ADR 0023. The full local static
   suite passes. After acceptance, prepare the focused PR and reviewed live T-1301 session
   sequence. Do not start P13.2.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No AWS session
is open; current P13.1 implementation and proof are local-only.
```
