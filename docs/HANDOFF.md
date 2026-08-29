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
  post-merge checkpoint and focused P13.1 implementation. Reviewed implementation `6cdb54c` and
  owner-acceptance checkpoint `e2db4dc` are published on `origin/p13-1-canary`; no PR exists yet.
  Never push `main`.
- Accepted ADR 0023 keeps one Helm release and adds opt-in stable/canary API+web pairs,
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

The owner accepted ADR 0023 on 2026-08-28 against implementation `6cdb54c` as represented by
checkpoint `791b0e4`. This permits PR and live-plan preparation, not merge or AWS execution.
- Draft PR #55 targets `main` from `p13-1-canary`. Exact-head run `33193213907` passed API, web,
  Terraform/Helm, and container build/scan/SBOM/signature jobs before the stopped live attempt; the
  PR remains draft and unmerged.
- A bounded T-1301 session used a 19:00 Edmonton alarm and 17:45 teardown cutoff. Read-only
  preflight confirmed the non-root identity, pinned region, budget actual USD 5.915, forecast
  USD 6.603, a conservative four-hour estimate below USD 1, and zero temporary AWS resources.
- Persistent state is reconciled at exact Terraform source head `efb3b06`. Exact saved plan
  `/tmp/bedoux-p13-t1301-20260828-1558.tfplan` hashes to
  `ce72db3e6c6a1d39680784a7fb680f93195f824265121a185ce6c1bb5dc49376`: 25 creates, 11 in-place
  updates, zero deletes/replacements. It preserves Route 53/ACM as no-op, keeps aliases disabled,
  uses EKS 1.34 with one Spot `t3.medium` at 1/1/1, and contains no NAT/EIP or optional managed
  service. The owner approved and Terraform applied that exact binary: EKS, the Ready Spot node,
  and both pinned add-ons are healthy. No PR state change, workflow dispatch, application, ALB, or
  Kubernetes bootstrap occurred.
- Post-apply verification found a blocker: EKS did not propagate the standard project/environment
  tags to its managed EC2 instance or root gp3 volume, and its backing Auto Scaling group has no
  propagate-at-launch copies. Live remediation is a new mutation outside the approved binary.
- The owner ordered immediate teardown and approved exact temporary-only destroy plan SHA-256
  `77a0273803ca29faa826ecbe09ee2100174c6c03f813e96dbf8c57acf5da21f9`. The guarded helper
  rechecked the hash, destroyed its exact 15 resources, and deleted the captured temporary cluster
  OIDC provider. The 16:49 Edmonton sweep returned zero temporary compute, network, storage,
  database, load-balancing, alias, log, stack, and cluster-OIDC resources. Only the approved
  persistent allowlist remains. All exact session files were removed from `/tmp`.
- Temporary infrastructure existed for less than one hour, with no ALB/NAT/RDS; conservative
  incremental cost is below USD 0.10 pending billing ingestion. P13.1 remains `IN PROGRESS`, and
  T-1301 is not claimed because required managed-node/root-volume tag propagation was absent.
- Local repair `353e3f4` covers both default primary and P11 HA secondary node groups: dedicated
  launch templates tag instances and volumes at creation and own the 20-GiB gp3 root mapping;
  node-group `disk_size` is absent; and dedicated ASG-tag resources set both standard tags with
  `propagate_at_launch=true`. Mocked default/P11-HA plans pass 2/2, all three credential-free
  Terraform profile validations pass, and CI now enforces the mock tests plus the `disk_size`
  absence check. No AWS API endpoint or remote state was reached for this local repair.

Next action:
1. Obtain independent review of local Terraform repair `353e3f4` in draft PR #55. After
   acceptance, open a fresh alarmed AWS session, reconcile persistent state, and generate a new
   exact plan for separate approval. PR ready/merge, workflow dispatch, T-1301 completion, and
   P13.2 remain separately gated.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No AWS session
is open and no temporary AWS resource is live; P13.1 still awaits T-1301.
```
