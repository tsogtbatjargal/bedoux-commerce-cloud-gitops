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

## Current state (as of 2026-08-17)
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
  during self-check, not shipped. **P9.3 is complete:** word-count-measured timing showed the
  script fits 15:00 at every realistic delivery pace (14:19 at the slowest tested, 100 wpm) with
  no cuts needed — correcting an earlier unmeasured guess in the P9.1 draft that assumed it ran
  long. **P9 gate approved by owner 2026-08-07. All phases P0–P9 are complete — this is the
  project's final milestone.** Per the owner's explicit decision, the repository **remains
  private**; ADR 0004's "flip public before P9" clause is superseded by
  [ADR 0013](decisions/0013-remain-private-at-p9.md).
- **P10-P14 optimization track bootstrapped 2026-08-09**, at the owner's explicit request to
  optimize/improve the working prototype (reliability/HA, security hardening, delivery
  maturity, performance/cost). This is new, additive work — it does not reopen P0–P9.
  [ADR 0014](decisions/0014-post-p9-optimization-track-scope.md) records the track's scope
  and how it reads `docs/cost-guardrails.md`'s hard limits: bounded autoscaling only (a hard
  `maxReplicas`/node cap satisfies the guardrail; "unbounded" is what's banned), Multi-AZ RDS
  only as a single reviewed one-off (never routine), and the Route 53 domain decision is
  deferred to P12 pending an explicit owner choice. Full phase table (P10 security hardening,
  P11 bounded autoscaling & HA, P12 TLS/custom domain, P13 delivery maturity, P14 cost/perf
  capstone) is in `docs/IMPLEMENTATION-PLAN.md`'s "Phase 10+" section; checklist and gate
  evidence ids (`T-1001`..`T-1404`) are in `docs/PROGRESS.md`/`docs/TEST-PLAN.md`.
- **P10.1 is complete (2026-08-09).** Re-scanned the API base image (`python:3.12-slim`,
  Debian 13) with `trivy`: 23 HIGH/CRITICAL OS-level CVEs (up from 22 at P2.5), every one
  still with an empty `Fixed Version` — genuinely nothing fixable this round, not an
  unchecked assumption. `apps/web` re-confirmed clean at 0. T-1001 satisfied.
- **P10.2 is complete (2026-08-09).** `charts/bedoux/templates/networkpolicy.yaml` adds
  default-deny-all + explicit allows (web↔api, api/bedoux-migrate/bedoux-seed↔postgres,
  ingress-controller-namespace→web/api), gated by `networkPolicy.enabled` (default `false`).
  **Real finding:** kind's default CNI (kindnet) does not enforce `NetworkPolicy` at all —
  objects apply with no error and do nothing. `k8s/kind-config.yaml` now disables the default
  CNI in favor of Calico (pin the actual latest release at setup time — v3.32.1 as of P10.2;
  recipe plus two host-environment findings, an `iptables-legacy`-vs-`nft` mismatch and the
  host's `fs.inotify.max_user_instances` limit, are documented in `docs/local-tooling.md`).
  Live drill on the Calico-backed cluster: an unlabeled pod could not reach
  `postgres:5432`/`api:8000`/`web:8080` directly; the legitimate paths and the full golden
  path (catalog + a real order, cross-checked in Postgres) worked identically with the
  policies active. T-1002 satisfied. **The kind cluster `bedoux` is left running**, now
  Calico-backed, as the ongoing local dev cluster — same precedent as P3.1.
- **P10.3 is complete (2026-08-10), T-1003 satisfied.** Green PR CI generated API/web
  SPDX 2.3 SBOMs, uploaded one seven-day artifact, and signed and verified both immutable
  candidate digests against an ephemeral registry/key without granting PR jobs OIDC or AWS
  access. The main deployment workflow keylessly signs ECR digests, constrains verification
  to the exact `deploy-learning.yml` identity on `main` plus GitHub's issuer, verifies inside
  the Helm step, and deploys `repository@sha256` references. The rollback drill now keeps the
  signed digest and injects a failing web command instead of bypassing the gate with an unsigned
  missing tag. No AWS session was opened for P10.3; the P10.4 apply later recreated the current
  GitHub policy declaration containing its narrowly scoped ECR layer-read delta. Re-read the live
  policy before any future signed AWS workflow dispatch.
- **P10.4 is complete (2026-08-11), T-1004 satisfied.** The re-review found a real second-hop
  delegated-role escalation path not covered by ADR 0007. ADR 0015 now requires the AWS-managed
  `PowerUserAccess` permissions boundary on every project role; owner-applied
  `bedoux-iam-scoped` v4 requires and protects that boundary. Live read-back passed for all six
  roles present in the session, VPC CNI moved to an exact-ServiceAccount IRSA role, the node
  changed to ECR pull-only, EBS CSI moved to its v2 policy, and an attempted unbounded test-role
  creation was denied with no test role left behind.
- **P10.5 is complete (2026-08-11), T-1005 satisfied.** The live EKS VPC CNI add-on reported
  `enableNetworkPolicy=true`; a rogue pod was denied PostgreSQL access while an `app=api` pod
  reached the same service. The temporary no-NAT EKS/VPC session was destroyed and the final
  inventory sweep was clean. **P10 gate approved by owner 2026-08-11; P11 is active.** No
  temporary AWS resources are live. The persistent allowlist is the state bucket, two ECR
  repositories, six persistent IAM roles, and the GitHub OIDC provider.
- **P11.3 is complete:** on `p11-3-live-scaleout`, EKS 1.34 with two Spot `t3.medium` nodes
  served the chart, and pinned k6 0.52.0 drove 14,382 successful requests with 283.57 ms
  average / 741.5 ms p95 / 909.44 ms p99 latency. API and web both scaled from 2 to the hard
  HPA maximum of 3 and recovered to 2 after load. The guarded teardown destroyed all 15
  temporary Terraform resources and the final AWS sweep was clean. The initial same-AZ Spot
  placement exposed a real `minDomains: 2` scheduling limitation; P11.4 owns the node-loss and
  topology follow-up. The default kubeconfig still points to the deleted EKS endpoint.
- Owner-applied `bedoux-iam-scoped` policy v6 is the current live declaration; ADR 0016 and
  `infra/iam/bedoux-iam-scoped-v6.json` record its exact read-only introspection and EKS
  execution-role PassRole additions.
- Repository workflows are exposed through exactly three thin skills under `.agents/skills/`:
  `phase-orchestrator`, `aws-session-guardrail` (including Kubernetes drills), and
  `github-pr-branch-workflow`. Claude Code discovery wrappers under `.claude/skills/` route to
  the same canonical bodies. Operating logic remains canonical in `docs/workflows/` and
  `docs/runbooks/`; do not fork agent-specific procedures.
- Three real findings surfaced and were fixed during P5, each documented with its own ADR
  or PROGRESS entry:
  1. **ADR 0007** — `bedoux-admin`'s scoped IAM policy (`bedoux-iam-scoped`) had a genuine
     self-escalation hole: because the policy's own resource pattern matched its own ARN,
     `bedoux-admin` could rewrite its own constraining policy. Closed with an explicit Deny,
     applied by the owner via console (never via `bedoux-admin`'s own API access, to avoid
     exercising the escalation path even for the fix itself). ADR 0015 later superseded the
     claim that this direct deny was a complete closure; `bedoux-iam-scoped` is now v4 and every
     delegated project role is boundary-capped.
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
- ADR 0013: the repository remains private at P9 (ADR 0004's "flip public before P9" clause is
  not exercised); a future flip requires its own new ADR plus the full-history secrets sweep
  ADR 0004 already specified — not implied by staying private now.
- ADR 0014: scope of the post-P9 optimization track (P10-P14) — additive, does not reopen
  P0–P9; bounded autoscaling (hard caps) satisfies the "no unbounded autoscaling" guardrail;
  Multi-AZ RDS only as a single reviewed one-off, never routine; the Route 53 domain decision
  is deferred to P12 pending an explicit owner choice.
- ADR 0015: every delegated project role must retain the AWS-managed `PowerUserAccess`
  permissions boundary; `bedoux-iam-scoped` v4 requires and protects that exact boundary.
  ADR 0007 remains the direct self-policy fix but is superseded where it claimed complete closure.

## What I want next
P0–P9 are complete and closed (P9 gate approved 2026-08-07) — do not reopen or re-litigate
that work, and do not silently revisit ADR 0013's "remain private" decision without a fresh,
explicit owner decision plus ADR 0004's still-standing full-history secrets sweep prerequisite.

The **active work is P11 — bounded autoscaling and HA**. P10.1–P10.5 are complete and the P10
gate is owner-approved. **P11.1 is complete** — its HPA resources for `api` and `web`, explicit
hard `maxReplicas: 3` cap, pinned Metrics Server, and bounded kind scale-out/scale-back proof
are recorded as T-1101. **P11.2 is complete** — the pinned three-node kind proof placed one API
and one web replica on each worker, honored `minAvailable: 1` during a worker drain, showed
topology-constrained replacements Pending, recovered after uncordoning, and tore down cleanly.
P11.3 and its required teardown are complete. P11.4 is not started. Before any node-loss drill,
the owner must activate a new bounded AWS session with an independent alarm. No temporary AWS
resources are live; only the persistent allowlist remains.

Mark whichever task you start `IN PROGRESS` in `docs/PROGRESS.md` before changing anything,
same as every prior phase. Land each task via its own feature branch + PR (not a direct
commit to `main`) — every P0–P10 commit in `git log` follows this pattern; CI (API tests,
web lint/test/build, Terraform/Helm validation, container build+scan) must be green before
merging.

Two real local-environment findings from P10.2 that a fresh kind cluster will need again:
kindnet doesn't enforce `NetworkPolicy` (Calico is now required — see `k8s/kind-config.yaml`
and `docs/local-tooling.md`'s "NetworkPolicy-enforcing kind cluster" section for the exact
recipe and two host-specific fixes). The kind cluster `bedoux` is currently left running,
Calico-backed, with `networkPolicy.enabled=true` from the P10.2 drill — check its state before
assuming a clean starting point.

## Skills and smaller-model subagents
Repository documents remain canonical; a skill is a thin workflow wrapper, never a replacement
for `AGENTS.md`, `docs/PROGRESS.md`, an accepted ADR, or a runbook. At the start of each task,
inspect the skills actually available in that agent host. When a matching skill exists, announce
it, read its complete `SKILL.md`, and follow it. Do not claim that a proposed repository skill is
installed merely because it was discussed. Good shared repository-skill candidates for the
repeated work here are phase/checkpoint orchestration, AWS session + teardown guardrails,
Kubernetes drill/evidence capture, IAM least-privilege review, CI evidence verification, and
progress-ledger closeout.

Codex may delegate bounded side work to smaller-model subagents when that reduces wall-clock time.
Prefer `gpt-5.6-luna` (when available) for isolated, reversible work such as manifest inventory,
test scaffolding, YAML/static validation, evidence extraction, or documentation comparison; use a
larger model only when the subtask genuinely needs it. The primary agent keeps the immediate
critical path and all architecture, IAM interpretation, AWS authorization/mutation, phase-state,
gate, teardown, and final-evidence decisions.

Subagent rules for this repository:

- Give each subagent one concrete output and a disjoint read/write scope; never duplicate the
  primary agent's active work.
- Subagents must not mutate AWS, edit `docs/PROGRESS.md`, create/supersede ADRs, approve gates,
  merge branches, or make teardown decisions. Owner authorization and the AWS-session runbook
  remain with the primary agent and cannot be delegated.
- Require changed file paths, commands/tests run, results, assumptions, and unresolved risks in
  every subagent return. Narrative confidence is not evidence.
- Review every subagent patch and rerun relevant verification in the primary workspace before
  recording evidence or checking off a task. Close completed agents instead of leaving them idle.
- Skip delegation for a simple serial task or when the result blocks the very next action; the
  primary agent should keep those tasks on the critical path.

For P11.1, a good split is: the primary agent marks P11.1 `IN PROGRESS`, owns chart design and the
live kind proof; one Luna subagent can inventory current chart resources/values and test coverage,
and a separate bounded review subagent can check the finished diff and evidence gaps while the
primary runs the local drill. Do not let either subagent update the authoritative progress ledger.

Every P10-P14 AWS-costing item stays session-based with same-day teardown per
`docs/cost-guardrails.md` — nothing runs continuously. `docs/cost-guardrails.md` flatly
prohibits unbounded autoscaling and routine Multi-AZ RDS (ADR 0014 explains how P10-P14 reads
those limits); a Route 53 hosted zone is deferred to P12 pending an explicit owner decision on
buying a domain vs. using a subdomain vs. skipping live deployment — do not assume an answer.

Use `$aws-session-guardrail` when it is available, then manually walk the canonical "Before the
session" checklist in `docs/runbooks/aws-session.md` and its teardown sweep. The skill grants no
AWS authority. Never create AWS resources outside that process. Only after the owner has explicitly
approved a phase gate, record that approval as its own commit ("Phase N gate approved by owner;
activate Phase N+1") before starting the next phase's work. The Terraform VPC must keep NAT
disabled.
```
