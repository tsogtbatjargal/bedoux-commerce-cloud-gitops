# Start Here

This file is the entry point for a new Claude Code, Codex, OpenClaw, or human session.

## First five actions

1. Read `AGENTS.md` completely.
2. Read `docs/PROGRESS.md` completely. It is the authoritative checkpoint.
3. Read the active phase in `docs/IMPLEMENTATION-PLAN.md`.
4. Read only the architecture, decision, test, or runbook sections referenced by that phase.
5. Before changing anything, verify the last completed checkpoint using the commands recorded
   in `docs/PROGRESS.md`.

Do not infer progress from files merely existing. A task is complete only when its checkbox is
checked in `docs/PROGRESS.md` and its evidence is recorded in the session log.

## Current checkpoint

- Project state: **Phase 0 complete (gate approved 2026-07-18). Phase 1 complete (gate
  approved 2026-07-18). Phase 2 (local app slice on Compose: FastAPI + Postgres + React,
  full image scans) complete — P2 gate approved 2026-07-19.** The rootless-Podman/kind
  cgroup gap is fixed and verified (real cluster create/delete), and the full golden
  path was driven in a real Chrome browser via Playwright MCP with the resulting order
  confirmed in Postgres — see `docs/local-tooling.md` and `docs/PROGRESS.md`'s
  2026-07-19 session log entries. **P3.1 complete**: kind cluster `bedoux` is up with
  plain manifests (`k8s/`) for postgres/api/web, verified via `curl` and a real browser
  through the NodePort. **P3.2 complete**: readiness/liveness probes, resource
  requests/limits, and a Secret-vs-ConfigMap split by whether config embeds a
  credential; the exact race hit in P3.1 is now architecturally prevented by an
  init container on the api Deployment, proven with a real drill (scaled postgres to 0,
  restarted api, watched it correctly block instead of racing, then recover cleanly).
  **P3.3 complete**: ingress-nginx (`controller-v1.15.1`) routes `/` to web and `/api`
  (prefix-stripped) directly to api — the same shape P5's ALB Ingress will use, not a
  kind-only workaround. **P3.4 complete**: `charts/bedoux/` Helm chart per ADR 0005
  (`post-install,pre-upgrade` migration hook — corrected same-day from an initial
  `pre-install` design that would have failed every fresh install, caught by live
  testing before it ran for real). Proven against the live cluster: install, upgrade,
  a deliberately broken upgrade that failed safely without touching the running app,
  and a real `helm rollback` with all data intact. `charts/bedoux/` is now the live
  deployment artifact; `k8s/*.yaml` stays only as the P3.1–P3.3 historical record.
  **P3.5 complete**: scale (verified real load-balancing across new pods), zero-downtime
  pod deletion (20/20 requests succeeded mid-deletion), a broken-config incident
  diagnosed purely from `kubectl` output, and a clean rollback — all against the live
  cluster, plus two real operational findings (ConfigMap fixes need a manual rollout
  restart; plain `helm upgrade` silently reuses previous values unless
  `--reset-values` is passed). Cluster is left running.
  **P4.1 + P4.3 complete**: root MFA enabled, root has zero access keys; working
  identity is non-root IAM user `bedoux-admin` (`PowerUserAccess` + a small IAM policy
  scoped to `bedoux-*`-named resources, not `AdministratorAccess`), used via
  `--profile bedoux-admin` on every AWS command from here on
  (`docs/local-tooling.md`'s "AWS CLI identity" section). Region pinned:
  **`ca-central-1`**. **P4.2 complete**: USD 20 monthly cost budget (80%/100% alerts)
  + Cost Anomaly Detection both live in the console. **P4.4 complete**: full
  `/aws-session-start` + `/aws-teardown-verify` sweep run for real against the account
  — completely empty, confirming both slash commands actually work. Found and fixed
  two real gaps: a Cost Explorer data-availability caveat added to the runbook, and
  `docs/HANDOFF.md` (which had gone stale since 2026-07-18) fully regenerated.
  **P5 pre-work complete 2026-07-23**: both pending decisions (#3, #4) implemented
  and live-verified before any billable AWS resource — ADR 0006 (Spot risk + gp3
  StorageClass chart support) and the order-write kill switch + request bounds
  (proven against kind, including a real-browser check). **P5.1 complete
  2026-07-28**: real `eksctl` EKS cluster `bedoux` (control plane + 1 Spot
  `t3.medium` node), OIDC provider, and the EBS CSI driver add-on with its own
  IRSA role — gp3 dynamic provisioning proven with an actual EBS volume (write,
  read back, cross-confirmed via `aws ec2 describe-volumes`, cleaned up). Along
  the way, found and fixed (via **ADR 0007**) a real self-escalation hole in
  `bedoux-admin`'s scoped IAM policy (`bedoux-iam-scoped` — it could rewrite its
  own constraining policy) plus the narrow IAM grants `eksctl`/IRSA actually
  needed; that P5 fix was v3, all changes were console-applied by the owner and
  verified live. P10.4 later superseded the complete-closure claim via ADR 0015
  and owner-applied v4. **P5.2 complete**: ECR repos `bedoux-api`/`bedoux-web` created,
  `p5` images pushed and confirmed present. **P5.3 complete**: AWS Load Balancer
  Controller live via its own IRSA role; found ALB has no path-rewrite
  annotation (fixed via **ADR 0008** — the AWS profile routes everything
  through `web`, whose own nginx already proxies `/api` internally); real app
  deployed with real ECR images, reachable via the ALB DNS name, golden-path
  order confirmed in Postgres. **P5.4 complete**: request traced ALB→web→api
  with a correlated marker in both pods' logs; a deliberate `web` scale-to-0
  breakage was diagnosed purely from `kubectl`/AWS CLI output (empty
  Endpoints, draining ALB target) and fixed, full recovery confirmed.
  **P5.5 complete**: full teardown in the correct order (app → ALB controller
  → cluster), `/aws-teardown-verify` sweep clean. One real finding: the
  session had an **undisclosed NAT Gateway** the whole time —
  `k8s/eksctl-cluster.yaml` never set `vpc.nat.gateway: Disable`, so eksctl's
  default silently violated the project's explicit no-NAT rule (cost was
  trivial, ~USD 0.07, but the rule was broken undetected until teardown
  caught it via the tagging-API sweep). Fixed for future sessions. ECR repos
  and the session's IAM roles/policies were kept (not deleted), per
  `docs/cost-guardrails.md`'s persistent-resource allowlist. **P5 phase
  fully complete — gate approved 2026-07-29; P6 active.**
- **P6 is fully complete — gate approved by owner 2026-08-01; P7 is active.** P6.3 declared the
  GitHub OIDC deployment role, established green PR validation (API/PostgreSQL, web,
  Terraform/Helm, and image scan), and installed a tested local direct-`main` push guardrail.
  GitHub's current private-repository plan cannot enforce server-side rulesets; ADR 0010 records
  that transparent compensating control and its limits.
- **P6.4 complete 2026-07-31:** main-branch CI obtained the narrowly scoped GitHub OIDC role,
  pushed immutable ECR images, deployed the AWS Helm profile with namespace-only access, and
  passed a public ALB health/catalog smoke. **P6.5 complete 2026-07-31:** green baseline run
  `30685274638` and controlled run `30685420148` proved CI's deliberate Helm failure, atomic
  rollback to the captured pre-drill image, and public health verification (T-602). The corrected
  teardown helper prepared persistent state before its 14-resource temporary-only destroy plan;
  the final sweep was clean. No temporary billed AWS resources are live.
- **P7.1 is complete — T-701 passed 2026-08-01.** A fresh short-lived no-NAT RDS session passed
  GitHub Actions run `30727844150` (migration, seed, API/web rollout, and public catalog), then
  used the bounded verifier to create and read back one synthetic public order. A direct API
  workload query confirmed exactly one RDS-backed order row and the kill switch was restored to
  disabled. Teardown began ahead of the independently alarmed deadline and the final sweep was
  clean; no temporary AWS resources are live. **P7.2 is complete — T-702 passed
  2026-08-02:** GitHub Actions run `30761203972` proved S3-backed `image_url` responses and its
  masked direct-image smoke; an API-pod STS assertion proved the scoped image-read IRSA role.
  The temporary S3/IRSA/RDS/EKS session was torn down cleanly, including the image bucket and its
  six synthetic objects. **P7.3 and P7.4 are complete:** the Secrets Manager/IRSA proof passed,
  and the RDS deletion/backup policy plus T-703 same-day teardown evidence are recorded in
  `docs/PROGRESS.md`. No temporary AWS resources are live. **P7's gate is approved and P8 is
  active. P8.1 is complete:** the API emits safe structured JSON completion logs with request-ID
  propagation, proven in the pinned local runtime and a real local container. **P8.2 is complete
  (2026-08-05):** a time-bounded no-NAT session proved temporary three-day Container Insights
  logging (including the add-on-created `performance` group), the IRSA-restricted collector,
  structured application-log delivery, dashboard, and four notification-free alarms, all `OK`.
  The owner deferred P8.3 once already on 2026-08-05; a first 2026-08-06 attempt hit a real,
  previously-undiscovered Alembic `%`-interpolation bug and separately overran its deadline by
  ~3 hours (recorded honestly in `docs/PROGRESS.md`), was fixed, proven locally, and merged.
  **P8.3 is now complete (2026-08-07).** This session applied the lesson directly: an actual
  enforced background alarm (not just intent) was armed at session start. All four drills —
  unhealthy ALB target, failed pod (CrashLoopBackOff), DB connection error (RDS security-group
  revocation), and failed rollout (Helm `--atomic`) — were induced, diagnosed purely from tooling
  output, fixed, and recovered, each with independently-confirmed evidence. Full teardown
  completed roughly 2h50m under deadline; independent sweep confirmed clean. No AWS resources
  are currently live. **P8.4 is complete:** `docs/runbooks/p8-troubleshooting.md` documents all
  four drills as symptom → diagnose → root cause → fix → recovery check, written directly from
  the commands proven live that same session — not generic guidance. **P8 gate approved by
  owner 2026-08-07; P9 (interview package) is active.** **P9.1 is complete:**
  `docs/interview/walkthrough-script.md` is a timed 15-minute script grounded entirely in real
  recorded evidence (ADR 0007's IAM self-escalation fix, ADR 0008's ALB no-rewrite finding, the
  four P8.3 drills, both deadline-overrun incidents) — no hypothetical capability described.
  **P9.2 is complete:** all six diagrams exist and are exported to sibling SVGs — the two
  existing (`system-context`, `learning-path`) plus four new (`request-path`, `ci-cd`,
  `vpc-network`, `identity`), each grounded in real facts, not invented. **P9.3 is complete:**
  measured word-count timing showed the script fits 15:00 at every realistic pace (14:19 at the
  slowest tested) with no cuts needed — correcting an earlier unmeasured guess. **P9 gate
  approved by owner 2026-08-07. All phases P0–P9 are complete — this is the project's final
  milestone.** Per the owner's explicit decision, the repository **remains private**; ADR 0004's
  "flip public before P9" clause is superseded by
  [ADR 0013](docs/decisions/0013-remain-private-at-p9.md).
- **P10–P14 optimization track bootstrapped 2026-08-09** (owner request: optimize/improve the
  prototype — reliability/HA, security hardening, delivery maturity, performance/cost).
  [ADR 0014](docs/decisions/0014-post-p9-optimization-track-scope.md) records the track's
  scope and how it reads `docs/cost-guardrails.md`'s hard limits (bounded autoscaling only,
  Multi-AZ RDS as a one-off reviewed exception, Route 53 gated on an explicit owner domain
  decision at P12). Full phase table in `docs/IMPLEMENTATION-PLAN.md`'s "Phase 10+" section;
  checklist in `docs/PROGRESS.md`. **P10.1 is complete:** the current API/web image re-scan is
  recorded, with no currently fixable API base-image CVE. **P10.2 is complete:** default-deny and
  explicit-allow NetworkPolicies were proven on the retained Calico-backed kind cluster.
  **P10.3 is complete:** green PR CI generated and validated API/web SPDX artifacts and signed and
  verified both immutable candidate digests without OIDC or AWS access; the main deployment path
  keylessly signs, exact-identity verifies before Helm, and deploys the verified digest.
  **P10.4 is complete:** ADR 0015's permissions boundary, `bedoux-iam-scoped` v4, replacement
  workload identities, and bounded deny test were proven live. **P10.5 is complete:** the EKS VPC
  CNI enforced the NetworkPolicies in a real allow/deny drill, followed by a clean same-session
  teardown. **P10 gate approved 2026-08-11; P11 gate approved 2026-08-20; P12 is active.**
  ADR 0022 records the owner's `bedoux.ca` apex cutover and Shopify-retirement choice. PR #50
  merged the reviewed module as `b08f197`; P12.1 live evidence continues on the local
  `p12-1-live-route53-acm` branch. The Calico-backed kind cluster is
  still running and Ready, but the default kubeconfig context points at the deleted EKS endpoint;
  use or switch deliberately to `kind-bedoux`.
- Repository workflow skills are validated and published on `main` through merged PR #47
  (`874305c`); P11.1 is complete with T-1101 evidence and P11.2 is complete with local
  PDB/topology evidence.
- P11.3 is complete on `p11-3-live-scaleout`: the live k6 proof reached the hard 3-replica HPA
  cap with 0% request failures, and the guarded same-session teardown swept all temporary AWS
  resources clean. ADR 0016 records the owner-applied policy v6 PassRole reconciliation. The
  initial Spot placement exposed a real same-AZ/minDomains finding; P11.4 was assigned the
  node-loss drill and follow-up topology decision.
- The first P11.4 live T-1103 attempt on 2026-08-18 proved two AZ-pinned nodes, safe
  non-PostgreSQL drain, one-AZ stateless recovery, and restored cross-AZ placement, but failed
  the hard traffic gate: 115 of 30,265 requests failed. ADR 0018 records the live Kubernetes
  1.34 finding that `minDomains` is invalid with `ScheduleAnyway`. That session and its later
  owner-approved orphan-volume cleanup both closed with a clean inventory.
- Accepted ADR 0019 addresses the evidence-supported ALB/pod termination gap with an AWS-HA-only
  30-second target deregistration bound, 45-second preStop hold, 60-second grace period, and
  deterministic AWS target-health readiness gates. Static renders, fail-closed guard mocks, and
  pinned k6 p99/failure diagnostics pass. The fresh 2026-08-20 local drill also passed: the
  non-PostgreSQL worker drained in 48.39 seconds under five minutes of pinned traffic, with
  19,011/19,011 successful requests, p95 670.56 ms, p99 807.89 ms, stateless one-worker recovery,
  PostgreSQL untouched, and restored two-worker placement. The recovery helper was hardened after
  the drill showed that terminating pods can create a transient false spread result. The exact
  cluster and temporary files are gone, and the owner restored the transient host inotify limit
  to its original 128. Local closeout is clean.
- **P11.4 and T-1103 are complete as of 2026-08-20.** The fresh reviewed AWS retry drained the
  safe stateless AZ node in 73.72 seconds during pinned five-minute k6 traffic. All
  33,507/33,507 requests succeeded with 0 failures; average latency was 78.24 ms, p95 155.35 ms,
  p99 453.29 ms, and maximum 1.25 s. PostgreSQL remained untouched, stateless workloads recovered
  in the surviving AZ, and the helper restored Ready cross-AZ placement. Public health/catalog
  and both target-health checks passed after recovery. The Ingress/ALB, Kubernetes prerequisites,
  16 Terraform-managed temporary resources, and exact cluster OIDC provider were removed; the
  final AWS sweep and local temporary-file/process sweep were clean. Budget actual remained
  USD 4.552 of USD 20; estimated session cost is below USD 0.30 pending billing ingestion.
- **All P11.1–P11.5 tasks and T-1101–T-1104 tests are complete, and the owner approved the P11
  gate on 2026-08-20. P12 is active.** The owner selected the `bedoux.ca` apex and retired
  Shopify; ADR 0022 supersedes ADR 0021 and satisfies ADR 0014's owned-domain path. P12.1's
  disabled-by-default Route 53/ACM module and two-stage live runbook first create the apex zone,
  then replace the registrar nameservers before validating a certificate for the apex and `www`.
  The in-house ALB aliases arrive in P12.2, so the Shopify cutover creates an accepted temporary
  no-site window. The owner approved hosted-zone persistence on 2026-08-24. The tagged public
  zone is live and the `.ca` parent plus four independent resolvers now return exactly its four
  Route 53 nameservers. The prior alarmed session is closed cleanly; T-1201 still requires a
  fresh alarmed session and an `ISSUED` ACM certificate for the apex and `www`.
- Safe stopping point: after any single task with its evidence recorded in `docs/PROGRESS.md`.
- Standing gate: `make docs-check` must pass before any commit that touches docs or diagrams.

## Non-negotiable boundaries

- Hard AWS budget cap: **USD 20 per month.** Stop conditions in
  `docs/runbooks/aws-session.md` override any task in progress.
- **No AWS resource is created or modified outside a session opened via
  `docs/runbooks/aws-session.md`.** Same-day teardown is the default.
- After every AWS session the resource inventory must be verified empty except for the
  persistent-resource allowlist in `docs/cost-guardrails.md`.
- No secrets, tokens, private keys, AWS account IDs, or personal email addresses in this
  repo, its history, logs, or evidence.
- The AWS region is pinned once chosen (recorded in `docs/PROGRESS.md` known facts); never
  infer it from a console URL.
- Every milestone is demonstrated locally (Compose or kind) before it is attempted in AWS.
- Never claim production traits (traffic, uptime, customers) the system has not had.

## Resume protocol after a disconnect

1. Run `git status --short` and `git log --oneline -5`.
2. Inspect the latest entry in `docs/PROGRESS.md`.
3. Re-run the latest recorded verification command.
4. If AWS work was possibly in flight: run the read-only leftover sweep from
   `docs/runbooks/aws-session.md` (or `/aws-teardown-verify`) before anything else —
   an orphaned cluster costs money every hour.
5. If verification disagrees with the progress log, stop and record the discrepancy. Do not
   advance the phase.
6. Continue only the single item marked `IN PROGRESS`.
7. Before stopping, update the checklist and append a dated session entry, even if work failed.

## Definition of a useful session log entry

Record:

- date/time and agent/operator name;
- phase and task ID;
- files or systems changed;
- commands/tests run and their result;
- **AWS resources created and destroyed this session, and the estimated session cost**
  (write `AWS: none` when the session never touched AWS);
- decisions made, without including secrets;
- exact next action;
- blockers and safe rollback, if applicable.
