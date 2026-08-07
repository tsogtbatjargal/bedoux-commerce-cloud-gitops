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
3. Check docs/IMPLEMENTATION-PLAN.md's "Pending owner-approved decisions" section — all
   phase-start decisions are now recorded: ADR 0006, the kill switch/request bounds, and
   ADR 0011's P7.2 S3 adapter boundary.

## Current state (as of 2026-08-07)
- Phases 0-4 complete, gates approved. Local app (FastAPI + Postgres + React) proven on
  Compose (P2), then on kind with a Helm chart (P3, ADR 0005), with real drills throughout.
  AWS account readiness done in P4: non-root IAM identity `bedoux-admin`, region
  `ca-central-1` pinned, USD 20 budget + Cost Anomaly Detection live.
- **Phase 5 (Manual EKS session) is fully complete and its gate is owner-approved.** This was
  the first phase to create real billable AWS resources, and it did: a full eksctl EKS
  cluster, node group, ALB, and app deployment were created, exercised, and torn down
  same-day. No AWS resources are currently live — confirmed via a full
  teardown sweep, not assumed.
- **Phase 6 is complete; its gate is owner-approved.** Terraform now recreates the P5
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
- **P6 is fully complete; its gate was approved by the owner on 2026-08-01, and P7 is active.**
  After the local repair merged, green run
  `30685274638` proved the baseline release and public smoke. Controlled run `30685420148`
  captured the actual pre-drill web image, deliberately failed the Helm web rollout, then passed
  the conditional rollback verification and public health assertion after Helm atomically restored
  the release (T-602). The improved teardown helper used an explicit state-only preparation step,
  reviewed a plan with exactly 14 temporary EKS/add-on/VPC deletes and no persistent addresses,
  and the final inventory sweep was clean. No temporary AWS resources are live.
- **P7.1 is complete — T-701 was proven 2026-08-01.** It adds a disabled-by-
  default, private, encrypted Single-AZ RDS module with EKS-security-group-only PostgreSQL
  ingress; an external Helm database mode consumes a pre-created `rds-credentials` Secret and
  omits the in-cluster Postgres workload. API/migration/seed readiness uses SQLAlchemy `SELECT 1`
  against the same connection URL the app uses. Offline Terraform/Helm/workflow checks pass. The
  stale kind port-forwarder was repaired by recreating the exact project cluster with the
  documented `Delegate=yes` scope; a disposable external-profile namespace then passed migration,
  seed, six-product catalog, and persisted-order proof, and was deleted cleanly. The 2026-08-01
  AWS session then proved real RDS provisioning, migration/seed Jobs, API/web readiness, and a
  public catalog smoke through successful GitHub Actions run `30715096011`, followed by a clean
  full teardown. The earlier session overran its deadline but was fully removed; the follow-up
  session used an independent 22:00 MDT alarm and successful GitHub Actions run `30727844150`.
  Its bounded `scripts/verify-order-proof.sh` procedure created and read back exactly one
  quantity-one public synthetic order, then a direct API workload query confirmed exactly one
  RDS-backed row. Ordering was restored disabled and the final teardown sweep was clean before the
  deadline. P7.2 then completed its S3/IRSA proof; P7.3 owns the Secrets Manager replacement for
  the temporary Kubernetes Secret.
- **P7.2 is complete — T-702 was proven 2026-08-02.** ADR 0011's storage-neutral boundary is
  live: product records keep a stable `products/...` key; static mode returns the web asset URL;
  S3 mode returns an API-generated presigned `GetObject` URL through a ServiceAccount-specific
  IRSA role. Successful GitHub Actions run `30761203972` passed migration/seed/rollout and its
  masked direct-S3 image smoke; an API-pod STS assertion confirmed the expected image-read role.
  The temporary private/encrypted/versioned S3 bucket, its six synthetic objects, scoped role and
  policy, RDS, EKS, and VPC were all removed in the same session. The final sweep was clean;
  only the approved state bucket, two ECR repositories, and no-hourly-cost IAM/OIDC allowlist
  remain. **P7.3 and P7.4 are complete:** ADR 0012's direct Secrets Manager retrieval through
  the separate `bedoux-api-secrets` IRSA identity passed live, and the RDS deletion/backup
  policy plus T-703 same-day teardown evidence are recorded. **P7's gate is approved and P8 is
  active. P8.1 is complete:** the API emits safe structured JSON completion logs with request-ID
  propagation, proven in the pinned local runtime and a real local container. **P8.2 is
  complete (2026-08-05):** a time-bounded no-NAT session proved temporary three-day Container
  Insights logging (including the add-on-created `performance` group), the IRSA-restricted
  collector, structured application-log delivery, dashboard, and four notification-free alarms,
  all `OK`. The session was torn down and independently verified clean well before its 17:30
  MDT alarm. Two real teardown-script bugs found live that session (invalid hardcoded CloudWatch
  add-on version placeholder; unset RDS password breaking Terraform's plan-time string
  interpolation) were fixed, proven, and merged.
- **P8.3 (four troubleshooting drills) is complete (2026-08-07), T-802 satisfied.** A first AWS
  session attempt (2026-08-06) hit a real, previously-undiscovered bug — Alembic's
  `Config.set_main_option` crashed on any DB password containing a `%`-encodable character — and
  separately overran its planned teardown deadline by roughly three hours while that was being
  diagnosed, with no independent wall-clock alarm set. Both were recorded honestly in
  `docs/PROGRESS.md` rather than glossed over; the session was emergency torn down and
  independently verified clean, and the fix (escape `%` as `%%`) was proven two ways (a unit
  test and a real local `kind` migration run) and merged as PR #29. The 2026-08-07 retry applied
  the lesson directly: an actual enforced background alarm (1h/30m/10m/deadline notifications)
  was armed at session start, not just intent. The app deployed successfully with the fix
  (main-branch run `31199043032` proved OIDC/ECR/migration/seed/rollout/ALB smoke all passing
  against the real RDS + Secrets Manager profile). All four drills — unhealthy
  ALB target (scale-to-0 → ALB `draining` → `503`), failed pod (CrashLoopBackOff via a bad
  container command → `kubectl logs` showed the exact injected error), DB connection error
  (revoked the RDS security group's ingress rule → `pg_isready` timeout + empty rule list, both
  from tooling), and failed rollout (`helm upgrade --atomic` with a nonexistent image tag →
  `ImagePullBackOff` → Helm's own atomic rollback fired automatically) — were induced, diagnosed
  purely from tooling output, fixed, and independently confirmed recovered. Teardown finished
  roughly 2h50m under the 14:04 MDT deadline; independent sweep confirmed clean.
- **P8.4 is complete.** `docs/runbooks/p8-troubleshooting.md` documents all four P8.3 drills as
  symptom → diagnose (exact commands, real output shapes) → root cause → fix → recovery check,
  written directly from the commands proven live in the same P8.3 session — not generic
  guidance. T-801 (P8.2) and T-802 (P8.3) are both satisfied. **P8 gate approved by owner
  2026-08-07; P9 (interview package) is active. P9.1 is complete:**
  `docs/interview/walkthrough-script.md` is a timed 15-minute script (1/3/3/3/3/2 min per the
  plan's allocation) grounded entirely in real recorded evidence — no hypothetical capability.
  **P9.2 is complete:** all six diagrams exist and are exported to sibling SVGs in
  `docs/diagrams/` — the two existing (`system-context`, `learning-path`) plus four new
  (`request-path`, `ci-cd`, `vpc-network`, `identity`), each grounded in real facts from
  `docs/architecture.md` and named ADRs. A real layout bug (container children starting at
  `y=20` painted over their own swimlane's title text at `startSize=44`) was found and fixed
  during self-check, not shipped.
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
- ADR 0011: API image delivery is storage-neutral (`image_url`); S3 mode uses a private bucket
  and API-side presigned URLs through a ServiceAccount-specific IRSA role, never an image proxy.
- ADR 0012: the P7.3 API, migration, and seed processes retrieve a JSON `DATABASE_URL` directly
  from a temporary Secrets Manager secret through the exact `bedoux-api-secrets` ServiceAccount;
  no Kubernetes credential Secret is synchronized.

## What I want next
P9.1 and P9.2 are both done. Next is **P9.3 — a timed dry-run** of the P9.1 script
(`docs/interview/walkthrough-script.md`) against a real clock, using the finished P9.2 diagrams
(`docs/diagrams/`), trimmed to fit 15 minutes. The script's own timing notes flag section 5
(observability/troubleshooting) as the one with the most material to cut first if it runs long.
Record the actual timed result (even if just "read aloud in N:NN, trimmed to fit") in
`docs/PROGRESS.md` as T-901 evidence. P9 needs no AWS session (`$0` cost).
There is no `/aws-session-start` for Codex: before touching AWS, manually walk the "Before
the session" checklist in `docs/runbooks/aws-session.md`, and run its teardown sweep before
ending any AWS session. Never create AWS resources outside that process. If asked to approve
a phase gate, make that its own commit ("Phase N gate approved by owner; activate Phase
N+1") before starting the next phase's work. The Terraform VPC must keep NAT disabled.
```
