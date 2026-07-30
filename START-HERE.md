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
  needed; policy is now at v3, all fixes console-applied by the owner and
  verified live. **P5.2 complete**: ECR repos `bedoux-api`/`bedoux-web` created,
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
- Active phase: **P6 — Terraform, then CI/CD; P6.1 and P6.2 are complete.**
- Next action: **P6.3** — GitHub OIDC role + PR pipeline. P6.2 recreated the EKS
  learning environment as Terraform, verified Kubernetes access plus the EBS CSI add-on,
  then destroyed it in the same session. The Terraform VPC has NAT disabled from the
  start. No billable AWS resources are currently live (see `docs/PROGRESS.md`'s Overall
  status table — confirmed by the full teardown sweep, not assumed).
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
