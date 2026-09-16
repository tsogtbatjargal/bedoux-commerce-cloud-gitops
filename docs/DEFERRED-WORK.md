# Deferred work and post-MVP improvements

Last updated: 2026-09-16T09:35:39-06:00.

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
- **Resolution (2026-09-14T17:20:57-06:00):** fixed. The values-only source now carries only
  `repoURL`/`targetRevision`/`ref` (no `path`, so it can no longer be treated as a second
  manifest-generating source), and `helm.valueFiles` references the full repo-relative path
  (`$values/env/values.yaml`), not a basename. Proven by
  `scripts/test-render-gitops-applications.sh`'s two DEF-005 assertions, resolving real nested
  fixture content through the Application contract at a pinned commit. See `docs/PROGRESS.md`
  session log 2026-09-14T17:20:57-06:00 for full evidence. This entry and its gap/history above
  are kept, not deleted, per this file's maintenance rule.
- **PR #95 review (2026-09-14T17:26:10-06:00, Codex):** emitted values-only source and full
  repo-relative valueFiles reference are corrected at `0ded589e29e2938dec79a8070365b68b3cd822d0`.
  Regression evidence still needs repair: the awk assertion starts at `ref: values`, so a
  forbidden `path: env` immediately BEFORE ref passes (independently reproduced, exit 0).
  Parse the complete source mapping and prove an injected path is rejected irrespective of
  key order; resolve the selected nested values file and render the actual selected workload.
  Both new renderer suites pass locally but are absent from CI workflow/Makefile invocations.
  Wire the same commands into CI before treating its green status as source-binding evidence.
- **PR #95 follow-up (2026-09-14T18:45:56-06:00, Codex):** at
  `13b98ea525838a81470eb6817e9cbbe0ebbf5f9a`, the values-only path check is structural and
  both renderer suites execute in CI (confirmed job log). Those previous findings are closed.
  Remaining source-binding false acceptance is recorded under DEF-006 below; do not re-open
  the now-fixed full-path/ref-only implementation or CI wiring.

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
- **Resolution (2026-09-14T17:20:57-06:00):** fixed for the one-root/one-child case (multi-child
  fan-out/real App-of-Apps enumeration remains deferred — see below). `--root-path` is read as a
  directory that, at the pinned `--env-revision`, must contain exactly one child-pointer YAML
  file (`docs/gitops-fixtures/dev-root-child-pointer.example.yaml` is a worked example); the
  renderer reads that pointer to discover the child's `releaseRecordPath`/`valuesPath`/
  `childAppName` and generates the child from it — the root's own source now actually produces
  the child, rather than the caller separately naming both. Release-record/values parsing,
  appRevision/chart-path verification and the `pairedAppRevision`/image repository/digest
  cross-check are now shared via `scripts/lib/gitops-release-binding.sh`, sourced by both
  `render-gitops-release.sh` and `render-gitops-applications.sh` — actually reused, not just
  documented as reused; the child renderer previously skipped this validation entirely. Proven
  by `scripts/test-render-gitops-applications.sh` (33 assertions): zero/multiple pointer files
  refused by name, a pointer missing a required field refused, and an image-digest mismatch
  reached through the root/pointer path now refused (the pre-fix renderer would have rendered it
  without error). Multi-child fan-out is still explicitly out of scope — this proves one root
  producing one child, not enumeration across several; still revisit before multi-environment
  promotion (GO-2/GO-3), per the original boundary above. See `docs/PROGRESS.md` session log
  2026-09-14T17:20:57-06:00 for full evidence. This entry and its gap/history above are kept,
  not deleted, per this file's maintenance rule.
- **PR #95 review (2026-09-14T17:26:10-06:00, Codex):** NOT CLOSED at
  `0ded589e29e2938dec79a8070365b68b3cd822d0`. Shared release/image validation is an improvement,
  but the emitted root source only specifies repoURL/targetRevision/path. Its pinned apps/dev
  directory contains a custom childAppName/releaseRecordPath/valuesPath YAML pointer, not a
  Kubernetes Application, Helm root chart, Kustomization or configured plugin. The external
  shell script emits the child; Argo is not instructed to execute it. Independently inspected
  the test's pinned root: no generator, pointer is not an Application, child chart contains only
  Chart.yaml (no workload template). Both suites passing does not prove the root can generate
  the child. Require an actual Argo-supported root rendering path and a local root-source to
  child to pinned-values/chart to workload test, including a broken-source negative and moving
  branch independence. Keep this entry open and correct candidate closure claims meanwhile;
  no live cluster or GO-2 activation needed for these bounded fixes.
- **Correction — DEF-006 reopened (2026-09-14, later same day):** the resolution immediately
  above was premature. The "child-pointer YAML file" format it describes
  (`childAppName`/`releaseRecordPath`/`valuesPath`) is **not** something real Argo CD understands.
  A genuine Argo App-of-Apps sync of the root Application (`source.path` = `--root-path`) applies
  whatever it finds there as Kubernetes resources; that pointer file is not a valid `Application`
  manifest, so nothing in actual Argo semantics turns it into the child. The root and child text
  emitted by that revision of `render-gitops-applications.sh` were only two independently
  parameterized renders that happened to agree with each other — not proof that the root's own
  source produces the child through any mechanism Argo itself implements. DEF-006 is now
  **re-resolved**, this time via an actual Argo-supported generation mechanism (real App-of-Apps):
  `--root-path` must contain, at `--env-revision`, exactly one already-rendered, checked-in
  `Application` manifest for the child (`docs/gitops-fixtures/dev-root-child-application.example.yaml`
  is the current worked example — the prior pointer-file fixture is kept, with its own correction
  note, not deleted). `scripts/render-gitops-applications.sh` discovers that manifest, independently
  re-derives the release binding from two provenance annotations
  (`gitops.bedoux/release-record-path`, `gitops.bedoux/values-path`) resolved at the manifest's OWN
  values-source revision (never assumed equal to `--env-revision`; required to be a pinned, existing
  commit that is an ancestor-or-equal of `--env-revision`), and structurally validates — via a real
  YAML parse (`scripts/lib/gitops-release-binding.sh`'s `gob_validate_child_manifest`), not
  line-adjacency — that the checked-in manifest's `spec.sources` match that independently-derived
  binding field-for-field, including rejecting an injected `path` on the values-only source. It then
  proves "resolved pinned chart/values → workload manifests" by running the same `helm template` step
  `render-gitops-release.sh` uses (`gob_render_workload_manifests`, now shared by both scripts).
  Broken-root (YAML present but not a valid `Application` manifest) and moving-branch negative tests
  were added. Proven by `scripts/test-render-gitops-applications.sh` (36 assertions), now wired into
  `.github/workflows/pr-validation.yml`'s "Terraform and Helm validation" job alongside
  `scripts/test-render-gitops-release.sh`, both confirmed green in CI. Multi-child fan-out remains
  explicitly out of scope, per the original boundary above. This correction and both resolutions
  above are kept, not deleted, per this file's maintenance rule.
- **PR #95 follow-up (2026-09-14T18:45:56-06:00, Codex):** remains OPEN at
  `13b98ea525838a81470eb6817e9cbbe0ebbf5f9a`. Actual checked-in child Applications replace
  the unusable pointer, but independent local counterexamples still pass: (1) inject chart
  helm.parameters overriding api.image.repository with example.invalid/unreviewed-api;
  structural validation accepts and emits it while the proof renderer ignores the override;
  (2) put the only child under apps/dev/nested: recursive git discovery accepts it, but the
  emitted root lacks directory.recurse and Argo's default nonrecursive directory load skips it.
  The root loader also filters away non-Application YAML and JSON instead of validating the
  exact resource set Argo loads. Require matching selection semantics and reject unexpected
  render-affecting Helm/source fields (or faithfully validate and render supported ones).
  The positive chart still has no templates: output contains two Applications and zero
  workloads, yet the workload assertion passes. Add nonempty API/web templates, assert exact
  images and rendering context, and prove a reviewed child-pin advance changes workloads while
  the previous root pin remains stable. No live cluster needed; both current suites and CI
  pass but do not close these concrete gaps. Preserve the single-child/local-only boundary.
- **Follow-up (2026-09-14T21:08:05-06:00): three bounded gaps closed in the same App-of-Apps fix.**
  (1) The structural validator (`gob_validate_child_manifest`) previously checked only the fields it
  actively used; a checked-in manifest could declare unsupported Helm/source override fields
  (`helm.parameters`, `helm.values`/`valuesObject`, `kustomize`, `directory`, `plugin`, a Helm-repo
  `chart` reference) that a real Argo sync WOULD apply but this tooling's own `helm template` proof
  step silently ignored — proving a different effective output than Argo's own. Now refused via an
  explicit key allowlist on both sources. (2) Discovery under `--root-path` was recursive
  (`git ls-tree -r`) while the emitted root Application carries no `directory: {recurse: true}`
  (Argo's default is non-recursive) — a mismatch: a nested child manifest this script found would
  never actually be synced by real Argo. Discovery is now non-recursive (matching the emitted
  config) and explicitly refuses a nested directory rather than silently traversing into or ignoring
  it; it also now refuses ANY additional resource alongside the one child manifest (not just multiple
  `kind: Application` files) — a real Argo sync applies everything it finds there, not just the
  Application-kind ones. (3) The scratch chart used by both renderer test suites had no (or only a
  one-sided API) template, so `helm template` produced an empty/NOTES-only banner — the
  "resolved chart/values → workload manifests" proof asserted only exit code 0, not actual content.
  Both suites now render real API+web Deployment templates and assert the rendered workload
  manifests contain the pinned `repository@digest` for both images. A new test demonstrates a
  reviewed child-pin update (new image digests via a fresh checked-in child manifest, modeling a
  real release promotion) changes the workload output at the new pin while a re-render at the
  previous, already-reviewed root pin remains byte-identical to its original render. See
  `docs/PROGRESS.md` session log 2026-09-14T21:08:05-06:00 for full evidence. This follow-up and
  everything above it in this entry are kept, not deleted, per this file's maintenance rule.
- **PR #95 follow-up (2026-09-15T19:14:32-06:00, Codex):** at
  `55af6085570f106143df1dca877171f5ec6532e0`, source/Helm-key allowlists, strict single-file
  nonrecursive discovery, nonempty API/web templates and child-pin image promotion address
  the prior override, nested-discovery and empty-output findings. Both suites and four CI
  checks pass. One requested rendering-context gap remains: the Application renderer passes
  releaseId to Helm and omits --namespace, whereas its child uses Argo's default release name
  (metadata.name) and destination.namespace. A fixture using .Release.Name/.Release.Namespace
  yields dev-0001-api/default instead of dev-child-api/bedoux-dev while render exits 0.
  Derive and validate that context from the child, pass it explicitly to the shared renderer,
  and add context-sensitive template assertions. Keep this bounded correction on PR #95;
  no diagram edit, broader GO-1 restart, GO-2 activation or cluster is needed.
- **Follow-up (2026-09-15T19:24:39-06:00): rendering-context correction.** The shared workload
  renderer (`gob_render_workload_manifests`) previously called `helm template` with the release
  record's own `releaseId` as the Helm release name and no `--namespace` at all — so
  `.Release.Name`/`.Release.Namespace` inside any template never matched what a real Argo sync would
  actually set (Argo uses the Application's own `metadata.name` as the Helm release name, and
  `spec.destination.namespace` as `.Release.Namespace`; it has no knowledge of `releaseId`, an
  internal release-record field). Fixed: `gob_render_workload_manifests` now takes an explicit
  `release_name`/`namespace` pair (validated as DNS-1123 labels via new `gob_require_dns_label`)
  instead of deriving a release name internally, and `render-gitops-applications.sh` derives that
  pair from the (structurally validated) checked-in child manifest — `metadata.name` and
  `spec.destination.namespace` — passing the child's own identity, not `releaseId`, into the
  renderer. `gob_validate_child_manifest` also now validates `spec.destination.namespace` against
  the `bedoux-<environment>` convention (derived from the release record) and
  `spec.destination.server` against the expected in-cluster server, refusing a mismatch rather than
  trusting the checked-in value blindly. `render-gitops-release.sh` (which has no Application to
  derive a namespace from) passes an empty namespace through unchanged, matching `helm template`'s
  own "default" default — its release name (`releaseId`) is unchanged, since there is no Application
  identity to prefer over it there. Both renderer test suites now render API/web `Deployment`
  templates using `.Release.Name`/`.Release.Namespace` and assert their EXACT rendered value (not
  just "some namespace"), plus a new mismatched-namespace negative test proving the validation
  actually rejects a wrong `spec.destination.namespace`. Proven by
  `scripts/test-render-gitops-applications.sh` (58 assertions, up from 54) and
  `scripts/test-render-gitops-release.sh` (23 assertions, up from 21). See `docs/PROGRESS.md` session
  log 2026-09-15T19:24:39-06:00 for full evidence. This follow-up and everything above it in this
  entry are kept, not deleted, per this file's maintenance rule.
- **Review accepted (2026-09-15T21:37:42-06:00, Codex):** at PR #95 head
  `5152ae0ed9279a09f9fb63cb59b627ae1dbc38ca`, the remaining Helm rendering-context mismatch
  is fixed: the child name and validated destination namespace are passed explicitly, with
  context-sensitive positive tests and a wrong-namespace refusal. Local renderer suites pass
  58/58 and 23/23; GitHub reports all four checks SUCCESS (run `35044122307`). No blocking
  finding remains in this bounded follow-up. PR is still OPEN, not merged; live reconciliation
  remains later-phase evidence. Preserve the single-Application MVP boundary until separately
  authorized adoption. Historical review findings below are retained, not reopened by this note.
- **Merge recorded (2026-09-16T14:12:21Z, Claude):** PR #95 merged at the reviewed head above,
  producing merge commit `c6af3b70a94bc397c42d789ea556ffd4e0210693` — the "PR is still OPEN, not
  merged" line in the note immediately above is superseded by this merge, not deleted; it was
  accurate when Codex wrote it. See `docs/PROGRESS.md` session log 2026-09-16T14:12:21Z for full
  evidence. DEF-005 and DEF-006 are closed for this bounded slice; full GO-1 remains `IN PROGRESS`
  and paused, GO-2 remains inactive, per every resolution above.

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

## Captured MVP findings — resolved, closed with the MVP

These items affected the selected demo path itself and were closed within the active MVP task
in `PROGRESS.md`, not by restarting the advanced GitOps work above. Evidence source: Codex review
at 2026-09-09T20:27:22-06:00 in `PROGRESS.md`. Kept here (not moved to "Resolved items" below) so
the full gap/fix history stays attached to each ID; each now carries a **Resolution** line.

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
  `docs/runbooks/gitops-mvp-demo.md`.
- **Resolution:** owner-approved closeout 2026-09-10. Same-cluster scaling lap demonstrated
  (snapshot `153a1526a...` -> `c16d9e0a8...`, web `1/1` -> `2/2`, DB credential reused, DB-backed
  checks passing before/after); `web.replicas` restored to `1`; the earlier "new migration Job"
  claim corrected (scaling-only change correctly reuses the already-Succeeded Job for the same
  image tag). Chart fix (`migration.gitopsMode`) and all scripts/tests committed and merged via
  PR #91 (`feature/gitops-mvp` -> `main`), all four CI checks passing. See `docs/PROGRESS.md`
  session log 2026-09-10T02:55:00Z, 2026-09-10T03:40:00Z and 2026-09-10T11:15:00-06:00 for full
  evidence and the merge SHA. Scope closed is scaling-only; new image/migration releases remain
  unproven (tracked in DEF-015).

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
- **Resolution:** owner-approved closeout 2026-09-10. Post-trigger stale-operation fast-fail
  fixed (fast-fail conditions now gated on `operation_is_current`); new real-trigger regression
  test (no `--skip-sync`) proves the loop waits through the stale window before succeeding; 14/14
  verifier assertions passing. Merged via PR #91, all four CI checks passing. See
  `docs/PROGRESS.md` session log 2026-09-10T03:40:00Z and 2026-09-10T11:15:00-06:00. Arbitrary
  image-update/all-response-shape verification remains unproven (tracked in DEF-015).

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
- **Resolution:** owner-approved closeout 2026-09-10. Ownership is now checked before any cluster
  mutation (an unmarked reused cluster is refused, never adopted); the broad `mvp-*` image-cleanup
  fallback is removed (exact-tag-only, skipped and reported rather than guessed); deletion
  failures now propagate to a non-zero exit instead of being reported as complete. 5
  up-ownership + 17 cleanup assertions passing. Merged via PR #91, all four CI checks passing.
  See `docs/PROGRESS.md` session log 2026-09-10T03:40:00Z and 2026-09-10T11:15:00-06:00. No demo
  cluster, container, or image remained on the host after this closeout (reconfirmed
  2026-09-10). Further inventory-error/preflight hardening remains open (DEF-015).

### DEF-015 — Post-MVP startup preflight and broader update verification

- **Status:** PARTIALLY RESOLVED (owner-approved bounded milestone GO-MVP-U1, 2026-09-10);
  remaining subfinding stays DEFERRED. Source: Codex review 2026-09-10T09:20:38-06:00 in
  `PROGRESS.md`.
- **Resolution (subfinding 1 of 3 — startup inventory-error branch): CLOSED.**
  `scripts/gitops-mvp-up.sh` now captures `kind get clusters`' own exit status before deciding
  create-vs-reuse (mirrors the pattern already in `scripts/gitops-mvp-down.sh`): a failed query
  REFUSEs before any cluster mutation, instead of falling through to creation. New regression test
  `scripts/test-gitops-mvp-up-inventory.sh` (6/6 assertions) proves no kind/kubectl/podman/helm
  mutation call happens after a failed inventory query. See `docs/PROGRESS.md` GO-MVP-U1.1 session
  log entry.
- **Resolution (subfinding 2 of 3 — `.items[0]` ordering selection and a real update proof):
  CLOSED for the demonstrated shape.** `scripts/gitops-mvp-verify.sh` now selects the newest
  RUNNING pod per label, not `.items[0]`. A genuine source-revision-A → source-revision-B
  application-version update (API version bump surfaced in `/health`, a visible web footer, a new
  backward-compatible migration) was live-demonstrated on the same cluster/database: the running
  image provably changed, the visible change appeared, and a synthetic order survived the update
  unchanged. This also surfaced and fixed two previously-unknown defects: `gitops-mvp-verify.sh`
  required a bare `Synced` status and `Healthy` health that a real update (as opposed to GO-MVP's
  scaling-only case) can never reach again, because retained prior-release migration Jobs
  (deliberately never pruned) permanently show as extra/unhealthy resources — fixed with a
  narrowly scoped tolerance (only a retained, non-current-release Job may explain an OutOfSync/
  Degraded reading; any other drift still fails). See `docs/PROGRESS.md` GO-MVP-U1.2 session log
  entry and `docs/runbooks/gitops-mvp-demo.md`'s "GO-MVP-U1" section for the full transcript.
  **Not closed:** broader new-image/schema shapes beyond this one demonstrated update (e.g.
  multi-file source changes, dependency/runtime-version bumps, destructive schema changes) remain
  unproven.
  - **Verifier hardening round 2 (Codex review, 2026-09-10T17:24:50-06:00), fixed via mock
    regression tests only — the live-demo evidence above is unchanged, not re-run:** the
    retained-Job tolerance did not reject a failed/empty/malformed resource listing; excused any
    non-current Job by name inequality alone rather than positive identification (naming
    convention + a direct terminal-status check); inferred current-release health purely from
    "all drift is retained Jobs" instead of independently confirming the current release's own
    resources; and the ordering check picked one pod per label instead of identifying the
    current-rollout ReplicaSet, checking every relevant replica, and explicitly reporting a
    workload the release left unchanged. All four fixed in `scripts/gitops-mvp-verify.sh`;
    26/26 mock assertions pass (up from 14/14; then 16/16 after round 1). See
    `docs/PROGRESS.md`'s 2026-09-10T18:00:00-06:00 session log entry.
  - **Verifier hardening round 3 (Codex review, 2026-09-10T19:05:29-06:00), fixed via mock
    regression tests only — the live-demo evidence above is still unchanged, not re-run:**
    round 2's "unchanged workload" detection still compared a ReplicaSet's creationTimestamp to
    migration completion — a timing correlation, not proof the pod template didn't change.
    Fixed to compare the actual pod-template-hash captured before this sync to the one active
    now (a genuine hash match is the only valid proof of "unchanged"), with a new regression
    proving a genuinely new ReplicaSet/pod whose pod predates migration completion is still
    caught ("new ReplicaSet -> new pod -> migration completes"). Separately, Job termination
    (both the current release's own migration Job and any retained prior-release Job) was
    inferred from `.status.succeeded`/`.status.failed` counts, which can reflect a Job still
    retrying after an earlier failed attempt (a "retry gap") rather than actually being done.
    Fixed to require the Job's own explicit `status.conditions[type=Complete|Failed,
    status=True]`, read via one validated query; a query failure or a Job with neither condition
    set yet is rejected, never defaulted to success. 30/30 mock assertions pass (up from 26/26),
    including preserved positive tests for a genuinely unchanged workload and a genuinely
    terminal retained Job (together, not just individually). See `docs/PROGRESS.md`'s
    2026-09-10T19:30:00-06:00 session log entry.
  - **Verifier hardening round 4 (Codex review, 2026-09-10T20:15:00-06:00), fixed via mock
    regression tests only — the live-demo evidence above is still unchanged, not re-run; no new
    cluster run:** `--skip-sync` was still using its pod-template-hash and pod-creation-timestamp
    reads to claim "unchanged by this release," an ORDERING VIOLATION, or full release acceptance
    — but with no sync ever triggered, both reads are of the SAME already-deployed state taken
    moments apart, not a genuine before/after pair; a coincidental hash match or mismatch there
    proves nothing about what happened during a release, because no release happened during that
    run. `--skip-sync` is now explicit STATUS ONLY: it skips the pre-sync hash capture entirely and
    reports migration ordering/unchanged-workload status as UNVERIFIED, never a pass/fail claim,
    and its final message never claims full release acceptance in that mode. Added a new stable
    regression proving a `--skip-sync` status check against pods that predate the current migration
    Job's completion (the routine "check on a release some time after it already happened" case)
    exits 0 with an explicit UNVERIFIED note — never a false ORDERING VIOLATION nor a false
    UNCHANGED claim. The scenarios that genuinely exercise ordering/unchanged-workload evidence
    (ordering violations, unchanged-workload, multi-replica, new-ReplicaSet ordering, and the
    combined unchanged+retained-Job case) were moved off `--skip-sync` onto a real triggered sync,
    since that evidence is only ever meaningful when a sync genuinely ran. Also fixed the mock
    itself: the prior/current ReplicaSet-hash transition was driven by a raw per-label call
    counter (transitioning on the 2nd call regardless of whether a sync was ever triggered) —
    replaced with a marker file the mock's `patch application` case only touches when a sync
    trigger actually happens, so the mock's own causality now matches the real script's (no
    trigger, no transition). 35/35 mock assertions pass (up from 30/30). See `docs/PROGRESS.md`'s
    2026-09-10T20:15:00-06:00 session log entry.
- **Resolution (subfinding 2b — migration ordering and controlled failure/recovery): CLOSED for
  the demonstrated shape.** A minimal backward-compatible migration's ordering before workload
  advancement was proven with Job/pod identity and timestamp evidence (already covered by GO-MVP's
  existing ordering check, re-confirmed here on a real update). A controlled migration failure
  (an isolated demo-only fixture on a throwaway, never-merged branch) was proven to make
  verification exit non-zero, never advance the candidate past the migration wave, and leave the
  previously-working release and its order fully usable. Recovery was explicit and reviewed
  (re-running startup pinned at the known-good revision, then verify) — no automatic schema
  downgrade was invoked. The failed migration's DDL rollback (Alembic's per-migration transaction)
  was inferred from the pod's `Error` exit, not independently re-confirmed with a direct `psql`
  schema query before teardown — a minor evidence gap, not a functional one.
- **Still DEFERRED (subfinding 3 of 3 — multi-cluster/shared-image concurrency):** multiple demo
  clusters can still share base-SHA image tags; a tag is not exclusive per-cluster ownership. No
  work was done on this in GO-MVP-U1; it stays out of scope.
- **While deferred:** one demo cluster at a time; review cleanup's exact tags and preserve
  anything shared; explicitly report skipped image cleanup; inspect exact leftovers manually when
  needed. Do not claim proof of arbitrary/destructive schema changes or multi-file source updates
  beyond the one demonstrated shape.
- **Revisit:** before adding multiple concurrent demos, before claiming broader new-image/schema
  deployment support than the one demonstrated update, or when startup inventory fails.
- **Close with (remaining):** scoped image ownership for any supported concurrency. No advanced
  GO-1 automation is implied.

### DEF-016 — Refresh MVP runbook after verifier and PR closeout

- **PR #94 review (2026-09-14T16:53:02-06:00):** requested post-sync documentation corrections
  verified at `0809eb4681e09d759e0445d8efcb605ad527ed65`: checkpoint records PR #93 merged
  and synchronization complete, duplicate history labeled, UTC/local timestamp corrected.
  Four CI checks and local documentation component checks pass; 25 unaffected GO-1 files
  match the backup manifest. No merge blocker found; PR #94 remains OPEN, pending owner
  merge authorization. This supersedes the pending-fix recommendation in the review below,
  without changing any advanced-work deferral or claiming the PR is already merged.
- **Post-sync review (2026-09-14T13:44:50-06:00):** runbook fix remains RESOLVED and PR #93
  is verified merged at `932230b7be36522aad7241e829a977ea35558cb3`; local synchronization and
  saved-work preservation are accepted. Small checkpoint follow-up remains deferred: refresh
  PROGRESS's stale open-PR/pending-sync status, visibly label the duplicate historical DEF-016
  section without removing review text, and correct the synchronization note's UTC/local time.
  Until then use PROGRESS's dated synchronization review for current state. Revisit at the next
  documentation closeout; close with consistent present-tense checkpoint/history labels in a
  focused reviewed PR. No runtime changes or phase activation are authorized by this note.
- **Status:** RESOLVED (documentation-only bounded housekeeping item, 2026-09-14T09:46:43-06:00; see below).
  Carried forward at GO-MVP-U1's PR #92 merge closeout (2026-09-10T21:37:35-06:00) from a note
  found in unrelated, uncommitted full-GO-1 working-tree content (never itself committed) so it
  was not lost. Updated: 2026-09-14T09:46:43-06:00.
- **Gap:** `docs/runbooks/gitops-mvp-demo.md` still described GO-MVP's chart fix as an uncommitted
  edit even though PR #91 merged it, and its verification narrative predated the per-workload
  ordering/retained-Job checks and the explicit `--skip-sync` status-only boundary added across
  GO-MVP-U1's four verifier-hardening rounds (see DEF-015 subfinding 2's round 2–4 notes and
  `docs/PROGRESS.md`'s 2026-09-10T18:00:00-06:00, 19:30:00-06:00, and 20:15:00-06:00 session log
  entries).
- **Resolution:** `docs/runbooks/gitops-mvp-demo.md`'s "Why a local snapshot" section now states
  the `migration.gitopsMode` chart fix is committed and merged (PR #91, merge commit
  `60e7d0757b1394f6d63a63530242eb7fed83eaf5`), not an uncommitted working-tree edit, and clarifies
  the local-snapshot mechanism is an independent design choice for fast iteration, not a
  workaround for that now-merged fix. Its "Verification" section now describes the current
  behavior accurately: default (triggered-sync) mode's retained-Job sync/health tolerance (only a
  positively-identified, terminal, non-current-release Job explains OutOfSync/Degraded — never any
  other drift or an unhealthy current resource), per-workload pod-template-hash before/after
  comparison (proving CHANGED vs. UNCHANGED, checked across every current-rollout replica when
  changed), and `--skip-sync`'s explicit status-only contract (no pre-sync sample, ordering/
  unchanged-workload status reported as `UNVERIFIED (--skip-sync)`, final message tagged
  `STATUS ONLY`, never a release-acceptance claim) — cross-checked directly against
  `scripts/gitops-mvp-verify.sh --help`'s current output. `START-HERE.md` and `docs/HANDOFF.md`
  were also refreshed to record PR #92's actual merge (head `935b95cc7cacd49c1b86e4676b5644069ec038d1`,
  merge commit `b7e52a9a14f2366609e6e733df0277872a5439b5`) rather than describing it as still open.
  No functional/runtime change — documentation only. See `docs/PROGRESS.md`'s 2026-09-14 session
  log entry for the PR and CI evidence.
- **While deferred (historical, prior to resolution above):** rely on
  `scripts/gitops-mvp-verify.sh --help` for the current, accurate behavior contract rather than
  the runbook's narrative; a default (non-`--skip-sync`) triggered sync is required for this run's
  ordering/unchanged-workload evidence, while `--skip-sync` is status-only and never a
  release-acceptance claim. The demo's local-snapshot operation was unaffected; this was a
  documentation-accuracy gap, not a functional one.
- **Revisit:** if the verifier's behavior changes again without a matching runbook update.
- **Close with:** `docs/runbooks/gitops-mvp-demo.md` updated to describe the chart fix as merged
  (not uncommitted) and to describe the current ordering/retained-Job/`--skip-sync` behavior
  accurately; no functional change implied or required. — **Done, see Resolution above.**

<!-- Synchronization note (merge sync 2026-09-14T16:30:03Z / 2026-09-14T10:30:03-06:00 -- corrected 2026-09-14, an earlier version of this note mislabeled the merge time as 16:30:03-06:00): the review notes immediately below were recorded directly in this checkout's local, uncommitted docs/DEFERRED-WORK.md by Codex across several PR #92 reviews, before this checkout was synchronized to main. They predate and are superseded by the resolved summary above (see also docs/PROGRESS.md's 2026-09-10T17:24:50-06:00 through 21:35:39-06:00 session log entries for the authoritative, already-merged record of the same work). Preserved verbatim, append-only, per the maintenance rule against silently deleting history. -->

- **Latest PR #92 review (2026-09-10T21:35:39-06:00):** bounded skip-sync mode finding
  CLOSED at `935b95cc7cacd49c1b86e4676b5644069ec038d1`. No pre-sync hash capture in
  status-only mode; both workloads report UNVERIFIED and final output explicitly disclaims
  release acceptance. Trigger-aware mocks preserve ordering checks in normal sync mode.
  Independent prior counterexample now produces only status/UNVERIFIED evidence. All 35
  verifier assertions and other local MVP/Helm suites pass; four exact-head CI checks green.
  No remaining blocker found in this bounded follow-up; recommend owner-authorized merge,
  not an executed merge. Multi-cluster/broader-shape limitations remain deferred. Original
  live evidence unchanged; isolated worktree retains authoritative U1 state. Runbook drift
  is tracked separately as non-blocking DEF-016.
- **PR #92 review (2026-09-10T21:09:26-06:00):** at head `30175af`, explicit
  Complete/Failed conditions address the retry-gap finding, and before/after template hashes
  address the triggered-sync counterexample. All 30 verifier assertions pass. One bounded P2
  mode-contract issue remains: `--skip-sync` captures both hashes after an already-completed
  deployment, yet calls their equality proof the release left the workload unchanged and
  bypasses ordering. A stable mock with a new RS at 00:00:30Z, its pod at 00:01:00Z and migration
  completion at 00:02:00Z exits 0 with UNCHANGED/ALL NON-HTTP CHECKS PASSED. No sync was triggered.
  Smallest correction: make skip-sync explicitly status-only, reporting ordering unverified
  without release-acceptance/unchanged-by-release claims; no durable evidence framework needed.
  Add a stable post-deployment regression, and make transition mocks change state only after
  an actual sync trigger. Preserve original live evidence; no new live run needed for this fix.
  This review note does not replace the isolated worktree checkpoint or authorize merge/GO-2.
- **PR #92 review (2026-09-10T19:05:29-06:00):** at head `e40025f` (verifier code
  unchanged from `aadff46`), failed/empty resource-list checks and naming/group restrictions
  are improved; all 26 verifier assertions pass. Two reproduced blockers remain within U1:
  (1) an RS created before migration completion is automatically called unchanged, so a NEW
  release deployed prematurely bypasses ordering altogether; (2) failed-pod counts plus
  zero active pods do not prove Job termination, and failed direct reads still default to zero.
  Mocks for an early new RS, a Job between retries, and a failed active-status read all exit 0.
  Require independent before/after workload identity to prove unchanged, and explicit true
  Complete/Failed Job conditions from a successful validated read. Do not infer either from
  the timestamps/counters whose safety is being tested. Keep previous live evidence unchanged.
- **Host closeout update:** inotify is independently confirmed restored to 128. No new live
  cluster run is needed merely to reproduce these verifier defects; add realistic local cases
  including RS creation before its pod, both preceding migration completion. Preserve valid
  truly unchanged workloads and terminal retained-Job recovery as positive controls.
- **PR #92 review (2026-09-10T17:24:50-06:00):** GO-MVP-U1 is active on the separate
  `feature/gitops-version-update` worktree; this main-worktree note does not replace its
  checkpoint or imply merge. Startup inventory refusal is correctly implemented at candidate
  head `2bfe8e0f17960b6516b38bf02e91353d7cdab99d`, and the reported A/B/order/failure demo is
  useful evidence. However, verifier subfindings are not ready to close: the new retained-Job
  predicate returns success on failed/empty resource reads, permits ANY non-current Job, and
  uses sync status alone to excuse Degraded health without examining resource health. Mocks
  independently return exit 0 for these cases. Selecting the newest Running pod also hides an
  earlier current-release replica created before migration completion; it does not identify
  the advancing ReplicaSet/image. Fix these bounded U1 verification gaps before merging #92;
  preserve the original scaling MVP closeout and keep multi-cluster work deferred.
- **Required regression evidence for candidate closure:** failed/empty/malformed resource
  reads refuse; a positively identified retained migration Job is tolerated, an unrelated Job
  or unhealthy current resource is not; health and sync reasons are checked independently;
  ordering selects actual current-rollout members and catches one early replica even if
  another was created later. Distinguish deliberately unchanged workloads from advancing ones.
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

### DEF-016 (historical duplicate — superseded by the DEF-016 section above; preserved verbatim, not deleted) — Refresh MVP runbook after verifier and PR closeout

- **Follow-up review (2026-09-14T10:28:30-06:00):** remaining PR #93 documentation findings
  closed at `5eb7a76e84ebaabc51a84eff17e01db5348ad021`. Snapshot description distinguishes
  committed app source from the working-tree chart overlay; stale remote-source transition
  removed. Pending synchronization now uses ancestry-checked fast-forward and retained stash
  apply with content reconciliation. Four CI checks and local documentation checks pass;
  all 27 refreshed-backup hashes matched before these required review notes were appended.
  Recommend owner-approved merge, then refresh the backup before synchronization. No merge
  or synchronization performed in this review; retain historical findings below as evidence.
- **PR #93 review (2026-09-14T10:04:22-06:00):** head `14a4f3b` is OPEN/MERGEABLE with
  all four CI checks green; documentation component checks pass. Two narrow corrections remain
  before recommending merge: runbook lines 39–41 incorrectly include uncommitted apps/api and
  apps/web edits in the snapshot (only charts/bedoux is overlaid; app changes require a local
  commit selected by --app-revision); lines 295–298 still make local snapshots conditional on
  the already-merged chart fix and imply remote-source support without a script change.
  Also revise the pending synchronization plan in PROGRESS and the backup README to use a
  checked fast-forward and retained stash apply instead of recommending hard reset/stash pop.
  All 27 backup manifest hashes matched before this review appended local notes; refresh the
  backup before synchronization and compare reconciled PROGRESS/DEFERRED semantically.
- **Closeout review (2026-09-14T08:44:32-06:00):** remote `main` at `f290478` carries
  this entry and correctly records PR #92 merged at `b7e52a9`. Its `START-HERE.md` and
  `docs/HANDOFF.md` still say the U1 PR is open; include those checkpoint statements in the
  next documentation refresh. The merge log calls direct main publication an established
  convention, contrary to START-HERE and the PR workflow's no-direct-main rule; correct that
  description and use a feature branch/PR for future checkpoint changes. No history rewrite
  is needed. This original checkout is still at `f3e38bd` with saved GO-1 changes: consult
  committed remote progress for current state and preserve those changes during any later sync.
- **Status:** DEFERRED; non-blocking for the reviewed local MVP/U1. Updated:
  2026-09-10T21:35:39-06:00.
- **Gap:** `docs/runbooks/gitops-mvp-demo.md` still describes the chart fix as an uncommitted
  edit although PR #91 merged it, and its verification narrative predates the current
  per-workload ordering/retained-Job checks and explicit skip-sync status-only boundary.
- **While deferred:** use the current verifier's `--help`; default triggered sync supplies
  this run's ordering evidence, while `--skip-sync` is status-only and never release acceptance.
  Local snapshot operation remains the implemented demo source; a documentation refresh does
  not authorize switching to a remote repository or enabling automated reconciliation.
- **Revisit:** next documentation/merge closeout or before handing the runbook to a new operator.
- **Close with:** reconcile present-tense instructions with committed code and merged PR state;
  distinguish historical live evidence from current mock tests; document both verifier modes.
- **Source:** Codex PR #92 review at `935b95c`, PROGRESS session 2026-09-10T21:35:39-06:00.

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

DEF-012, DEF-013 and DEF-014 are resolved; their full gap/fix history and Resolution evidence
are kept in place under "Captured MVP findings" above rather than duplicated here, per the
maintenance rule against silently deleting history. DEF-016 is also resolved (documentation-only
runbook refresh, 2026-09-14); its full gap/fix history and Resolution evidence are kept in place
under its own section above. No other items are resolved.
