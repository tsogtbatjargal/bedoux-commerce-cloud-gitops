# Deferred work and post-MVP improvements

Last updated: 2026-09-10T09:20:38-06:00.

The owner requested a working local MVP first, then the unfinished GitOps improvements.
This file keeps that work discoverable without treating it as fixed or requiring every future
feature before a local demo. [PROGRESS.md](PROGRESS.md) remains the **only authoritative
execution state**; this backlog does not activate tasks, approve architecture or authorize AWS.

## Maintenance rule

- Whenever work is deferred or an out-of-scope defect is discovered, add or update an item here
  before session closeout. Reuse an existing ID for the same issue; do not duplicate it.
- Include the gap, safe boundary while deferred, revisit trigger, closure evidence and source.
  Update the timestamp and reference its ID in the session entry in `PROGRESS.md`.
- After the MVP demonstration and at subsequent milestone closeouts, review this file with the
  owner. Activate only one approved item through `PROGRESS.md` and the normal gate workflow.
- Keep resolved entries with a link to completion evidence/commit; do not silently delete them.
  A proposed fix or passing helper test alone is not closure of a complete workflow.
- Deferral is safe only while the affected feature stays out of use or an explicit safe manual
  alternative exists. A blocker on the selected MVP path must be fixed or that path simplified,
  not relabeled as a future improvement. Secrets, migration safety and scoped cleanup still apply.

## Open items

All items below are **DEFERRED**, not active or complete. Their original GO task references are
future planning associations, not authorization to start those tasks. Initial defect evidence:
`PROGRESS.md`, Codex review at **2026-09-09T18:16:51-06:00**. The earlier review entries retain
the investigation history, including issues already fixed that should not be reopened here.

### DEF-001 — Usable, ownership-aware release-attempt workflow

- **Gap:** the runbook's `claim → check --claims-dir` sequence rejects its own new claim with
  exit 6. `consume` removes a claim without verifying ownership or a recorded outcome.
- **While deferred:** exclude claim automation from the MVP; use explicit operator review,
  manual sync and manual recovery. Do not claim automatic replay protection.
- **Revisit:** before automated bootstrap/retry/recovery (original GO-3/GO-5).
- **Close with:** one successful preflight/claim/deploy-stub/outcome workflow; competing and
  crashed attempts refused; only the authorized claimant can finalize against verified outcome
  evidence; bind authorization to the exact environment and immutable release tuple.
- **Artifacts:** `scripts/gitops_release_attempt_claim.py`,
  `scripts/gitops_bootstrap_precondition_check.py`, `docs/runbooks/gitops-recovery.md`.

### DEF-002 — Attempt evidence survives target-cluster loss

- **Gap:** the proposed ConfigMap-only claim disappears with the disposable cluster while Git
  may still say `pending`, allowing a fresh cluster to repeat an uncertain attempt.
- **While deferred:** never automatically resume an uncertain release after cluster loss;
  require operator review of deployment and migration evidence.
- **Revisit:** alongside DEF-001, before any automatic fresh-cluster recovery.
- **Close with:** a chosen durable authority outside the disposable target's failure boundary,
  documented restoration/permission rules, and a target-store-loss test that still refuses
  replay. No TTL-based guess that an uncertain attempt is safe.
- **Source:** design-contract Gate 6a and the 18:16:51 review in `PROGRESS.md`.

### DEF-003 — Paired rollout failure and traffic recovery

- **Gap:** failed paired health currently returns `HOLD`, leaving canary traffic in place.
  The post-API decision ignores both state objects and can promote a `Degraded` web candidate.
- **While deferred:** no Rollouts/canary coordinator in the MVP; deploy the ordinary API/web
  workloads and do not claim progressive-delivery safety.
- **Revisit:** before enabling paired canaries (original GO-6), together with DEF-004/DEF-007.
- **Close with:** explicit wait-versus-failure states, fresh release/health checks for both
  candidates before each action, automatic both-candidate abort on failure, observed stable
  routing, and drain-before-scale-down tests including failure between promotions.
- **Artifacts:** `scripts/gitops_paired_rollout_coordinator_model.py`, design-contract Gate 4b.

### DEF-004 — Atomic coordinator ownership and stale-owner fencing

- **Gap:** lease acquisition uses an existence check followed by an unconditional write; two
  genuinely simultaneous holders both succeeded. Expiry alone does not stop the old holder acting.
- **While deferred:** do not run the coordinator or rely on its lease model for exclusivity.
- **Revisit:** before any concurrent/restartable coordinator (original GO-6; depends on DEF-003).
- **Close with:** atomic acquisition and ownership/version-checked renewal/takeover; deterministic
  simultaneous-acquisition tests; stale holders refused before every promote/abort side effect.
- **Artifact:** `scripts/gitops_paired_rollout_coordinator_model.py`, `acquire_lease`.

### DEF-005 — Correct multi-source values lookup

- **Gap:** `env/values.yaml` renders as `$values/values.yaml`; Argo resolves that from the repo
  root. Setting `path: env` on the values source also enables unintended resource generation.
- **While deferred:** use a single-source Application for the MVP; do not use the broken
  multi-source generator. If multi-source becomes necessary, fix this before deploying it.
- **Revisit:** before adopting the environment repository's external-values flow (GO-2/GO-3).
- **Close with:** full repo-relative `$values/env/values.yaml`, no `path` on a values-only source,
  and tests resolving real nested files at the pinned commit through the Application contract.
- **Artifact:** `scripts/render-gitops-applications.sh`; [Argo semantics](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/).

### DEF-006 — Real root-to-child source generation and promotion

- **Gap:** rendering two separate Application objects does not prove the root's source produces
  that child. The passing fixture has no `apps/dev` root path; shared release validation is not
  actually reused by the Application renderer.
- **While deferred:** one directly managed, manually synced Application; no App-of-Apps claim.
- **Revisit:** before root/child automation and multi-environment promotion (GO-2/GO-3).
- **Close with:** execute the actual root template/generator locally, produce its child, resolve
  both immutable source revisions and shared image/release validation, then render the selected
  workload. Prove moving-branch independence and how a reviewed promotion advances the root
  without requiring a static file to contain its own commit SHA.
- **Artifacts:** `scripts/render-gitops-applications.sh`, `scripts/render-gitops-release.sh`,
  `docs/gitops-expansion-plan.md` release-binding requirements.

### DEF-007 — Progressive-delivery installation and router-specific evidence

- **Gap:** Rollouts, the executable paired coordinator and Traefik reconciliation adapter are
  design-only. A named adapter or matching step indices are not live routing evidence.
- **While deferred:** port-forward the MVP; no router/canary installation is required just for
  browser access. Retain the planned Traefik choice without claiming it is installed.
- **Revisit:** after MVP, before a routing/canary demonstration (GO-3/GO-6).
- **Close with:** compatible versions recorded in `local-tooling.md`, actual weighted-routing
  observation for the chosen provider, stable/canary dependency isolation, and P13-equivalent
  health, abort and drain evidence. Resolve DEF-003/DEF-004 first.
- **Source:** design-contract Gates 3/4b and `TEST-PLAN.md` T-GO-06.

### DEF-008 — Environment repository and promotion automation

- **Gap:** the separate private env repo, narrow bot/read credentials, env CI, release PRs and
  dev-to-staging promotion remain future implementation, not a working delivery path.
- **While deferred:** use the existing app repository, one environment and explicit manual
  revision selection/sync. Keep existing CI checks and the legacy namespace ownership boundary.
- **Revisit:** after the single-environment MVP works; obtain explicit remote-repository and
  phase authorization (original GO-2/GO-4).
- **Close with:** T-GO-02/T-GO-04 evidence, source/provenance validation, wrong-file bot proposals
  rejected, secrets absent from Git, and reviewed promotion of the same immutable artifact pair.
  Resolve DEF-005/DEF-006 before adopting their automation.

### DEF-009 — Admission enforcement and automated recovery hardening

- **Gap:** deployment-boundary signature enforcement and live recovery/restart drills are not
  established by controller selection or helper tests.
- **While deferred:** if omitted from the isolated synthetic-data MVP, explicitly record that
  runtime signatures are not enforced. Keep CI security checks; do not claim production readiness,
  signed-only admission or automatic disaster recovery. Manual safe cleanup is still MVP scope.
- **Revisit:** before enabling enforcement/automatic recovery or broadening beyond the bounded
  local demo (GO-3/GO-4/GO-5).
- **Close with:** pinned tools in `local-tooling.md`; wrong-signer/unsigned/verifier-outage and
  expired-exception tests; migration failure, reviewed repair, suspension/restart and data-recovery
  evidence for T-GO-03–05. Resolve DEF-001/DEF-002 before automatic attempt recovery.

### DEF-010 — Temporary AWS/EKS demonstration

- **Gap:** the new GitOps path has not been demonstrated on EKS.
- **While deferred:** local-only MVP; no AWS mutations or new billable services.
- **Revisit:** only after local acceptance and separate owner-approved AWS session (GO-7).
- **Close with:** relevant local blockers resolved, canonical session/cost controls, exact scoped
  authorization, live evidence and clean same-day teardown (T-GO-07).

### DEF-011 — Existing diagram export and documentation gate

- **Gap:** untracked `docs/diagrams/gitops-workflow.drawio` has no sibling SVG; full docs-check
  fails. The diagram and autosave belong to unrelated in-progress work.
- **While deferred:** preserve both files and report the failing gate honestly. This is a
  documentation/merge constraint, not a reason to build more deployment automation.
- **Revisit:** coordinate with its editor before including the diagram or claiming full docs-check
  success; this may be needed before post-MVP improvement work.
- **Close with:** owner/editor-approved disposition or valid exported SVG, then full docs-check
  passes for the intended change set. Do not delete or export someone else's work by inference.

## Captured MVP findings — not deferred past MVP acceptance

These items affect the selected demo path itself. They are recorded here for continuity, but
must be handled within the active MVP task in `PROGRESS.md`, not by restarting the advanced
GitOps work above. Evidence source: Codex review at 2026-09-09T20:27:22-06:00 in `PROGRESS.md`.

### DEF-012 — Demonstrate a repeatable Git-driven update on the same cluster

- **Latest review (2026-09-10T09:20:38-06:00):** ready for owner closeout for the
  **scaling-only MVP**. The reported same-cluster scaling/DB evidence stands; the subsequent
  log explicitly corrects the unsupported new-migration claim, and `web.replicas` is restored
  to 1. Historical gaps below are retained as history, not a request to repeat fixed work.
  New image/migration releases remain unproven and outside this acceptance recommendation.
- **Review update (2026-09-09T20:55:51-06:00):** credential reuse and removal of replica
  overrides are implemented; Claude records a same-cluster scaling lap at two snapshot SHAs.
  Accept that as reported scaling evidence, not a fresh migration/image-release lap: both runs
  use base HEAD's `mvp-2c1ec6b0aab1` tag and therefore the SAME migration Job name. The claim
  that a new Job ran on the second sync needs correction or UID/time evidence. A scaling-only
  MVP can retain its already-successful migration; do not require advanced release automation.
  Keep source/image-update support unproven until separately tested. The demonstration also
  leaves the shared chart's default web replicas at 2; restore the temporary baseline change
  or explicitly review that legacy behavior change before packaging.
- **Disposition:** MVP acceptance gap; not a post-MVP enhancement.
- **Gap:** startup generates a new DB password when reusing existing PostgreSQL/PVC state;
  fixed-name migration Job uses `Replace=true`, not an explicit recreation/release-identity
  mechanism; the suggested `web.replicas` change is masked by the script's `replicas: 1` override.
  Existing evidence reports initial installs, not a before/after revision-and-visible-change lap.
- **Safe boundary:** use only the recorded first-install demo; do not claim repeatable updates
  or rerun startup against retained data until credential reuse is addressed.
- **Close with:** preserve existing DB credentials; select a minimal migration-Job lifecycle
  that works for an image change; demonstrate one effective Git change → manual sync → observed
  result on the SAME cluster, with before/after SHAs, DB-backed API checks and workload health.
- **Artifacts:** `scripts/gitops-mvp-up.sh`, `charts/bedoux/templates/migration-job.yaml`,
  `docs/runbooks/gitops-mvp-demo.md`. Record true project commit state: current chart edits are
  uncommitted in this repository; commits inside throwaway snapshots are a different thing.

### DEF-013 — MVP verification must reject missing or failed evidence

- **Latest review (2026-09-10T09:20:38-06:00):** the specific post-trigger race is fixed;
  the new real-trigger mock waits through two stale polls and then succeeds. Independently
  reran all 14 verifier assertions successfully. Ready for owner closeout within the recorded
  scaling-only path; do not infer verification of arbitrary image updates or all transient
  API-response shapes. Historical findings below are superseded where explicitly fixed.
- **Review update (2026-09-09T20:55:51-06:00):** missing/failed Job, revision mismatch,
  rollout failure, ordering failures and HTTP status checks now reject as intended. Remaining
  wait bug: after successfully queuing a sync, a first read of the previous Succeeded operation
  immediately breaks the loop and refuses (mock exit 1 in under one second), rather than
  waiting for the new operation. All current verifier tests force `--skip-sync`, so none tests
  this normal trigger-to-controller transition. Add a bounded old-status → new-operation →
  success case, plus timeout/current-operation failure cases. Do not accept old status as
  success. Pod ordering currently uses `.items[0]` without selecting the advancing revision;
  unchanged workloads legitimately predate a new migration, so do not claim this proves all
  image-update shapes. Keep that extension outside a scaling-only MVP until verified.
- **Disposition:** MVP acceptance gap; not a post-MVP enhancement.
- **Gap:** verifier accepts stale Synced/Healthy without confirming the requested revision/sync
  operation; missing migration Job exits 0, ordering violations only warn, web ordering is not
  checked, and HTTP failures are printed without rejection. `/health` deliberately skips the DB.
- **Safe boundary:** do not treat the current verifier's exit 0 as full MVP acceptance evidence.
- **Close with:** bounded checks for the selected revision and completed sync, correct release's
  migration success and both workloads' advancement, successful HTTP checks including a DB-backed
  endpoint; failure-sensitive local tests and the live DEF-012 update lap.
- **Artifact:** `scripts/gitops-mvp-verify.sh`.

### DEF-014 — MVP cleanup inventory and exact ownership

- **Latest review (2026-09-10T09:20:38-06:00):** targeted ownership-before-mutation,
  no-adoption, no-prefix-fallback and deletion-error propagation fixes verified by code review
  and all 5 startup-ownership / 17 cleanup assertions passing. Ready for owner closeout for
  the one-cluster MVP. Unknown image ownership now explicitly skips image cleanup; success of
  other cleanup steps is not proof skipped images are absent. Historical findings below are
  superseded where explicitly fixed. Additional hardening is separately bounded in DEF-015.
- **Review update (2026-09-09T20:55:51-06:00):** kind-inventory failure, empty-state exit,
  cleanup-side marker refusal and Application finalizer are corrected. Still unsafe:
  startup checks ownership only AFTER node writes/image loads/Argo installation and patches,
  and adopts an unmarked existing cluster if it lacks the Application. Check ownership before
  any cluster mutation; mark only clusters positively created by this invocation. Cleanup's
  missing-Application/cluster fallback still sweeps ALL matching `mvp-*` images; mocks prove
  it selects another demo's image. A failed `podman images` query is still hidden by `|| true`
  and reports cleanup complete/exit 0. Remove the broad fallback (skip unknown targets and
  report them, or use exact recorded ownership), distinguish query errors, and do not report
  complete when retained-cluster deletion or image removal failed. These are existing MVP
  safety requirements, not a request for production inventory infrastructure.
- **Disposition:** MVP cleanup requirement; not a post-MVP automation expansion.
- **Gap:** inventory failure is treated as cluster absence; no matching images makes an already
  clean run fail through grep/pipefail; image cleanup selects every matching `mvp-*` image rather
  than a particular demo's inventory. Reused/custom clusters are not checked for demo ownership.
- **Safe boundary:** review exact targets manually; never infer successful teardown from a failed
  inventory query or delete unrelated resources. The 20:27 review independently confirmed no
  kind clusters remained from the reported run.
- **Close with:** already-clean success, inventory-error refusal, consistent Podman provider,
  exact demo-owned targets, a no-write preview and verified cleanup. Correct the claim that the
  Application cascades via a finalizer: the emitted Application currently declares none.
- **Artifacts:** `scripts/gitops-mvp-down.sh`, `scripts/gitops-mvp-up.sh`.

### DEF-015 — Post-MVP startup preflight and broader update verification

- **Status:** DEFERRED; non-blocking for the demonstrated single-cluster scaling-only MVP.
  Source: Codex review 2026-09-10T09:20:38-06:00 in `PROGRESS.md`.
- **Gap:** startup still branches to creation on a failed `kind get clusters` pipeline rather
  than distinguishing error from absence; test coverage does not yet include that branch.
  Verification still selects `.items[0]` for pod ordering and does not demonstrate all
  new-image/migration-update shapes. Multiple demo clusters can share the base-SHA image tags;
  a tag is not exclusive per-cluster ownership.
- **While deferred:** one demo cluster at a time; confirm successful read-only kind inventory
  before startup and stop on failure; review cleanup's exact tags and preserve anything shared.
  Use only the demonstrated chart-scaling update, not arbitrary source/schema updates.
  Explicitly report skipped image cleanup; inspect exact leftovers manually when needed.
- **Revisit:** before adding multiple concurrent demos or claiming new-image/schema deployment
  support, or when startup inventory fails.
- **Close with:** startup inventory-error test proving no creation is attempted; scoped image
  ownership for any supported concurrency; appropriate current-workload ordering evidence and
  a same-cluster new-image/migration update test. No advanced GO-1 automation is implied.

## New-item template

Use the next unused `DEF-NNN` ID; keep IDs stable when the title changes.

```text
### DEF-NNN — Short title

- Status: DEFERRED. Updated: <ISO 8601 timestamp with timezone>.
- Gap:
- While deferred: <safe boundary or manual alternative>
- Revisit: <concrete trigger; dependencies; owner decision if needed>
- Close with: <observable acceptance evidence>
- Source: <file / review timestamp / issue; no secrets or raw sensitive logs>
- Resolution: <leave empty until verified; link PROGRESS evidence and commit>
```

## Resolved items

None yet. Move closed entries here with their original IDs and evidence links.
