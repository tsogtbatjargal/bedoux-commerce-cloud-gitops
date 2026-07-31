# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
You are continuing work on bedoux-commerce-cloud at
/var/home/tsogtb/git-projects/bedoux/bedoux-commerce-cloud — a long-running, agent-agnostic
AWS EKS commerce learning project with a hard USD 20/month budget. Owner-confirmed
optimization target: this is an EKS/platform-engineering portfolio (operational evidence —
drills, rollback, IAM — outranks commerce-app features whenever the two compete for time).

## First actions
1. Read START-HERE.md, then AGENTS.md, then docs/PROGRESS.md (the only authoritative state).
2. Verify the last checkpoint before changing anything.
3. Check docs/IMPLEMENTATION-PLAN.md's "Pending owner-approved decisions" section — only
   one item remains open (the P6/P7 S3 adapter boundary); the two P5-scoped decisions are
   done (ADR 0006, and the kill switch/request bounds).

## Current state (as of 2026-07-31)
- Phases 0-4 complete, gates approved. Local app (FastAPI + Postgres + React) proven on
  Compose (P2), then on kind with a Helm chart (P3, ADR 0005), with real drills throughout.
  AWS account readiness done in P4: non-root IAM identity `bedoux-admin`, region
  `ca-central-1` pinned, USD 20 budget + Cost Anomaly Detection live.
- **Phase 5 (Manual EKS session) is fully complete and its gate is owner-approved.** This was
  the first phase to create real billable AWS resources, and it did: a full eksctl EKS
  cluster, node group, ALB, and app deployment were created, exercised, and torn down
  same-day. No AWS resources are currently live — confirmed via a full
  teardown sweep, not assumed.
- **Phase 6 is active; P6.1–P6.3 are complete.** Terraform now recreates the P5
  learning profile with a public-only VPC (no NAT), EKS 1.34, one Spot `t3.medium` node,
  ECR lifecycle policy, IRSA/OIDC, EBS CSI, and controller permissions. P6.2 proved a
  real Terraform apply/verify/destroy cycle: cluster access initially failed because the
  creator had no EKS access entry, then passed after Terraform created an explicit,
  dynamically derived creator access entry and cluster-admin association. The node was
  Ready, EBS CSI was ACTIVE, and the full teardown sweep was clean. No temporary AWS
  resources remain; only the state bucket, two ECR repos, and four IAM roles plus policy
  are persistent allowlisted resources.
- **P6.3:** PR #1 validates API/PostgreSQL, web lint/test/build, Terraform/Helm, and container
  scanning; all checks are green. Terraform declares a main-branch-bound GitHub OIDC role with
  ECR/cluster-description permissions and namespace-scoped EKS edit access for P6.4. GitHub's
  current private-repository plan cannot enforce a server-side rule; ADR 0010 documents the
  installed, tested local pre-push guardrail that blocks direct `main` pushes in this clone and
  explicitly states its non-server-enforced limitation.
- **P6.4 is complete.** Main-branch run `30657784919` proved GitHub OIDC, immutable ECR image
  push, namespace-only Helm deployment, real EBS CSI `gp3` provisioning, migration/seed jobs,
  and public ALB health/catalog smoke. The same session then tore down the Ingress/ALB, release,
  controller, cluster, VPC, and add-on; final inventory was clean for all temporary billed
  resources. During an exceptional Terraform destroy recovery, the EBS CSI role was also deleted
  through its OIDC-provider dependency. It is no-cost and Terraform will recreate it next
  session; harden that recovery path before P6.5.
- Three real findings surfaced and were fixed during P5, each documented with its own ADR
  or PROGRESS entry:
  1. **ADR 0007** — `bedoux-admin`'s scoped IAM policy (`bedoux-iam-scoped`) had a genuine
     self-escalation hole: because the policy's own resource pattern matched its own ARN,
     `bedoux-admin` could rewrite its own constraining policy. Closed with an explicit Deny,
     applied by the owner via console (never via `bedoux-admin`'s own API access, to avoid
     exercising the escalation path even for the fix itself). Policy is now at v3; also
     picked up the narrow IAM grants `eksctl`/IRSA genuinely need (an EKS nodegroup
     service-linked-role check, OIDC provider tag/delete).
  2. **ADR 0008** — the ALB Ingress Controller has no path-rewrite annotation equivalent to
     nginx's `rewrite-target`, so the AWS profile can't route `/api` straight to the API
     Service the way kind does. Fixed by routing everything through `web` and letting its
     own nginx reverse proxy (already built for Compose in P2.4, previously dormant in
     Kubernetes) forward `/api` internally. `charts/bedoux/templates/ingress.yaml` branches
     on `ingress.controller` (`nginx` vs `alb`) to emit the right shape.
  3. **Undisclosed NAT Gateway** (documented in `docs/PROGRESS.md`'s P5.5 entry, no
     standalone ADR — a config bug fix, not a design decision): `k8s/eksctl-cluster.yaml`
     never set `vpc.nat.gateway: Disable`, so eksctl silently created one for the whole
     session, violating the project's explicit no-NAT rule. Cost was trivial (~USD 0.07)
     but it went undetected until the teardown sweep's tagging-API check caught it. Now
     fixed in the committed config — any future P5-family session should not repeat this.
- ADR 0006 (Spot-node risk acceptance + real gp3 PVC via EBS CSI) and the order-write kill
  switch + request bounds were both implemented and live-verified — including a full
  golden-path order confirmed in Postgres over the real public ALB DNS name, and the kill
  switch correctly defaulting to off (verified via `/api/health`) before that demo window.
- `charts/bedoux/values-aws.yaml` is the AWS session profile overlay: `storageClass.create:
  true`, `postgres.storageClassName: gp3`, `api.ordersEnabled: false`,
  `ingress.{className,controller}: alb`.
- Real-browser verification is wired up via Playwright MCP + a real Google Chrome (Flatpak,
  throwaway profile at /tmp/chrome-mcp-profile). Must be relaunched after any session/host
  restart (see docs/local-tooling.md).
- Rootless-Podman + kind cgroup delegation is fixed and documented (docs/local-tooling.md).

## Locked decisions (do not revisit without a new ADR in docs/decisions/)
- ADR 0001: small stack — React/Vite/TS, FastAPI, PostgreSQL, image-storage adapter boundary.
- ADR 0002: MVP defers Route53/ACM (use ALB DNS, HTTP), RDS (in-cluster Postgres until P7),
  S3 images and Secrets Manager (P7). No NAT Gateway in the learning profile.
- ADR 0004 (supersedes 0003): private repo at bedoux-tech, flip public before P9 after a
  full-history secrets sweep; direct-to-main until P6; commit convention
  `<TaskID> complete: ...` and gate commits.
- ADR 0005: DB migrations run as a Helm post-install,pre-upgrade hook Job; no auto-downgrade
  on rollback; seed is a separate opt-in Job, never on by default.
- ADR 0006: accept Spot-node interruption risk in the learning profile; still provision real
  gp3 storage via the EBS CSI driver + its own IRSA role — proves the storage/IAM setup, not
  database resilience (that's P7's job via RDS).
- ADR 0007: closed a real self-escalation hole in `bedoux-admin`'s scoped IAM policy; any
  future change to `bedoux-iam-scoped` requires the owner via console/root, permanently.
- ADR 0008: the AWS ALB profile routes everything through `web`; `/api` prefix-stripping
  happens via `web`'s own nginx reverse proxy, not an ALB-level rewrite (ALB has none).
- ADR 0009: GitHub Actions uses a main-branch-bound OIDC deployment role with least-privilege
  ECR/EKS permissions and `bedoux`-namespace edit access.
- ADR 0010: until server-side protection becomes available, block direct local `main` pushes
  with the documented pre-push guardrail; never claim that it protects other clones or GitHub UI.
- One decision remains pending, not yet implemented — see docs/IMPLEMENTATION-PLAN.md's
  "Pending owner-approved decisions": the P6/P7 S3 image adapter boundary (API returns
  `image_url`, presigned URL via IRSA in S3 mode, frontend storage-agnostic).

## What I want next
Continue the single task marked IN PROGRESS in docs/PROGRESS.md: **P6.5 — CI rollback drill**.
Work one item at a time and record evidence before checking anything off. Before any mutation,
first harden P6.4's Terraform teardown-recovery path; then manually walk the full **Before the
session** checklist in `docs/runbooks/aws-session.md`, review the Terraform plan/cost, set a
same-day teardown time, and use `bedoux-admin`.
There is no `/aws-session-start` for Codex: before touching AWS, manually walk the "Before
the session" checklist in `docs/runbooks/aws-session.md`, and run its teardown sweep before
ending any AWS session. Never create AWS resources outside that process. If asked to approve
a phase gate, make that its own commit ("Phase N gate approved by owner; activate Phase
N+1") before starting the next phase's work. The Terraform VPC must keep NAT disabled.
```
