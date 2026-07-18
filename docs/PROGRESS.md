# Progress

This file is the **only authoritative execution state** for bedoux-commerce-cloud.
Do not infer progress from files existing. A task is complete only when its checkbox is
checked here and its evidence is recorded in the session log.

## Overall status

| Field | Value |
|---|---|
| State | IN PROGRESS |
| Active phase | P1 — Local tooling |
| Active task | P1 gate — awaiting owner approval to activate P2 |
| Last verified | 2026-07-18 — T-011 `make tools-check` all-green from a plain host shell |
| AWS resources currently live | **NONE** (no AWS account activity yet; no AWS account contacted) |
| Month-to-date estimated AWS spend | USD 0 |
| Next operator action | approve the P1 gate, or review the P3 rootless-Podman gap noted below |

Allowed states: `NOT STARTED` / `IN PROGRESS` / `BLOCKED` / `COMPLETE`.

## Known facts

- AWS region: **not pinned yet** (pinned in P4.3; recorded here when chosen).
- AWS account: none configured on this workstation yet; `/aws-*` commands must refuse.
- GitHub: `bedoux-tech/bedoux-commerce-cloud`, **private** until a pre-P9 history sweep
  (ADR 0004); `tsogtbatjargal` pushes over SSH from the workstation; the `bedoux-tech` gh
  auth lives on bedoux-vm (openclaw user).
- Standard tags for every AWS resource: `project=bedoux-commerce-cloud`, `environment=learning`.

## Phase checklist

### P0 — Bootstrap

- [x] P0.1 COMPLETE — doc spine created (START-HERE, AGENTS, CLAUDE shim, PROGRESS,
      IMPLEMENTATION-PLAN merge, TEST-PLAN, HANDOFF); `project-plan.md` +
      `learning-roadmap.md` merged and removed. Evidence: session log 2026-07-17; T-001.
- [x] P0.2 COMPLETE — ADR index + 0002 (MVP deferrals) + 0003 (repo hosting) created;
      0001 flipped to Accepted. Evidence: `docs/decisions/README.md` status table.
- [x] P0.3 COMPLETE — README banner + doc index, architecture MVP-vs-production table,
      aws-session closeout section, Makefile docs-check extension. Evidence: T-001 run.
- [x] P0.4 COMPLETE — `.claude/settings.json` read-only allowlist + `/catchup`,
      `/aws-session-start`, `/aws-teardown-verify`, `/closeout` commands. Evidence: T-006.
- [x] P0.5 COMPLETE — diagrams revised (system-context deferral styling, learning-path
      → P0–P9) and exported to SVG via podman `rlespinasse/drawio-export`. Evidence:
      `make docs-check` OK 2026-07-18; visual self-check of PNG previews passed.
- [x] P0.6 COMPLETE — GitHub repo `bedoux-tech/bedoux-commerce-cloud` created **private**
      (ADR 0004) from bedoux-vm's gh, `tsogtbatjargal` added as push collaborator, `main`
      pushed from the workstation. Evidence: T-002 — `git remote -v` shows origin;
      push output `* [new branch] main -> main`; session log 2026-07-18.

**P0 gate approved by owner 2026-07-18** (evidence: T-001..T-006 above; gate commit in git log).

### P1 — Local tooling

- [x] P1.1 COMPLETE — aws/kubectl/eksctl/kind/helm/terraform installed as static binaries
      to host `~/.local/bin` (Silverblue-clean, no rpm-ostree layering); `make` (+ podman
      package for presence-check parity) installed via dnf in the pre-existing `bedoux-aws`
      toolbox; `~/.local/bin/make` wrapper makes `make <target>` work transparently from a
      host shell. Evidence: T-011 — `make tools-check` → "All project prerequisites are
      available." from a plain host shell; `make docs-check` → "docs-check OK".
- [x] P1.2 COMPLETE — pinned versions + install method recorded in
      `docs/local-tooling.md`, including the make-wrapper recursion pitfall and a known
      P3 gap (kind + rootless Podman needs cgroup `Delegate=yes`, not yet fixed).

### P2 — Local application slice

- [ ] P2.1 NOT STARTED — API skeleton + health endpoint + tests.
- [ ] P2.2 NOT STARTED — schema, migrations, seed data.
- [ ] P2.3 NOT STARTED — catalog + order endpoints + integration tests.
- [ ] P2.4 NOT STARTED — React catalog/detail/cart/confirmation pages.
- [ ] P2.5 NOT STARTED — Compose file + image scan + size record.

### P3 — Local Kubernetes

- [ ] P3.1 NOT STARTED — kind cluster + plain manifests.
- [ ] P3.2 NOT STARTED — probes, limits, config.
- [ ] P3.3 NOT STARTED — Ingress routing.
- [ ] P3.4 NOT STARTED — Helm chart.
- [ ] P3.5 NOT STARTED — drills (scale, delete, break, rollback).

### P4 — AWS account readiness

- [ ] P4.1 NOT STARTED — root MFA + credential review (owner console checklist).
- [ ] P4.2 NOT STARTED — budget + alerts + anomaly detection (owner console checklist).
- [ ] P4.3 NOT STARTED — pin region; record above under Known facts.
- [ ] P4.4 NOT STARTED — paper rehearsal of the session runbook.

### P5 — Manual EKS session

- [ ] P5.1 NOT STARTED — session start + eksctl cluster.
- [ ] P5.2 NOT STARTED — ECR repos + image push.
- [ ] P5.3 NOT STARTED — ALB controller + Ingress + reachability.
- [ ] P5.4 NOT STARTED — trace + break/fix drill.
- [ ] P5.5 NOT STARTED — teardown + clean sweep.

### P6 — Terraform, then CI/CD

- [ ] P6.1 NOT STARTED — Terraform modules + reviewed plan.
- [ ] P6.2 NOT STARTED — apply/verify/destroy cycle.
- [ ] P6.3 NOT STARTED — OIDC role + PR pipeline.
- [ ] P6.4 NOT STARTED — deploy pipeline against session cluster.
- [ ] P6.5 NOT STARTED — CI rollback drill.

### P7 — Managed data services

- [ ] P7.1 NOT STARTED — RDS + migration job.
- [ ] P7.2 NOT STARTED — S3 images via adapter + workload identity.
- [ ] P7.3 NOT STARTED — Secrets Manager integration.
- [ ] P7.4 NOT STARTED — teardown incl. snapshot policy check.

### P8 — Observability and drills

- [ ] P8.1 NOT STARTED — app logging + request IDs.
- [ ] P8.2 NOT STARTED — CloudWatch dashboard + alarms.
- [ ] P8.3 NOT STARTED — four troubleshooting drills.
- [ ] P8.4 NOT STARTED — troubleshooting runbooks.

### P9 — Interview package

- [ ] P9.1 NOT STARTED — walkthrough script.
- [ ] P9.2 NOT STARTED — final diagram set.
- [ ] P9.3 NOT STARTED — timed dry-run.

## Blockers

- None.

## Session log

Append newest entries immediately below this heading. Never include secrets or AWS account IDs.

### 2026-07-18 — P1 local toolchain — Claude Code (operator: Tsogo)

- **Phase/task:** P1.1 and P1.2 complete; P1 gate ready for owner approval.
- **Changed:** installed aws-cli 2.36.2, kubectl v1.36.2, eksctl 0.229.0, kind v0.32.0,
  helm v3.21.3, terraform v1.15.8 as static binaries to host `~/.local/bin`; installed
  `make` (GNU Make 4.4.1) + `podman` package into the toolbox `bedoux-aws` via dnf;
  added `~/.local/bin/make` wrapper (`toolbox run -c bedoux-aws /usr/bin/make "$@"`);
  updated `docs/local-tooling.md` with full version/method table and a documented
  rootless-Podman gap for `kind` (needs cgroup `Delegate=yes`) deferred to P3.1.
- **AWS:** none. No AWS account contacted; `aws configure` was never run. Estimated
  session cost: USD 0.
- **Commands/tests (T-011):** `make tools-check` from a plain host shell →
  "All project prerequisites are available."; `make docs-check` → "docs-check OK".
- **Decisions:** chose host-`~/.local/bin` static binaries over toolbox-only install for
  the AWS/K8s CLIs, so `kind` shares the host's real Podman instead of a nested one —
  this is an environment detail, not an architecture decision, so no new ADR.
- **Incident (self-caught, no lasting harm):** the first version of the `make` wrapper
  called `toolbox run -c bedoux-aws make "$@"` (by name). Since the toolbox shares
  `$HOME`, `make` inside the toolbox also resolved to this same wrapper, recursing until
  the process/fork limit was hit (`fork: retry: Resource temporarily unavailable`).
  Killed with `pkill -9 -f "toolbox run"`; process count returned to normal (~430) within
  seconds; no kind/podman resources were ever created, nothing to tear down. Fixed by
  calling `/usr/bin/make` (absolute path) inside the toolbox; re-verified clean.
- **Next action:** owner approves the P1 gate; then P2.1 — FastAPI skeleton + health
  endpoint + tests (Compose). Separately, P3.1 must start with the rootless-Podman
  `Delegate=yes` fix before a real kind cluster can be created.
- **Blockers:** none for P1. Noted (not blocking): kind + rootless Podman gap for P3.

### 2026-07-18 — P0.6 GitHub push + ADR 0004 — Claude Code (operator: Tsogo)

- **Phase/task:** P0.6 complete; P0 gate ready for owner approval.
- **Changed:** ADR 0004 (start private, flip public before P9 after a full-history secrets
  sweep) supersedes 0003; repo `bedoux-tech/bedoux-commerce-cloud` created private via
  bedoux-vm's openclaw gh; collaborator invite to `tsogtbatjargal` accepted via API;
  `origin` added; `main` pushed.
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** `gh repo create --private` (on bedoux-vm), `gh api PUT .../collaborators`,
  local `gh api PATCH user/repository_invitations/<id>`, `git push -u origin main` →
  `* [new branch] main -> main` (T-002).
- **Decisions:** ADR 0004 accepted by owner ("lets start with private").
- **Next action:** owner approves the P0 gate; gate commit activates P1 (P1.1 install/pin
  toolchain — note `make`, `xmllint`, `aws` missing on this host).
- **Blockers:** none.

### 2026-07-18 — P0 verification + commits — Claude Code (operator: Tsogo)

- **Phase/task:** P0 gate verification (T-001, T-003, T-005, T-006); P0.6 pending.
- **Changed:** five convention commits P0.1–P0.5 (`7633b33`..`4a3c30c`); START-HERE
  checkpoint refreshed; `scripts/check-tools.sh` now also requires `make` + `xmllint`
  (both missing from this Silverblue host's base — install in P1).
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** docs-check logic OK (run via bash; `make` not on host yet);
  secrets sweep over `git ls-files` clean; T-005 cold-start test passed — a fresh agent
  reported state ("P0 nearly complete") and next action (P0.6 after visibility
  confirmation) from the spine alone, and caught the then-uncommitted checkpoint edit;
  T-006: the four slash commands are registered, `aws` CLI absent so `/aws-*` refuse
  safely. Diagram SVGs exported via podman `docker.io/rlespinasse/drawio-export`.
- **Decisions:** none new.
- **Next action:** P0.6 — owner confirms repo visibility (public per ADR 0003) and which
  GitHub account hosts it: local `gh` is authed as the owner's personal account, not
  `bedoux-tech`; then create + push, record T-002 evidence, close the P0 gate.
- **Blockers:** none.

### 2026-07-17 — P0 bootstrap — Claude Code (operator: Tsogo)

- **Phase/task:** P0.1–P0.4 complete; P0.5–P0.6 in progress.
- **Changed:** created git repo (`git init -b main`), `.gitattributes`, doc spine
  (`START-HERE.md`, `AGENTS.md`, `CLAUDE.md` shim, `docs/PROGRESS.md`,
  `docs/IMPLEMENTATION-PLAN.md`, `docs/TEST-PLAN.md`, `docs/HANDOFF.md`); merged and removed
  `docs/project-plan.md` + `docs/learning-roadmap.md`; ADRs 0002/0003 + index; 0001 →
  Accepted; edits to README, architecture, aws-session runbook, Makefile; `.claude/`
  settings + 4 slash commands; diagram revisions.
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** `make docs-check` (see phase gate T-001 for final run).
- **Decisions:** ADR 0002 (defer Route53/ACM/RDS/S3/Secrets from MVP), ADR 0003
  (bedoux-tech public repo, direct-to-main until P6, commit convention).
- **Next action:** finish P0.5 diagrams, then P0.6 GitHub push after owner confirms
  visibility.
- **Blockers:** none.
