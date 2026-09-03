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
  teardown. **P10 gate approved 2026-08-11; P11 gate approved 2026-08-20; P12 gate approved
  2026-08-26; P13 is active.** ADR 0022 records the owner's
  `bedoux.ca` apex cutover and Shopify-retirement choice. PR #53 merged the opt-in HTTPS,
  redirect, and staged-alias path to `main` as `775dfe1`. The bounded live session passed T-1202
  through trusted apex/`www` HTTPS, HTTP 301 redirects, and a real Chrome catalog render; T-1203
  passed after removing aliases and every temporary ALB/EKS/VPC resource while retaining only
  the approved zone/certificate allowlist. PR #54 passed all four checks and merged the P12
  completion/gate evidence as `386f66e`; merged P12 branches are cleaned locally/remotely.
  **P13.1 and T-1301 are COMPLETE as of 2026-08-29.** ADR 0023 keeps progressive delivery in
  one Helm release and uses controller-native ALB weighting, exact-image gates, target-health
  reconciliation, injected ALB pod-readiness, and a 30-second target deregistration bound. The
  local kind rehearsal passed first. PR #55 merged the implementation and node-tagging repair as
  `5bbf959`. The first live run then failed closed before staging on ALB's valid single-target
  relative-weight normalization; no canary object was created. Focused PR #56 exact head
  `5b48f81` passed run `33278575055` and merged the fail-closed normalization fix as `6884797`.
  Separately authorized T-1301 run `33278906766` on that exact `main` revision passed exact 90/10
  staging, two healthy target groups, 20/20 direct checks, 100/100 public checks with 13 correlated
  canary hits, reconciled 100/0 promotion before drain, healthy pod readiness, stable-only cleanup,
  and final public health/catalog smoke. The final immutable API/web candidate digests matched the
  deployed stable workloads, and no canary Deployment, Service, Ingress, or TargetGroupBinding
  remained. Ordered teardown deleted the Ingress/ALB first, then Kubernetes prerequisites and the
  exact owner-approved 18-resource Terraform destroy plan. The temporary cluster OIDC provider
  was deleted, the repeated authoritative sweep returned zero temporary resources, and exact
  T-1301 files were removed from `/tmp`. Budget actual was USD 6.002 and forecast USD 6.239 of
  USD 20. Only the approved persistent allowlist remains. PR #57 merged the closeout as
  `c815eca`; **the owner activated P13.2 on 2026-08-30, and T-1302 is now `IN PROGRESS`.** Its
  disabled-by-default canary-only HTTP-error injection, attributed gate-block semantics, exact
  stable-image rollback assertion, workflow input, fail-closed mocks, and bounded runbook are
  implemented locally. The first independent review found a false-positive evidence path; local
  fix `f6b113a` now reserves status 20 for access-log-correlated HTTP errors after prerequisites
  pass and denies T-1302 evidence for unrelated failures. Independent review accepted that fix;
  follow-up `0b9bcee` also requires exactly one structured attribution marker with status 20 and
  improves ordinary-rollout diagnostics. The separately authorized real local drill then passed:
  both canaries were Ready, all 20 injected API samples produced correlated HTTP 404s, attributed
  status 20 blocked promotion, exact stable images were restored automatically, all canary
  objects disappeared, and stable health/catalog passed. This is local-first evidence only; live
  T-1302 remains pending because the project requires the AWS ALB public-error path in addition to
  the generic local contract. Independent technical review accepted exact PR head `f69e680`;
  documentation-only exact head `107c019` passed all four jobs in run `33342279143` and merged
  through owner-approved PR #58 as exact `main` SHA `263fb125`. No canary dispatch has run. The
  separately authorized AWS preflight is now clean, persistent
  state is reconciled, and exact plan
  `ee48a1bd7a110bf66b1f570ee1dd50b1b98bbcbeb0db7dbcd156782ccfb7567f` applied unchanged with
  28 added, 11 changed, and zero destroyed. Operator bootstrap and older-main baseline run
  `33344400481` passed on exact main SHA `c815ecac`; EKS 1.34, both pinned add-ons, the one Ready
  Spot `t3.medium` node at `1/1/1`, initial worker/root-volume tags, propagated ASG tags, API/web,
  PostgreSQL, ALB, and the replacement web pod's injected True ALB readiness gate all pass.
  No canary object exists. Ordered teardown removed Ingress/ALB/TGs, application, namespace/PVC,
  controller, and `gp3`; the owner-approved temporary-only plan then applied unchanged with
  18 destroyed and no create/update action. The captured temporary cluster OIDC provider is
  absent, the full authoritative inventory sweep is clean, and only the approved persistent
  allowlist remains. No regression workflow was dispatched, so T-1302 remains incomplete. The
  P13.2 runbook now has a post-merge fresh-retry checklist: five-hour alarm, 75-minute teardown
  reserve, minimum time-to-apply/dispatch gates, fresh temporary artifacts, explicit context,
  TargetGroupBinding-aware readiness restart, early direct ALB verification, and authoritative
  EC2 reconciliation for stale tagging-index results. The retry baseline uses exact merged
  `main`, not the obsolete older-main/unmerged-PR path. Fresh 2026-08-31 preflight and guarded
  state reconciliation passed. The owner-approved create plan established the intended no-NAT
  EKS/VPC/one-Spot-node baseline, but capped output streaming returned before Terraform's summary,
  leaving a stale lock and three already-live tail objects untracked. The lock is safely cleared,
  state is reconciled. The owner-approved one-update recovery binary then failed closed as stale
  before provider mutation because remote state had advanced; it was not retried. Fresh exact
  mode-0600 plan SHA-256 `2685ba0ef277c6b78a533e6a07cc9bb7f73e170a9b5c58335996ffaeee75ef91`
  is a true 0-create/update/delete/replace no-op. Live AWS and state confirm pinned EBS CSI is
  `ACTIVE`, healthy, tagged, and carries both reviewed conflict settings, so no Terraform apply
  remains. Authorized exact-main stable run `33415367340` then passed on SHA `263fb125`: signed
  digest-pinned API/web, seeded six-product catalog, stable-only `web=100`, one healthy target,
  and the once-restarted web pod's injected `True` ALB readiness gate all pass. The ordinary
  baseline retains AWS's 300-second deregistration default; no unapproved normalization occurred.
  Authorized regression run `33417072276` then failed closed before Helm mutation because rebuilding
  the same exact post-merge SHA produced candidate digests equal to stable. Stable public health,
  six-product catalog, and readiness remain good; no canary object exists and T-1302 is not
  claimed. Local fix `acf2ccd` permits equal references only for the explicit configuration-error
  drill while retaining ordinary-canary refusal, with both paths mocked. Independent technical
  review accepted the exact fix. PR #59 exact head `eb337786` passed all four jobs in run
  `33434986130` and merged to `main` as `587f4458c172e2474b31937b098fbb4f1375db75`.
  The revised 14:00 dispatch boundary has passed, so no regression retry may run
  today. Authorized ordered teardown removed the Ingress/ALB/target groups, application,
  namespace/PVC, controller, and `gp3`. The owner-approved exact 18-delete plan then converged
  despite its execution transport ending before a final summary: no stale-plan reuse occurred,
  fresh Terraform refresh is a true no-op, exact cluster OIDC is absent, the authoritative sweep
  reports zero temporary resources, and all exact session files are removed. Only the approved
  persistent allowlist remains. T-1302 is not claimed. Local commit `012cdc6` now hardens private
  file modes, accepts Terraform's null no-op representation, adds credential-free regression
  tests to PR validation, and makes retained resumable process/session polling the canonical
  long-mutation contract. Independent review accepted exact `012cdc6`; focused draft PR #60 now
  carried that behavior at exact head `dc6c64ad5df634b426c720ed578124a5f0afed93`, with all four
  jobs green in run `33441994664`. Independent review accepted the exact PR head and its
  contextual runbook placement; it merged to `main` as
  `69162e37d906404421d936cbd366edfdddb7e31d`. A fresh alarmed AWS retry remains separately gated.
  The
  retained Calico-backed kind node is stopped with its PVC preserved and
  the host inotify value restored to 128. The default kubeconfig context still points at a deleted
  EKS endpoint, so always use an explicit context.
- **P13.2/T-1302 closeout 2026-09-01:** the owner-authorized retry from exact merged `main`
  SHA `69162e37d906404421d936cbd366edfdddb7e31d` passed the live public/direct injected-error
  gates, exact 90/10 staging, reconciled 100/0 promotion, stable-only rollback, canary cleanup,
  and final health/catalog smoke in workflow run `33538736864`. The first attempt had failed on a
  real Spot/AZ-bound PVC placement issue; recovery temporarily added a second Spot worker in the
  volume's AZ without deleting the PVC. Ordered teardown then removed the Ingress/ALB, application,
  namespace/PVC, controller, `gp3`, EKS, node group, and VPC. The owner-approved destroy plan
  reported 18 destroyed, 0 added, and 0 changed; the temporary cluster OIDC provider is absent.
  Final AWS inventory and `/tmp` cleanup are clean. P13.2 and T-1302 are complete. The owner
  approved the P13 gate and activated P14 on 2026-09-01. **P14.1/T-1401 is complete locally:**
  real P11 Metrics Server samples justify raising only the API CPU limit from 250m to 500m;
  requests and values without retained measurements remain unchanged. Focused PR #61 exact head
  `3f547a1` passed all four jobs in run `33559670780` and merged as `fd4cabb`. P14.2/T-1402 is
  complete at focused commit `bdc5b1e` through merged PR #62 (`758a087`): the live wildcard ECR
  lifecycle rule retained a real bare commit-SHA push in both repositories, and twelve older
  tagged images per repository were marked for expiration in lifecycle previews. P14.3 is complete
  locally at focused commit `0edafc9` from merged P14.2: same-shape `t3.medium`/`t3a.medium` Spot
  pools preserve the one-node and two-node HA ceilings; the review also records EKS Capacity
  Rebalancing, ordinary-profile 30-second/no-preStop shutdown behavior, and ADR 0019's explicit
  AWS-HA exception. All five Terraform tests pass. Exact head `0edafc9` passed all four jobs in
  run `33584953985` and merged through PR #63 as `aed6f5d`. Checkpoint reconciliation `f012225`
  retains the ECR, tagging, and Spot test wiring so P14.4 cannot repeat the stale-base conflict.
  **P14.4/T-1403 is complete locally at focused commit `511bf24`:** bounded read-only billing
  evidence puts the conservative P10–P13 calendar envelope at USD 4.939738 in positive usage,
  with final August whole-account usage at USD 8.373571 (41.9% of the USD 20 cap) and September
  through day one at USD 0.501845 estimated. The indexed report records phase windows, service
  drivers, credits, and daily-attribution limitations; its CI-wired arithmetic test rejects an
  inflated fixture. Exact head `511bf24` passed all four jobs in run `33652892894` and merged
  through PR #64 as `a8e9276`; checkpoint reconciliation `fab61a6` contains that merge.
  **P14.5/T-1404 is complete locally at focused commit `e165332`:** the 1,289-word walkthrough
  now incorporates P10–P14 evidence and remains within 15 minutes; a seventh optimization-track
  diagram plus refreshed system/request/CI-CD pairs are editable and exported; the semantic timing
  guard and `make docs-check` pass. Independent review accepted the exact focused commit after
  reproducing its timing, fail-sensitive checks, evidence traceability, and visual inspection.
  Exact commit `e165332` passed all four jobs in run `33681885076` and merged through PR #65 as
  `80cd24c`; checkpoint reconciliation `4286baa` contains that merge. The owner approved the P14
  gate on 2026-09-02 and closed the P10–P14 optimization track. No later phase is active.
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
  gate on 2026-08-20. All P12.1–P12.3 tasks and T-1201–T-1203 tests are now complete.** The owner
  selected the `bedoux.ca` apex, retired Shopify, and approved hosted-zone persistence through
  ADR 0022. The delegated zone, two validation records, and issued certificate remain. The live
  P12.2 session proved trusted HTTPS and redirects for both names plus a real browser catalog,
  then removed both aliases before the ALB/application/EKS/VPC teardown. The 2026-08-26 final
  sweep found no temporary resource or dangling alias; budget actual was USD 5.384 of USD 20.
  Only the approved persistent allowlist remains. The owner approved the P12 gate on 2026-08-26,
  activating P13; PR #54 merged the focused checkpoint as `386f66e`. P13.1/T-1301,
  P13.2/T-1302, P14.1/T-1401, P14.2/T-1402, P14.3, and P14.4/T-1403 are complete locally. The P14.2
  implementation is at `bdc5b1e` through merged PR #62 (`758a087`); focused P14.3 commit
  `0edafc9` merged through PR #63 as `aed6f5d`; focused P14.4 commit `511bf24` merged through
  PR #64 as `a8e9276`. P14.5/T-1404 exact head `e165332` passed all four jobs and merged through
  PR #65 as `80cd24c`. All P14 tasks and tests are complete and merged; the owner approved the
  P14 gate and explicitly declined activation of an unplanned phase.
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
