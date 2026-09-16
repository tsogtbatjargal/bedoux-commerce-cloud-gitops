# GO-1 design contract

Status: **Reopened for correction a seventh time on 2026-09-15.** No repository has been created,
no controller installed, no cluster or AWS resource touched to produce this document. Every check
below ran locally against this repository's existing files. Seven independent review rounds have
found and closed real defects — see all seven "Corrections applied" sections below. The fourth
round's DEF-006 fix was itself premature: it generated the child from a bespoke, non-Argo "pointer
file" format that real Argo semantics cannot turn into a child Application — the fifth round fixed
that using App-of-Apps, Argo's own native mechanism for a root Application generating children. The
sixth round closed three further bounded gaps in that App-of-Apps mechanism: unsupported
Helm/source overrides on the checked-in child manifest, a recursive/non-recursive mismatch between
discovery and the emitted root config, and hollow (template-free) workload-manifest proof. The
seventh round (immediately below) corrects the workload-manifest rendering CONTEXT itself: the
shared renderer used the release record's own `releaseId` as the Helm release name and no namespace
at all, neither of which is what a real Argo sync would actually use. DEF-005 (the multi-source
values lookup fix) was correct in the fourth round and is unchanged. These address
`docs/DEFERRED-WORK.md`'s DEF-005/DEF-006 entries. **Still not marked COMPLETE** — GO-1 remains `IN
PROGRESS` pending owner re-review; GO-2 remains inactive; ADR 0026/0027 remain Proposed.

## Corrections applied — seventh round (rendering-context correction: Helm release name/namespace, 2026-09-15)

1. **The workload-manifest rendering context did not match what a real Argo sync would use.**
   `gob_render_workload_manifests` called `helm template` with the release record's own `releaseId`
   as the Helm release name and no `--namespace` — but a real Argo sync of the child Application
   renders its chart with `.Release.Name` set to the Application's own `metadata.name` and
   `.Release.Namespace` set to `spec.destination.namespace`; Argo has no knowledge of `releaseId` at
   all (it is a `render-gitops-*` release-record convention, not an Argo/Helm concept). Any template
   using `.Release.Name`/`.Release.Namespace` (a very common pattern — resource naming, namespace
   scoping, common labels) would therefore render under this tooling's proof step with a DIFFERENT
   context than a real sync would use, silently.
2. **Fixed by deriving and validating that context from the child Application itself.**
   `gob_render_workload_manifests` now takes an explicit `release_name`/`namespace` pair (each
   checked by a new `gob_require_dns_label` against real Helm/Kubernetes naming rules) instead of
   assuming `releaseId` doubles as the release name. `render-gitops-applications.sh` derives that
   pair from the checked-in child manifest — `metadata.name` and `spec.destination.namespace` — and
   `gob_validate_child_manifest` now also validates `spec.destination.namespace` against the
   `bedoux-<environment>` convention (derived from the release record) and `spec.destination.server`
   against the expected in-cluster server, so neither is trusted blindly. `render-gitops-release.sh`,
   which has no Application to derive a namespace from, passes an empty namespace through unchanged
   (matching `helm template`'s own "default" default) and keeps `releaseId` as its release name,
   since there is no Application identity to prefer there.
3. **Proven with real `.Release.Name`/`.Release.Namespace` templates and exact-value assertions.**
   Both renderer test suites' scratch charts now include those fields in their Deployment templates
   (a `release:` label and a `namespace:` field) and assert the EXACT rendered value — for
   `render-gitops-applications.sh`, `.Release.Name` is the child's own name (`dev-child`), explicitly
   NOT the release record's `releaseId` (`dev-0001`), and `.Release.Namespace` is the child's
   `spec.destination.namespace` (`bedoux-dev`); for `render-gitops-release.sh`, `.Release.Name` is
   `releaseId` and `.Release.Namespace` is `helm template`'s own default `default`. A new
   mismatched-namespace negative test proves the new validation actually rejects a
   `spec.destination.namespace` that does not match the `bedoux-<environment>` convention.
4. Proven by `scripts/test-render-gitops-applications.sh` (58 assertions, up from 54: the two exact
   rendering-context assertions and the mismatched-namespace negative test are new) and
   `scripts/test-render-gitops-release.sh` (23 assertions, up from 21: the two exact
   rendering-context assertions are new). All previously accepted DEF-005/DEF-006/sixth-round fixes
   are unchanged and still pass. Both suites remain wired into
   `.github/workflows/pr-validation.yml` and green in CI.

## Corrections applied — sixth round (three bounded gaps in the App-of-Apps mechanism, 2026-09-14, later same day)

1. **Unsupported Helm/source overrides were neither rejected nor rendered.** The structural
   validator checked only the fields it actively compared (repoURL/targetRevision/path/
   helm.valueFiles on the chart source; repoURL/targetRevision/ref on the values-only source) but
   never rejected anything else a checked-in manifest might declare — `helm.parameters`,
   `helm.values`/`valuesObject`, `kustomize`, `directory`, `plugin`, a Helm-repo `chart` reference.
   A real Argo sync would apply any of these; this tooling's own `helm template` proof step silently
   ignored them, so a passing render could prove an effective output different from what Argo would
   actually produce. `gob_validate_child_manifest` now enforces an explicit key allowlist on both
   sources and refuses closed on anything outside it.
2. **Root-file discovery did not match the emitted root Application's own configuration.**
   Discovery used `git ls-tree -r` (recursive), but the rendered root Application carries no
   `directory: {recurse: true}` — Argo's default for a directory-style source is non-recursive. A
   nested child manifest this script found and rendered would, in reality, never be synced by Argo
   at all. Discovery is now non-recursive (`git ls-tree` at exactly one level under `--root-path`),
   refuses a nested subdirectory by name instead of silently traversing into or ignoring it, and
   refuses ANY additional entry found alongside the one child manifest — not just additional
   `kind: Application` files — since a real Argo sync of a non-recursive directory source applies
   every resource it finds there, not only ones that happen to be Applications.
3. **The workload-manifest proof was hollow.** Both renderer test suites' scratch Helm charts had no
   templates (or, for `render-gitops-release.sh`, only a one-sided API template), so `helm template`
   produced an empty/NOTES-only banner — "resolved pinned chart/values → workload manifests" was
   proven only by exit code 0, never by actual rendered content. Both suites now render real API and
   web `Deployment` templates and assert the workload manifests contain the pinned
   `repository@digest` for both images. A new test in `scripts/test-render-gitops-applications.sh`
   demonstrates a reviewed child-pin update (a fresh checked-in child manifest pointing at a new,
   reviewed release with different image digests, same appRevision — modeling a real promotion)
   changes the rendered workload output at the new pin, while re-rendering at the previous,
   already-reviewed root pin remains byte-identical to its original render — a later promotion never
   retroactively changes an earlier, already-approved render.
4. Proven by `scripts/test-render-gitops-applications.sh` (54 assertions, up from 36:
   unsupported-Helm-override, nested-directory, unexpected-resource, and the child-pin-update
   demonstration are new) and `scripts/test-render-gitops-release.sh` (21 assertions, up from 19:
   real web template plus workload-content assertions). Both suites remain wired into
   `.github/workflows/pr-validation.yml` and green in CI.

1. **The fourth round's DEF-006 fix did not use an actual Argo-supported generation mechanism.**
   `--root-path` pointed at a directory containing a bespoke YAML document
   (`childAppName`/`releaseRecordPath`/`valuesPath`) that only `render-gitops-applications.sh`
   itself knew how to interpret. The rendered root Application's own `source.path` was set to that
   same directory — but a real Argo CD sync of that root would try to apply the pointer file itself
   as a Kubernetes resource. It is not a valid `Application` manifest, so nothing in actual Argo
   semantics would turn it into the child. The root and child text this script emitted were only two
   independently parameterized renders that happened to agree with each other; nothing about them
   proved the root's own source produces the child through any mechanism Argo itself implements.
   `docs/DEFERRED-WORK.md`'s DEF-006 entry carries a correction note reopening it for this reason.
2. **Fixed via App-of-Apps — Argo's own native root-generates-children mechanism.** A root
   Application whose `source.path` is a directory of other, already-rendered `Application` manifests
   is a real, first-class Argo CD pattern (no ApplicationSet/CRD needed): a sync of the root applies
   whatever valid `Application` manifests it finds there, verbatim. `--root-path` must now contain,
   at `--env-revision`, exactly one such checked-in child `Application` manifest — the same kind of
   artifact a real "prepare release" step would commit into the env-repo
   (`docs/gitops-fixtures/dev-root-child-application.example.yaml` is the current worked example;
   the prior pointer-file fixture is kept, with its own correction note, per the append-only
   convention). `render-gitops-applications.sh` discovers that manifest and prints it verbatim as the
   child — it does not re-template it.
3. **Structural, not line-adjacency, validation — and it fails closed on tampering.** The checked-in
   child manifest carries two provenance annotations (`gitops.bedoux/release-record-path`,
   `gitops.bedoux/values-path`), resolved at the manifest's OWN values-only source
   `targetRevision` — never assumed equal to the caller's `--env-revision`, since a checked-in file
   cannot contain the hash of the commit that first introduces it. That revision must be a
   well-formed, existing, non-moving commit SHA that is an ancestor-or-equal of `--env-revision`
   (`git merge-base --is-ancestor`), refused otherwise. `scripts/lib/gitops-release-binding.sh`'s new
   `gob_validate_child_manifest` then parses the checked-in manifest's `spec.sources` as real YAML
   (not raw text) and structurally cross-checks every field — `repoURL`/`targetRevision`/`path`/
   `helm.valueFiles` on the chart source, `repoURL`/`targetRevision`/`ref`/absence-of-`path` on the
   values-only source — against the independently-derived release binding, failing closed on any
   mismatch, including a `path` deliberately injected onto the values-only source (proven by a
   dedicated negative test, not just the general field-comparison).
4. **Proves the full local chain: pinned root source → generated child → resolved pinned
   chart/values → workload manifests.** `scripts/lib/gitops-release-binding.sh`'s new
   `gob_render_workload_manifests` (the extraction + `helm template` step, now shared by both
   `render-gitops-release.sh` and `render-gitops-applications.sh` rather than duplicated) runs after
   the structural cross-check succeeds, so a single invocation of
   `scripts/render-gitops-applications.sh` demonstrates every link in that chain end to end, locally,
   with no cluster.
5. **New negative tests.** Broken-root (YAML present under `--root-path` but none of it a valid
   `Application` manifest — refused, naming what a real Argo sync would also refuse to reconcile)
   and a moving-branch test (re-rendering at the same pinned `--env-revision` after the scratch
   repo's branch advances is byte-identical; explicit rendering at the new revision differs), in
   addition to the retained zero/multiple-child-manifest, missing-annotation, and shared
   image-digest-mismatch tests. `scripts/test-render-gitops-applications.sh` now has 36 assertions.
6. **Both renderer test suites wired into CI.** `.github/workflows/pr-validation.yml`'s "Terraform
   and Helm validation" job (which already installs Helm) now runs
   `scripts/test-render-gitops-release.sh` and `scripts/test-render-gitops-applications.sh`
   (plus `--help`/`bash -n` smoke checks on both renderer scripts and the shared library) on every
   PR; confirmed green in CI for this change.

## Corrections applied — fourth round (DEF-005/DEF-006 fix, 2026-09-14)

1. **DEF-005 — multi-source values lookup was actually broken.** The child Application's
   values-only source set `path: env` (the values file's directory) AND `helm.valueFiles` referenced
   only the basename (`$values/values.yaml`). Per Argo's own multi-source semantics, `helm.valueFiles`
   entries using the `$values/...` ref convention are resolved from the REPO ROOT of the ref'd
   source, not from that source's `path` — so `$values/values.yaml` looked for a file at the repo
   root, never at the real `env/values.yaml`. Setting `path` on a `ref`-only source additionally
   makes Argo treat it as a second manifest-generating source, not a pure values reference — the
   "unintended resource generation" DEF-005 named. Fixed in `scripts/render-gitops-applications.sh`:
   the values-only source now carries only `repoURL`/`targetRevision`/`ref` (no `path`), and
   `helm.valueFiles` references the full repo-relative path (`$values/env/values.yaml`). Proven by
   `scripts/test-render-gitops-applications.sh`'s two DEF-005 assertions (full-path `valueFiles`
   reference; no `path:` under the `ref: values` source).
2. **DEF-006 — root-to-child generation was asserted, not proven, and validation was duplicated,
   not reused.** `render-gitops-applications.sh` previously took `--release-record-path`,
   `--values-path` and `--child-app-name` directly as caller-supplied flags — identical in spirit to
   the caller just writing out both Applications by hand; nothing about the render actually
   depended on the root's own source producing that specific child. Separately, it re-implemented
   release-record parsing inline instead of calling `render-gitops-release.sh`'s binding logic
   despite an earlier header comment claiming it did, and never checked `pairedAppRevision` or
   image repository/digest consistency at all — a mismatched image would have rendered without
   error. Both fixed together: `--root-path` is now read as a directory, AT THE PINNED
   `--env-revision`, that must contain exactly one child pointer YAML file (see
   `docs/gitops-fixtures/dev-root-child-pointer.example.yaml`); the script reads that pointer to
   discover `childAppName`/`releaseRecordPath`/`valuesPath` and generates the child from it — this
   is the root's own source actually producing the child, not two independently parameterized
   renders. Release-record/values parsing, appRevision/chart-path verification, and the
   `pairedAppRevision`/image repository/digest cross-check now live in
   `scripts/lib/gitops-release-binding.sh`, sourced by BOTH `render-gitops-release.sh` and
   `render-gitops-applications.sh` — genuinely shared, not just documented as shared. Zero or
   multiple pointer files under `--root-path` are refused by name (multi-child fan-out/real
   App-of-Apps enumeration remains explicitly out of scope — DEF-006's safe boundary while it was
   deferred, still true post-fix: this proves ONE root producing ONE child, not enumeration across
   many). Proven by `scripts/test-render-gitops-applications.sh` (33 assertions, up from 27):
   root/child pinning and the moving-HEAD negative test as before, plus zero-pointer refusal,
   multiple-pointer refusal naming fan-out as out of scope, a pointer file missing a required
   field, and — reusing the shared validation — an image-digest-mismatch fixture reached through
   the root/pointer path that the pre-fix script would have rendered without error.
3. **Reconciling the third round's "Application generation mechanism" claim below:** the
   third-round entry (see below) describes `render-gitops-applications.sh` as "the concrete answer
   to 'prove how the root passes the same immutable env revision.'" That was true only for the
   env-revision PIN (both sources really were pinned to the same SHA); it was not yet true for
   root-to-child GENERATION (the child's identity/paths came from the caller, not the root's
   source) — this round's fix closes that remaining gap. The third-round text below is left
   unchanged per this document's append-only convention; this note is the correction.

## Corrections applied — third round (Codex's second follow-up review, 2026-09-09T14:37:25-06:00)

1. **First-attempt authorization was still replayable.** The bootstrap-precondition checker is a
   read-only predicate over `status/<environment>.yaml`; running it twice with nothing recorded in
   between legitimately returns the same answer both times, which is correct for a read-only
   predicate but is not, by itself, proof that no deployment attempt is already in flight or
   crashed mid-attempt. Added a SEPARATE, durable primitive — `scripts/gitops_release_attempt_claim.py`
   (`claim`/`consume`), an atomic create-if-absent claim file keyed on `(environment, releaseId)` —
   plus an optional defense-in-depth `--claims-dir` check in the checker itself. See Gate 6a below.
2. **The paired-Rollout coordination design did not preserve its own stated failure contract.**
   Sequential promote calls and matching step indices were treated as sufficient evidence of a
   correct paired promotion; a crash/second-call failure could leave `api` ahead of `web` with no
   automatic-abort path back to it. Rewrote the coordinator's decision logic
   (`scripts/gitops_paired_rollout_coordinator_model.py`) to check divergence/health before anything
   else, require a fresh post-promote health observation (not just an advanced step index) before
   promoting the second Rollout, always abort BOTH candidates together on any failure, and added
   explicit coordinator ownership/fencing (a bounded-TTL lease) plus a named Traefik validation
   adapter. See Gate 4b below.
3. **The actual root/child Application binding mechanism remained unspecified.** The renderer pins
   local Git inputs but never generated an actual Argo `Application`, and the contract still
   suggested tracking env `HEAD` rather than proving an immutable pin. Chose a multi-source Argo CD
   `Application` as the mechanism and added `scripts/render-gitops-applications.sh`, which pins BOTH
   the root's own source and the child's env-values source to the exact same `--env-revision`,
   including a moving-HEAD negative test. See Gate 1 above.
4. **Incomplete binding/shape validation.** The binding renderer cross-checked image digests but not
   repository identity (a matching digest under a different, unreviewed repository rendered
   successfully); the suspension script's Application-shape check accepted a truncated response with
   no `.spec` at all. Both are now mandatory, verified checks. See Gate 1 and Gate 6b below.
5. **Documentation correction:** Gate 6a's `signature-rejection` classification claimed nothing ever
   touches the database — not generally true, since a migration Job at wave 0 can genuinely succeed
   before a wave-1 image is rejected by the signature verifier. Corrected in Gate 6a below.

All five were reproduced exactly (where the review supplied a reproduction) and proven fixed with
new/expanded local, no-cluster test suites — see each gate's "Local, no-cluster evidence" for exact
assertion counts and commands.

## Corrections applied — second round (Codex's follow-up review, 2026-09-09T13:29:08-06:00)

1. **Suspend script still reported false success.** The final verification step mapped *every*
   nonzero `jq -e` result to "automated field absent" — so a genuine `jq` processing failure
   (reproduced with a targeted mock: phase `Succeeded`, `argocd` calls all succeed, the
   Application genuinely still has `automated: {}`, but `jq` fails specifically on that one
   filter) was indistinguishable from "confirmed suspended," and was reported as success. The
   script also checked for in-flight operations *before* disabling automation, leaving a race
   where self-heal could start a new operation in the gap, and never examined `.operation` (a
   queued-but-not-yet-started request), only `.status.operationState.phase`. **Fixed:**
   automation is now disabled FIRST; a new `wait_for_quiescence` checks BOTH `.operation` and
   `.status.operationState.phase`; every field extraction distinguishes "jq/command failed"
   from "field legitimately null" via an explicit `== null` check rather than `-e` exit-code
   inference; every response is validated as Application-shaped JSON (`.metadata.name` must
   match) before any field is trusted. `scripts/test-gitops-suspend-reconciliation.sh` grew from
   3 to 6 scenarios (10 → 18 assertions), including a direct reproduction of the exact targeted
   jq-failure counterexample and a proof that the FIRST `--sync-policy none` call happens before
   the first quiescence check. A genuine bug in the test harness itself was also found and fixed
   along the way: `log()` wrote to stdout, so diagnostic messages logged from inside a function
   invoked via command substitution were being silently absorbed into the captured return value
   instead of appearing at all — moved to stderr.
2. **Binding gate remained partial.** The renderer proved app/chart pinning but read values from
   an arbitrary live path, `pairedAppRevision` was optional (skippable), and nothing pinned or
   verified an *environment* revision — a values file with the correct `pairedAppRevision` but a
   completely different, unreviewed image digest rendered successfully. **Fixed:**
   `scripts/render-gitops-release.sh` now requires `--env-revision` (a verified commit) and reads
   BOTH the release record and the values file via `git show <env-revision>:<path>` — never a
   live path; `pairedAppRevision` is now mandatory; each image's digest in the values file is
   cross-checked against the release record's own declared digest for that image, refused on any
   mismatch. (An initial attempt also had the release record self-declare and cross-check its
   own containing commit's hash — removed as logically circular; a commit's hash is a property
   of history, not content a file inside that commit can usefully self-reference.)
   `scripts/test-render-gitops-release.sh` now builds an isolated scratch git repo (so it never
   depends on anything being committed to this actual repository) and proves, with 17
   assertions: the positive case; working-tree independence; a real reproduction of the
   mismatched-digest counterexample; `pairedAppRevision` missing (refused) and present-but-wrong
   (refused, distinctly); and that `--env-revision` is genuinely honored (the same paths at an
   earlier commit, before the env content existed, are correctly refused).
3. **First-bootstrap contradiction.** The design has every promotion write a `pending` entry for
   its own releaseId in the same PR — but the checker refused *every* `pending` outcome
   unconditionally, meaning a brand-new environment's first-ever release could never bootstrap at
   all, even with `--allow-first-bootstrap` (which only ever covered the *empty-history* case, not
   an existing `pending` entry). **Fixed:** `pending` now proceeds when it is the sole,
   first-ever entry recorded for that exact releaseId (a reviewed promotion PR is itself the
   approval to attempt it — there is nothing further to confirm before a first try), but still
   refuses, with its own distinct exit code, if more than one entry exists for that releaseId (a
   replay/re-approval of something already attempted). A new `unknown` outcome was added for
   "attempted, but its result was never durably confirmed" (e.g. cluster lost mid-check) —
   always refused, never eligible for the first-attempt bypass, since something already happened
   and its result is uncertain, the opposite of genuinely fresh. `scripts/gitops_bootstrap_precondition_check.py`
   and its test suite (19 assertions, up from 14) were both rewritten accordingly. The migration
   Job fixture also now states explicitly: deleting a failed Job while its release record is
   still current would let self-heal (which stays enabled) recreate and retry it — cleanup is
   only safe after a new reviewed release record supersedes it.
4. **Paired API/web coordination completed as a real design (Gate 4b below), not left as "GO-6's
   own design gate."** A lockstep external coordinator — not two independently-analyzing
   Rollouts — is now the specified mechanism, reusing P13's already-proven paired health checks
   and Gate 6a's existing hold/recovery mechanism rather than inventing new ones.
5. **Router decision made:** Traefik, per explicit owner direction — see Gate 3.

## Corrections applied — first round (Codex's initial GO-1 review)

An independent review (Codex, `docs/PROGRESS.md` session log 2026-09-09T11:03:16-06:00) found
that the first COMPLETE claim was not supported by the actual evidence. Every finding was
addressed with a real fix and a reproducible local test, not just a rewritten claim:

1. **Suspend script silently succeeded under total command failure.** `scripts/gitops-suspend-reconciliation.sh`
   relied on `set -e` inside a function called as `f "$app" || fail=1` — bash suspends errexit
   for the entire call in that context, and the script never checked any individual `argocd`/`jq`
   exit code itself. Mocking both commands to always fail still printed "verified suspended" and
   exited 0; a mocked stuck `Terminating` phase did too. **Fixed:** every external command now
   goes through explicit exit-code-checked helpers (`run_argocd`, `run_jq`), an unrecognized or
   undetermined phase is treated as unsafe by default (not just "not Running"), and termination
   is re-verified after a forced `terminate-op` before suspending. **Tested:**
   `scripts/test-gitops-suspend-reconciliation.sh` reproduces both original failure modes plus a
   full success path with root-before-children ordering proof — all against mock `argocd`/`jq`
   binaries, no cluster contact.
2. **Rejected-release predicate could be bypassed.** The original design let a still-selected
   `rejected` releaseId through if some *other, later* releaseId in the same history happened to
   be `healthy` — `supersededBy` was wrongly treated as a live authorization instead of audit
   metadata. **Fixed:** `scripts/gitops_bootstrap_precondition_check.py` looks up only the
   release record's current releaseId and is fail-closed: it proceeds only on an explicit
   `healthy` entry for that exact releaseId; `rejected`, `pending`, and no-entry-at-all (the
   "missing evidence" gap Codex specifically flagged) all refuse. **Tested:**
   `scripts/test_gitops_bootstrap_precondition.py` reproduces the exact bug (a release record
   still naming `dev-0001` is refused despite `dev-0002` being healthy elsewhere) and covers
   `pending`, missing-entry, missing-file, empty-history, malformed-outcome and
   environment-mismatch cases — 14 assertions, all passing.
3. **Binding "evidence" never touched the release record.** The original `helm template` run
   only consumed the values fixture against the live working tree — it never read `appRevision`
   or proved anything about revision pinning. **Fixed:** `scripts/render-gitops-release.sh`
   resolves `appRevision` to an actual git commit and extracts the chart via `git archive` at
   that exact commit, refusing on invalid syntax, a nonexistent commit, or a values file whose
   `pairedAppRevision` doesn't match. **Tested:**
   `scripts/test-render-gitops-release.sh` proves the pinned render is byte-identical whether the
   working tree is clean or deliberately dirtied (a tracked file's live edit does not leak into
   the render), and exercises all three refusal paths.
4. **Fixture data errors.** `appRevision` was not valid hex; image digests were 60 characters,
   not the required 64 for SHA256. **Fixed:** `appRevision` is now this repository's real HEAD
   commit at fixture-authoring time (`2c1ec6b0aab1f1ea8d9612367831270719841f03`); digests are
   real, computed 64-character SHA256 hex strings.
5. **Migration fixture omitted database credential env vars** (would have defaulted to
   `localhost`) **and didn't list the ServiceAccount as a wave -1 prerequisite.** Fixed in
   `docs/gitops-fixtures/gitops-migration-job.example.yaml`; failed-Job retention is now an
   explicit stated decision (kept indefinitely, matching ADR 0005's precedent) rather than left
   unaddressed.
6. **Controller/router versions were never actually pinned**, despite GO-1's task-table
   requirement to do so. Fixed below (Gate 3) with researched, cited current versions.
7. **Platform exceptions expired only on version bump, not on a calendar date**, and
   **ingress-nginx was treated as a viable pin without checking its status** — it is in fact
   past its own announced retirement window. Fixed below (Gate 3).
8. **T-GO-01–08 were referenced but never indexed in `docs/TEST-PLAN.md`.** Fixed —
   see that file's new "T-GO-0x" section.
9. **`START-HERE.md` still said GO-1 was not started.** Fixed.

GO-1's own Gate 2 failure-semantics correction (operation status vs. resource health vs. retry
behavior are three separate things) and the Kyverno-deprecation retraction from the prior round
both stand unchanged; Codex's review did not dispute either.

Owner activated GO-1 on 2026-09-09 (`docs/PROGRESS.md` session log
2026-09-09T10:28:51-06:00) and then resolved all six named design gates with explicit
corrections to the drafted options; this document records those decisions as the design
contract, not as a re-opened discussion. Read `docs/gitops-expansion-plan.md` and
[Proposed ADR 0026](decisions/0026-two-repository-argocd-delivery.md) first for the
owner-confirmed choices this contract builds on (Argo CD, two-repository split, single kind
cluster first, etc.) — those are settled and not re-litigated here.

GO-1's scope per `docs/gitops-expansion-plan.md`'s task table is "review ADR 0026; finalize
source/binding rendering, migration order, signature verifier and paired-rollout design; pin
supported controller/router versions; **no installation**." Its acceptance evidence (T-GO-01) is
"ownership/trust map, rendered fixture validation, explicit ADR supersession and recovery
contracts; unresolved design choices block dependent tasks." This document plus the fixtures
under `docs/gitops-fixtures/` and `scripts/gitops-suspend-reconciliation.sh` are that evidence.

## How to read "evidence" in this document

Two different kinds of evidence appear below, and they are not interchangeable:

- **Design evidence (produced now, locally, no cluster/AWS contact)** — a fixture that renders
  or validates with real tooling (`helm template`, YAML/schema checks), a script whose
  `--help`/`--dry-run` paths run and are checked in, a written contract with no ambiguity left
  for the implementer. This is what GO-1 can actually produce.
- **Deferred cluster evidence (a later GO-# task, named by its T-GO-0x id)** — anything that
  requires an installed controller, a live sync, a real failure injection, or a real
  restart/recovery. GO-1 does not claim this evidence exists. Where a design choice here implies
  a specific future test, that test is named explicitly so nothing is silently assumed proven.

## Ownership and trust map

| Resource / scope | Owner today | Owner after GO-1 design (before GO-3 implementation) | Notes |
|---|---|---|---|
| `bedoux` namespace, all AWS/kind profiles, `charts/bedoux` Helm release `bedoux` | `scripts/p13-canary-rollout.sh` + operator `helm upgrade --atomic` | **Unchanged.** Stays fully outside Argo's scope through GO-1–GO-5 (Gate 4). | Zero overlap by design — see Gate 4. |
| `bedoux-dev` namespace | Does not exist | Reserved for Argo (GO-3 creates it) | New, GitOps-only. |
| `bedoux-staging` namespace | Does not exist | Reserved for Argo (GO-3 creates it) | New, GitOps-only. |
| `charts/bedoux` chart source (this repo) | This repo's own history/PRs | Unchanged as source; read at a pinned Git SHA by Argo (Gate 1) for GitOps environments only | Chart itself needs no Argo-specific fork; same source, two consumption paths. |
| `bedoux-commerce-env` repo (not yet created — GO-2) | N/A | Owner reviews/merges every PR; Argo reads it read-only via a scoped deploy key (Gate 5) | Creation is GO-2, not GO-1. |
| Migration Job, legacy path | Helm `post-install,pre-upgrade` hook, ADR 0005 | **Unchanged** for the legacy path | ADR 0005 stays Accepted as-is. |
| Migration Job, GitOps path | N/A | Argo sync-wave 0, `releaseId`-keyed name (Gate 2, ADR 0027 Proposed) | Design fixture: `docs/gitops-fixtures/gitops-migration-job.example.yaml`. Not wired into the chart yet — GO-3. |
| Deployment-time signature verification | None (CI-only Cosign check today) | Sigstore `policy-controller`, enforce mode, scoped platform exceptions (Gate 3) | Not installed. GO-3/GO-4 install and prove. |
| ALB/Ingress shared routing resources (`Ingress`, ALB listener rules) | AWS Load Balancer Controller reconciles what the `bedoux` Helm release declares | **Unchanged** while the `bedoux` release stays outside Argo | GitOps environments get their own `Ingress` objects in `bedoux-dev`/`bedoux-staging`, never editing the legacy release's Ingress. AWS/EKS profile unaffected by the router decision below. |
| Local kind router (GitOps environments only) | ingress-nginx (legacy `bedoux` release, unaffected) | Traefik v3.7.13 (Gate 3), `TraefikService`/`weightedTraefikServiceName` for future paired canary weighting (Gate 4b) | Not installed. GO-3 installs; GO-6 wires Rollouts to it. |
| Argo reconciliation state (root + children) | N/A | Owner-scripted suspend via `scripts/gitops-suspend-reconciliation.sh` (disable-before-wait per app, root before children, mandatory `.spec` shape check) (Gate 6b) | Script rewritten, mock-tested (21 assertions); live use is GO-3+. |
| Root/child Argo `Application` generation | N/A | Multi-source `Application`; root's own source AND the child's env-values source both pinned to the same exact `--env-revision` (Gate 1) | `scripts/render-gitops-applications.sh` (27 assertions, incl. moving-HEAD negative test); not applied to any cluster — GO-2/GO-3. |
| Deployment attempt serialization (`(environment, releaseId)`) | N/A | Atomic create-if-absent claim file, `scripts/gitops_release_attempt_claim.py` (Gate 6a) | 15 assertions; real mapping is `kubectl create configmap claim-<env>-<releaseId>` — GO-3 wiring, not built here. |
| Release-outcome durable record (`status/<env>.yaml` in env repo) | N/A | Written by promotion PRs (`pending`) and Git-repair PRs (`healthy`/`rejected`/`unknown`) (Gate 6a) | Design fixture: `docs/gitops-fixtures/dev-status.example.yaml`. Checked by `scripts/gitops_bootstrap_precondition_check.py` (24 assertions); not wired into a live bootstrap flow yet. |
| Rollout step advancement, `api` + `web` (future, GO-6) | N/A | A single external coordinator only (`gitops-paired-rollout-promote.sh`, design-specified — Gate 4b); neither Rollout auto-advances itself; fencing via a bounded-TTL lease | Reuses P13's existing paired-health-check scripts (plus a new named Traefik adapter, `p13-traefik-reconciliation-gate.sh`) and Gate 6a's status record for holds. Decision model tested locally (`gitops_paired_rollout_coordinator_model.py`, 15 assertions). Not built — GO-6. |

## Gate 1 — Release binding

**Decision:** Git-SHA-pinned chart source now; OCI chart packaging stays deferred (matches
`docs/gitops-expansion-plan.md:271`, which is itself still Proposed via ADR 0026 — not treated
as accepted by this sentence). The binding gate is closed by a structural property, not by
pinning the chart alone: a single `bedoux-commerce-env` commit is the atomic release unit. That
commit's own SHA *is* the env-values revision, and the fields inside its release-record file name
the exact `bedoux-commerce-cloud` commit SHA to render the chart at. Both facts are reviewed and
merged together in one PR — there is no path to change one without the other being present in the
same diff. Worked example: `docs/gitops-fixtures/dev-release-record.example.yaml` (the pinned
`appRevision` + image digests + `releaseId`) paired with
`docs/gitops-fixtures/dev-values.example.yaml` (the plain Helm values overlay committed alongside
it).

**Argo's read credential for this repo:** two separate read-only deploy keys, one per repository
(app repo, env repo), distinct from the GitHub App used for environment PR automation. This is a
plain, repository-scoped credential choice — deploy keys are not claimed to be categorically more
secure than a narrowly scoped GitHub App installation token; they were chosen for simplicity (one
key, one repo, no installation/app-registration step) and because Argo's own repository-credential
model is deploy-key-native. See Gate 5 for storage, rotation, revocation and SSH host-key
verification.

**Design evidence, produced now — third-round additions (repository-identity check, Application
generation mechanism; see "Corrections applied — third round" above):**
- `scripts/render-gitops-release.sh` requires an explicit, verified `--env-revision` commit and
  reads BOTH the release record and the values file from that exact commit via `git show`, never
  from a live filesystem path. It cross-checks, for each of api/web, independently: **repository**
  (values file's `image.repository` against the release record's declared image repository — new
  this round; a matching digest under a *different* repository is refused, closing the exact
  counterexample Codex's third review reproduced) and **digest** (values file's `image.digest`
  against the release record's declared digest); plus `pairedAppRevision` (mandatory) against the
  release record's `appRevision`. It then extracts the chart from `appRevision` via `git archive`
  and renders.
- `scripts/test-render-gitops-release.sh` (19 assertions, up from 17) adds the exact
  mismatched-repository-with-correct-digest counterexample (now refused, distinctly from a
  mismatched digest) to the existing suite (positive case; working-tree independence; mismatched
  digest; `pairedAppRevision` missing/wrong; invalid/nonexistent env-revision; `--env-revision`
  genuinely honored, not accepted-and-ignored).
- **Application generation mechanism, chosen this round (previously an open/deferred detail):
  multi-source Argo CD `Application`** (`spec.sources: [...]`) — Argo's own native mechanism for
  pairing a chart source with a values-only source, needing no additional generator/controller.
  ApplicationSet was considered and not chosen: its git generator needs the exact same
  pin-to-a-commit discipline this design already provides directly, for no benefit at today's
  scale (one root/child pairing per environment, not a fan-out across many near-identical
  environments). New `scripts/render-gitops-applications.sh` renders BOTH the root Application
  (`spec.source.targetRevision` pinned to the exact `--env-revision`) and the child Application
  (`spec.sources[0].targetRevision` pinned to the release record's `appRevision`;
  `spec.sources[1].targetRevision`, the values-only source, pinned to the SAME exact
  `--env-revision` as the root) — the concrete answer to "prove how the root passes the same
  immutable env revision" (expansion-plan lines 251-255). Explicitly refuses the literal strings
  `HEAD`/`main`/`master`/`origin/*`/`refs/*` by name (not just via the generic SHA-format check),
  so a caller gets a legible "this is a moving reference" error rather than a bare format error.
- `scripts/test-render-gitops-applications.sh` (27 assertions) builds an isolated scratch git
  repository and proves: both Applications render with every `targetRevision` pinned to an exact
  commit SHA (never `HEAD`); **the moving-HEAD negative test** — re-rendering at the SAME,
  already-pinned env-revision AFTER the scratch repo's branch has moved forward to a later commit
  produces **byte-identical output** to the original render, proving the tool never implicitly
  re-resolves to "whatever HEAD is now"; rendering EXPLICITLY at the new, later revision correctly
  picks up its different content (proving the tool is revision-scoped, not simply stuck/broken);
  the named moving-reference strings are all refused before touching git; a nonexistent commit and
  a release record missing `appRevision` are both refused.
- Fixture data (`docs/gitops-fixtures/`) was corrected: `appRevision` is a real 40-hex-character
  git SHA (this repository's HEAD at authoring time, `2c1ec6b0aab1f1ea8d9612367831270719841f03`);
  image digests are real, computed 64-character SHA256 hex strings; `api.image.repository` /
  `web.image.repository` are present and consistent with the release record's own `images.*`
  fields. These fixtures document the intended real-repo usage for GO-2/GO-3; end-to-end proof
  against this exact repository's own history additionally requires these files to actually be
  committed, which is why both test suites use an isolated scratch repo to exercise the full
  mechanism today without depending on that.
- All four Gate 1/2 fixture files still pass `yaml.safe_load` (real parse, not eyeballed).

**Deferred cluster evidence:** an actual Argo `Application` resolving this pairing LIVE (as opposed
to rendered/proven locally above), and proof that changing only one half (chart SHA or values)
without the other is impossible through Argo's own reconciliation — T-GO-01's "rendered fixture
validation" is satisfied above; live binding proof is T-GO-02 (repository boundary, credentials,
exact source-revision traceability) and T-GO-03 (fresh install).

## Gate 2 — Migration ordering

**Decision (overriding the earlier unconditional PreSync recommendation):** health-gated Argo
sync waves, not a PreSync hook. PreSync hooks apply before ordinary resources regardless of
negative sync-wave numbers on those resources — exactly the same class of ordering bug ADR 0005
already caught once for Helm's `pre-install`, now recurring under a different mechanism. Using
sync waves instead makes prerequisite health an explicit, checkable gate rather than an assumed
ordering:

- Wave -1: DB/Secret/ServiceAccount prerequisites — the existing `postgres`
  StatefulSet/Service/Secret **and** the `bedoux-api` ServiceAccount the migration Job's
  `spec.serviceAccountName` references (added per Codex's review — the first fixture version
  omitted it, and a Job cannot start without its ServiceAccount existing). Must be Argo-Healthy
  before wave 0 applies.
- Wave 0: the migration `Job`, a normal (non-hook) managed resource, gated by Argo's built-in Job
  health check (`status.conditions[Complete]=True`).
- Wave 1: `api`/`web` Deployments, unchanged.

Job identity is the reviewed release record's `releaseId`, never `.Release.Revision` (Argo's Helm
rendering has no stable equivalent — this was the concrete bug in the original recommendation).
Re-syncing the same release record targets the same Job name: a succeeded Job produces no diff; a
terminally failed Job (`backoffLimit` exhausted) leaves the Application Degraded at wave 0 and is
never recreated by routine reconciliation — only a new reviewed release record (new `releaseId`)
produces a new attempt. Forward-only migrations, no automatic downgrade, are preserved by never
invoking `alembic downgrade` in this path, matching ADR 0005's own non-feature.

CI-run migration is rejected: it would require giving the "Prepare release" CI action live
network access and credentials to the target database, which contradicts this track's goal of
removing routine cluster/data-plane credentials from CI once Argo owns deployment.

This is recorded as **[Proposed ADR 0027](decisions/0027-gitops-profile-migration-jobs.md)**,
superseding ADR 0005 **only for GitOps-managed environments** — the legacy Helm/P13 path keeps
ADR 0005 exactly as accepted, unchanged.

**Design evidence, produced now:**
- `docs/gitops-fixtures/gitops-migration-job.example.yaml` — valid YAML, checked programmatically
  for: `sync-wave: "0"` annotation present, no `helm.sh/hook*` annotations, `backoffLimit: 2` /
  `activeDeadlineSeconds: 120` (matching today's `charts/bedoux/values.yaml` migration defaults),
  `restartPolicy: Never`, name keyed on `releaseId` not `.Release.Revision`.
- Corrected per Codex's review: both containers now carry the real database-credential env block
  (`BEDOUX_DATABASE_URL` from the `postgres-credentials` Secret, matching
  `charts/bedoux/templates/_helpers.tpl`'s `bedoux.databaseCredentialEnv` in this project's
  default `kubernetes-secret` mode) — the previous version omitted this, which would have made
  `resolve_database_url()` fall back to the application's localhost default. Failed-Job retention
  is now stated explicitly in the fixture's own header: never automatically deleted, matching ADR
  0005's "kept around, not deleted" precedent, cleaned up only as part of a reviewed
  fix-forward/revert action.

**Deferred cluster evidence:** that Argo's built-in health checks for StatefulSet (wave -1) and
Job (wave 0) actually gate wave 1 as designed, that a terminally failed Job truly is not recreated
across a real resync, and that DB/Secret readiness genuinely blocks promotion — this is asserted
from Argo CD's documented health-check behavior, **not yet locally verified against a running
Argo installation**. T-GO-03 ("fresh install/failed migration/idempotent sync") is where this gets
proven live. Wiring this Job into `charts/bedoux` behind a GitOps-profile flag (mutually exclusive
with the legacy hook) is GO-3 implementation work, not done here.

**Correction applied:** the failure-status claim is narrowed per owner correction — see Gate 3/6
below and Gate 2's failure semantics restated in Gate 3.

## Gate 2 (failure semantics) — corrected

**Decision:** a failed migration blocks promotion of that environment's API/web release and
requires reviewed recovery (Gate 6a's status record + a Git-repair PR). It is **not** correct to
claim a failed hook automatically makes Application health `Degraded` and disables all future
synchronization as one bundled fact — operation status (the sync operation's own result), resource
health (each resource's individually assessed health, including the Job's), and retry/auto-sync
behavior are three separate, independently observable states in Argo. The accurate claim: the
migration Job's own health is `Degraded` once `backoffLimit` is exhausted, which blocks wave 1
from being applied (an Argo wave only advances past resources that are Healthy), and the
Application's aggregate health reflects that Degraded child resource — but auto-sync itself is not
disabled by this, and a subsequent unrelated sync operation is not automatically suppressed unless
explicitly designed to be (Gate 6a's status-record check is precisely what supplies that
suppression, deliberately, rather than assuming Argo does it for free).

**Deferred cluster evidence:** the observable failure status, any notification path, and retry
suppression must be specified and tested live — T-GO-03. This document does not claim that test has
run. Existing healthy capacity (e.g. a previously-promoted stable release still serving traffic in
a different environment) is preserved by construction (wave 1 for the *failed* release's
environment never applies), not because anything here claims an atomic rollback of already-applied
changes — no such rollback is claimed or designed.

## Gate 3 — Signature verifier, controller/router pins

**Version pins (added this round — the prior draft never actually pinned these despite it being
a stated GO-1 deliverable; researched and cited, not guessed):**
- **Argo CD: v3.5.2** (https://github.com/argoproj/argo-cd/releases). Argo CD has no branded LTS
  track; its own support policy patches only the three most recent minor lines (currently
  3.5.x/3.4.x/3.3.x) — v3.5.2 is current within that rolling window, not a permanent pin. Re-check
  at GO-3 install time in case a newer patch has shipped by then.
- **Sigstore `policy-controller`: v0.15.1** (https://github.com/sigstore/policy-controller/releases).
  No LTS designation either; re-check at install time.
- **Router (kind-local Ingress): Traefik, owner-decided.** This project's local kind profile
  previously used ingress-nginx (`docs/local-tooling.md`), which is **past its own announced
  retirement window**: per the project's own README and an official Kubernetes blog post dated
  2026-01-29 (https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/,
  https://github.com/kubernetes/ingress-nginx), "best-effort maintenance will continue until
  March 2026. Afterward, there will be no further releases, bugfixes, and no updates to resolve
  any security vulnerabilities" — already past as of this document (2026-09-09). This does
  **not** affect the AWS/EKS profile, which uses the separately-maintained AWS Load Balancer
  Controller (v3.4.3, unaffected by this finding).

  **Pin: Traefik v3.7.13** (Helm chart `traefik/traefik` v41.5.0, repo
  `https://traefik.github.io/charts`), researched and cited, not guessed. This is simultaneously
  the current stable release line and the version Argo Rollouts supports **natively, with no
  extra configuration** — Argo Rollouts added `traefik.io`-API-group support (Traefik v3's group)
  in v1.7 (PR argoproj/argo-rollouts#3348, Feb 2024); current stable Argo Rollouts is v1.9.1
  (2026-07-17), well past that minimum, so there is no version gap between "current Traefik" and
  "what Rollouts supports." **Caveat recorded, not currently applicable:** if Traefik were ever
  downgraded to v2.x, `rollouts-controller` would need explicit
  `--traefik-api-group=traefik.containo.us --traefik-api-version=traefik.containo.us/v1alpha1`
  flags, or canary weighting would silently target the wrong API group — worth a version-pin
  regression test whenever this pin is revisited, not relevant at v3.7.13.

  **Weighted-routing approach (documented now; installation is GO-3/GO-6 work, not GO-1):**
  Traefik's Kubernetes CRD provider (`providers.kubernetesCRD`, **on by default** in the Helm
  chart — no extra values needed) exposes a `TraefikService` CRD supporting weighted backend
  splits. Argo Rollouts' Traefik integration
  (`spec.strategy.canary.trafficRouting.traefik.weightedTraefikServiceName`) manages a
  `TraefikService`'s `weighted.services[].weight` fields directly, deliberately without also
  putting a static `weight` in the committed manifest — Rollouts, not Argo CD's sync, owns that
  field during an active canary, mirroring exactly the "narrow exceptions for controller-owned
  fields" principle ADR 0026 already establishes for the ALB/legacy path. This is the natural
  Traefik-native counterpart to the existing ALB weighted-`forwardConfig` approach
  (`charts/bedoux/templates/ingress.yaml`) and to Gate 4b's paired-coordination design above — the
  coordinator's promote calls are what change which step's weight is live, not a direct
  Argo-synced edit to the `TraefikService`. On kind specifically, the chart's default
  `service.spec.type: LoadBalancer` needs overriding (kind doesn't auto-provision one) — use
  `NodePort` with `kubectl port-forward`, the same class of kind-specific override
  `docs/local-tooling.md` already documents for other components.

  Candidates considered and not chosen: Envoy Gateway (CNCF, Gateway API-native — heavier
  migration, rewriting Ingress objects as Gateway/HTTPRoute, and no evaluated Argo Rollouts
  integration path was found as clearly documented as Traefik's); continuing ingress-nginx
  short-term (rejected outright — it is not "supported" by any honest definition post-retirement).

**Decision:** Sigstore `policy-controller`, subject to the version pin above and a compatibility
check against this project's existing keyless Cosign signing
(`.github/workflows/deploy-learning.yml`, identity
`https://github.com/bedoux-tech/bedoux-commerce-cloud/.github/workflows/deploy-learning.yml@refs/heads/main`,
issuer `https://token.actions.githubusercontent.com`) and against pulling from a private ECR
registry. Rationale: smallest operational footprint (one purpose-built controller, no separate
policy DSL), and it is Sigstore's own project so it tracks Cosign/Fulcio/Rekor changes fastest —
the most native fit for signatures already produced by this project's own tooling.

**Correction applied:** the earlier Kyverno-deprecation claim was wrong and is retracted. Current
documentation places legacy Kyverno policy-type deprecation at v1.19 and removal at v1.20,
estimated November 2026 — Kyverno itself is not being deprecated, and its modern
`ImageValidatingPolicy` type remains a viable alternative. `policy-controller` is still the
selection here, on its own stated rationale (footprint, native Sigstore fit), not because Kyverno
was disqualified by a deprecation that does not, in fact, apply to the project as a whole.

**Enforcement decision:** enforce from the first workload admission — no warn-mode soft launch.
Coverage: API, web, migration, canary and every init container in every GitOps-managed workload.
Required elements (design-specified here, installed and proven in GO-3/GO-4): protected-namespace
coverage (`bedoux-dev`, `bedoux-staging` only — `bedoux` stays outside Argo's/the verifier's scope
per Gate 4), rejection of any image not matching the pinned trusted identity/issuer, and an
explicit webhook failure-policy decision (fail-closed: an unavailable verifier blocks admission
rather than silently allowing it).

**Platform exception inventory (design-specified; exact digests pinned at install time, not
fabricated here). Corrected per Codex's review: every row now has a calendar expiry, not just
"reviewed on version bump" — a version that never bumps must still be re-reviewed periodically:**

| Image | Source | Why excepted | Owner | Expiry / renewal |
|---|---|---|---|---|
| `docker.io/library/postgres:16-alpine` | Third-party, `charts/bedoux/values.yaml:102-103` | Not produced by this project's CI; cannot carry our Cosign identity | Repo owner | Re-reviewed every 90 days OR at each `postgres` tag bump, whichever comes first; digest pinned when the exception is actually installed (GO-3/GO-4) |
| AWS Load Balancer Controller `v3.4.3` image | `public.ecr.aws/eks/aws-load-balancer-controller`, per `docs/architecture.md` and prior session evidence | Platform controller, not app code | Repo owner | Re-reviewed every 90 days OR at each controller version bump recorded in `docs/PROGRESS.md`, whichever comes first |
| Calico CNI `v3.32.1` manifest images | `docs/local-tooling.md:271`, kind-only | Platform networking, kind-specific | Repo owner | Re-reviewed every 90 days OR whenever `docs/local-tooling.md`'s pinned Calico version changes, whichever comes first |
| Traefik `v3.7.13` (chart `traefik/traefik` v41.5.0) | `https://traefik.github.io/charts`, kind-only | Platform ingress/router, kind-specific | Repo owner | Re-reviewed every 90 days OR at each Traefik version bump recorded in `docs/PROGRESS.md`, whichever comes first; digest pinned when actually installed (GO-3) |

No exception is namespace-wide (`bedoux-dev`/`bedoux-staging` only ever contain project-signed
images plus these named exceptions) — excluding `kube-system` wholesale was explicitly rejected
as too broad and is not part of this design.

**Deferred cluster evidence (T-GO-04):** verifier outage, wrong signer, unsigned image, and
unavailable registry/signature-credential failure tests, plus proof the enforce-mode webhook
actually fail-closes rather than fail-opens under those conditions. None of this has run; T-GO-04
("signed-only deployment rejection... forged provenance/expired credential failures") is where it
runs.

## Gate 4 — Paired API/web releases vs. Argo ownership

**Decision:** separate ownership during the transition, achieved by separate namespaces, not by a
shared-namespace field-ownership carve-out. The legacy P13 environment (Helm release `bedoux`,
namespace `bedoux`) stays completely outside Argo's management scope through GO-1–GO-5. GitOps
environments get their own namespaces (`bedoux-dev`, `bedoux-staging`) that the legacy dispatcher
never targets and Argo never shares with it. This closes the self-heal-vs-live-canary-weight
conflict identified in the Gate 4 research by construction — there is nothing to fight over because
nothing is shared.

**Legacy-dispatcher guard, added now (`scripts/p13-canary-rollout.sh`):** the script now refuses to
run against any Argo-reserved namespace (currently `bedoux-dev`, `bedoux-staging`) before doing
anything else, so a future accidental invocation against a GitOps-owned target fails loudly instead
of silently fighting Argo. See the diff below — this is a small, reversible, additive safety check;
it does not change any existing behavior against the `bedoux` namespace it already targets.

**Shared routing resources:** included in the ownership map above. The `bedoux` release's `Ingress`
and the AWS Load Balancer Controller's reconciliation of it are untouched; GitOps environments get
their own `Ingress` objects, never editing the legacy one.

**What Gate 4a resolves:** *transition ownership only* — nothing shared between the legacy
dispatcher and Argo during GO-1–GO-5, so there is nothing to fight over. **This is explicitly not
the same thing as paired-Rollout coordination**, corrected per Codex's second GO-1 review: an
earlier version of this document risked reading as if namespace separation resolved Gate 4 as a
whole. It does not. Gate 4b below is GO-1's actual design for that remaining problem — a concrete
mechanism, not a "candidate direction" deferred wholesale to GO-6.

## Gate 4b — Paired Rollout coordination design

**The problem, precisely:** once GO-6 gives `api` and `web` each their own Argo Rollout, nothing
in Argo Rollouts couples two independent Rollouts' step progression to each other by default. If
each Rollout runs its own automatic analysis and advances on its own schedule, a client can be
served a fresh canary `web` routed to a stale/reverted canary `api` (or the reverse) — exactly the
cross-version pairing ADR 0023 designed against for the legacy P13 path, where "the canary web pod
points only to `api-canary`" is the whole safety property. Two independently-analyzing Rollouts do
not preserve that property; nothing about two separate `AnalysisTemplate` schedules keeps their
step indices in lockstep.

**Decision: a single external lockstep-promotion coordinator is the only thing that ever advances
either Rollout past a step — neither Rollout is configured to analyze-and-promote itself.**

- Both `api` and `web` Rollouts use `pause: {}` (indefinite, manual) at every canary weight step
  in `strategy.canary.steps` — never `pause: {duration: Ns}`. Neither Rollout auto-advances on its
  own timer or its own analysis result.
- A single coordinator (design-specified here as `scripts/gitops-paired-rollout-promote.sh`;
  GO-6 implements and installs it — not built in GO-1, since Argo Rollouts does not exist yet) is
  the only caller of `kubectl argo rollouts promote`, using the decision function this round adds
  as a tested local model, `scripts/gitops_paired_rollout_coordinator_model.py` (GO-6 imports/calls
  it rather than re-deriving the same logic against a live Rollout).

**Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log 2026-09-09T14:37:25-06:00):
"sequential promote calls and matching step indices are not sufficient traffic evidence," and the
crash/second-call failure path did not preserve automatic stable-traffic restoration.** The
coordinator's decision function (`decide_action`, `decide_after_api_promote`) now separates four
concerns that the earlier draft's linear "promote api, then promote web" prose conflated:

1. **Divergence/health checked FIRST, before anything else.** If `api` and `web` report different
   `currentStepIndex` values, OR either reports `phase: Degraded`, the decision is `ABORT_BOTH`
   unconditionally — checked before the paired health check is even consulted. This is the crash
   case named in the review: if the coordinator crashes between promoting `api` and promoting
   `web`, the step indices diverge, and a restarted coordinator must **never** resume by blindly
   promoting `web` to "catch up" on unverified post-crash state. `ABORT_BOTH` is the only action
   available from a diverged state.
2. **Matched step indices are never, by themselves, sufficient to promote.** Only a *fresh* paired
   health/routing check — reusing the existing, already P13-proven checks
   (`scripts/p13-canary-gate.sh`, `scripts/p13-alb-pod-readiness-gate.sh`, and the ALB
   weighted-reconciliation proof in `scripts/p13-alb-reconciliation-gate.sh`, re-pointed at
   Rollout-managed Services) — authorizes `PROMOTE_API`. A failed paired check yields `HOLD`: both
   Rollouts stay paused at their current, still-matched step; nothing is aborted, nothing advances.
3. **After `promote api`, "the call succeeded and the step index advanced" is necessary but NOT
   sufficient either.** `decide_after_api_promote` requires a SEPARATE, fresh post-promote
   health/routing observation of `api`'s new step before authorizing `PROMOTE_WEB`. A failed
   post-promote check, or a promote call that reports success without the step index actually
   advancing, both yield `ABORT_BOTH` — never a retry of the same promote call, and never a
   promotion of `web` based on an unverified `api` state.
4. **Named Traefik validation adapter** (closes "ALB-specific gate scripts also need a named
   Traefik validation adapter; repointing Service names alone does not supply one"):
   `scripts/p13-traefik-reconciliation-gate.sh` (design-specified here, GO-6 implements) is the
   Traefik-native counterpart to `p13-alb-reconciliation-gate.sh` — it validates the `TraefikService`
   CRD's actual `status`/`weighted.services[].weight` state, the same way the ALB gate validates
   actual target-group weighted `forwardConfig`, rather than assuming a repointed Service name is
   itself proof of a correct traffic split.

**Coordinator ownership/fencing (new this round):** exactly one coordinator process may act at a
time, enforced by a bounded-TTL lease (`acquire_lease()` in the same model script) keyed to this
environment's paired-Rollout coordination — not the one-shot claim from Gate 6a below, since a
coordinator legitimately cycles across many promote calls for one paired rollout, not a single
attempt. A genuinely concurrent second coordinator instance is refused outright (its lease request
fails while the first instance's lease is unexpired). A **crashed** coordinator is superseded only
after its lease expires (bounded takeover, not immediate — a fresh instance re-derives current state
from the actual Rollouts' live status on start, never from its own possibly-stale local memory,
which is exactly why step 1 above checks divergence unconditionally on every cycle rather than
trusting "I already checked this").

**Both-candidate abort and drain ordering.** `ABORT_BOTH` means exactly that: both Rollouts are
aborted and traffic restored to stable on BOTH `api` and `web`, never just the one that triggered
the abort — a partial abort (only the failed side reverted) would immediately violate the pairing
property this whole gate exists to protect (a stale-canary/fresh-canary cross-pairing, just on the
other axis). Drain ordering reuses `docs/runbooks/gitops-recovery.md`'s existing "Failed canary:
traffic recovery first" sequence unchanged: stable traffic is verified actually serving on both
services, THEN (after the documented drain interval) the zero-traffic candidates may be scaled
down — never before routing is proven, and never for only one of the pair while the other still
carries candidate traffic.

**Abort/failure recovery path reuses Gate 6a's existing mechanism, not a new one.** Any
`ABORT_BOTH` is treated exactly like a Gate 2 migration failure or Gate 3 signature rejection:
recovery goes through the same reviewed Git-repair path, writing a `status/<environment>.yaml`
entry with classification `rollout-aborted` (already part of the Gate 6a schema).

**Why this satisfies "two independent Rollouts do not automatically guarantee this":** the two
Rollouts are not, in fact, independent under this design — they are both puppets of one
fencing-protected coordinator that only ever moves them together, gated on a FRESH paired-health
proof at every single promotion (not step-index bookkeeping), and that always aborts both together
on any divergence or failure. Argo CD's own reconciliation of the Rollout *specs* (image, step
definitions) is unaffected and stays GitOps-managed as normal; only step *advancement* is taken out
of each Rollout's own automatic analysis and centralized.

**Local, no-cluster evidence produced now:** `scripts/gitops_paired_rollout_coordinator_model.py`
(pure decision functions, no cluster/network access) and
`scripts/test_gitops_paired_rollout_coordinator_model.py` (15 assertions, all passing) prove: matched
steps with a failed paired check holds, never promotes on step-index equality alone; diverged step
indices (the crash repro) always abort both, regardless of the paired-check result; either side
reporting `Degraded` aborts both, checked before step-index/paired-check logic; both at the final
step is `DONE`, not an endless promote loop; a successful `api` promote call that failed its
post-promote health check aborts both rather than promoting `web` to match; a concurrent second
coordinator instance is refused an unexpired lease; a crashed coordinator's expired lease can be
taken over by a fresh instance.

**Explicitly deferred to GO-6 (not GO-1):** installing Argo Rollouts; writing
`gitops-paired-rollout-promote.sh` and `p13-traefik-reconciliation-gate.sh` for real; re-pointing
the P13 gate scripts at Rollout-managed Services; proving live that a genuinely divergent pair is
caught before serving mismatched traffic (T-GO-06). This document fixes the mechanism and its local
decision model GO-6 must implement against; it does not claim that implementation exists or has
been tested against a live Rollout.

## Gate 5 — Bootstrap credentials outside Git

**Decision:** an owner-executed bootstrap checklist, run once per fresh cluster (kind now, a
temporary EKS cluster later), added to `docs/runbooks/gitops-recovery.md`'s bootstrap section.
Credentials are delivered from protected files or the repository's existing approved secret
handling (never typed as bare command arguments, never left in shell history or logs) into
Kubernetes `Secret` objects of the type Argo's repository-credential mechanism expects
(`type: git`, well-known `argocd.argoproj.io/secret-type: repository` label), plus a connection
verification step (`argocd repo get <url>` reporting `Successful` before any Application is
created).

**Credential type:** two separate read-only deploy keys (Gate 1/Q12), one per repository. Deploy
keys chosen as the simplest repository-scoped mechanism — explicitly not claimed to be more secure
than a scoped GitHub App token, just narrower blast radius per key and no app-registration step.

**Storage, rotation, revocation (design-specified, checklist-enforced, not automated):**
- Storage: the private-key half never enters either Git repo; it is generated on the operator's
  workstation (`ssh-keygen -t ed25519 -f <path outside both repos> -C "argocd-<repo>-<purpose>"`)
  and injected directly into the cluster Secret at bootstrap time. The checklist records the key's
  **fingerprint**, never its contents, in `docs/PROGRESS.md` evidence.
- SSH host-key verification: the bootstrap checklist requires recording GitHub's published SSH
  host key fingerprint (not accepting it unverified on first connect) before the deploy key is
  used, so Argo's outbound Git connection is verified, not merely encrypted.
- Rotation: on suspected compromise (immediate), and otherwise at each fresh-cluster bootstrap
  (kind rebuild, or a new GO-7 temporary EKS session) — rotation is tied to a bootstrap event that
  already requires operator presence, rather than a separate unscheduled procedure. This cadence
  is proposed here for owner confirmation at document review, not treated as beyond question.
- Revocation: removing the deploy key from the relevant GitHub repository's settings immediately
  invalidates it; the checklist includes this as an explicit teardown/rotation step.

**Deferred cluster evidence:** actually creating and using these keys is GO-2 (repository creation)
and GO-3 (first bootstrap) work; this design contract fixes the mechanism, not the execution.

## Gate 6a — Holding a rejected release

**The earlier "unchanged Git is a no-op" answer is rejected, per owner correction, as an incomplete
mechanism** — it only addresses "don't drift within one live cluster's lifetime," and says nothing
about a fresh cluster (or a second cluster) bootstrapping from the same still-unfixed Git state and
blindly retrying a known-bad release.

**Decision:** keep auto-sync/self-heal enabled (no extra manual toggle to remember and forget), but
add a second, explicit, durable mechanism: a release-outcome record,
`status/<environment>.yaml`, committed to the env repo **only** as part of a reviewed Git-repair
PR (extending `docs/runbooks/gitops-recovery.md`'s existing "Git repair: separate reviewed change"
section) — or, for `pending`, as part of the SAME PR that promotes a new `releaseId`, so a
releaseId is never silently absent during the window between "just promoted" and "confirmed."
Design fixture: `docs/gitops-fixtures/dev-status.example.yaml`.

This distinguishes three failure classes explicitly, because they need different recovery, not one
generic "rejected" state:
- **migration-failure** — the Gate 2 Job reached `Degraded`; recovery needs a schema-compatible
  fix-forward migration, not just a new image.
- **signature-rejection** — the Gate 3 admission verifier blocked an image; recovery needs a
  correctly signed image. **Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log
  2026-09-09T14:37:25-06:00):** it is **not** generally true that nothing touched the database.
  Gate 2's sync waves apply in order (wave -1, then wave 0's migration Job, then wave 1's api/web
  Deployments) but are each independently subject to admission — a migration image can pass
  admission and actually run (mutating the database) at wave 0, and only THEN can a web/API image
  fail admission at wave 1. `signature-rejection` recovery must therefore inspect the actual wave-0
  migration Job evidence (did it run, did it succeed) before assuming the database is untouched —
  it is only genuinely untouched when the rejection happened at wave 0 or earlier, not when a wave-1
  image was rejected after a wave-0 migration already completed.
- **rollout-aborted** — a future GO-6 Argo Rollouts analysis failure; traffic already auto-reverted
  to stable, and (per the research finding this decision is built on) *the Rollout's own retained
  aborted status is the hold mechanism on that live cluster* — but that status does not survive a
  fresh cluster, which is exactly why this record exists in parallel.

**Bootstrap-precondition contract, corrected twice** (GO-3 wires this into a live bootstrap flow;
`scripts/gitops_bootstrap_precondition_check.py` is the actual, tested predicate today): before
enabling auto-sync for an environment, read its current release record's `releaseId`, look up
**only that exact `releaseId`** in `status/<environment>.yaml`.

- **First-round fix:** proceed only on an explicit outcome for that releaseId, never on a rejected
  entry's `supersededBy` field — the prior version treated `supersededBy` as a live bypass, so a
  release record still naming an OLD rejected releaseId would incorrectly proceed because some
  LATER releaseId happened to be healthy elsewhere in history. `supersededBy` is audit metadata
  only.
- **Second-round fix (the first-bootstrap contradiction):** an outcome of `healthy` proceeds, as
  before. An outcome of `pending` proceeds **only when it is the sole, first-ever entry** recorded
  for that exact releaseId — a reviewed promotion PR wrote it, and that PR review is itself the
  approval to attempt a first deployment; there is nothing further to confirm before trying. If
  more than one entry exists for that releaseId, `pending` refuses instead (a replay/re-approval
  of something already attempted, distinct exit code from `rejected`). A new `unknown` outcome
  (attempted, result never durably confirmed) always refuses and is never eligible for the
  first-attempt bypass. No entry at all still refuses — a non-empty history with this releaseId
  simply missing is a recording gap, never approval, no override. `--allow-first-bootstrap`
  exists only for a genuinely empty/absent history (before the "write pending at promotion"
  convention has ever applied at all) and is checked to confirm it never creates a loophole for
  the gap case.

Both bugs were reproduced exactly and proven fixed: `scripts/test_gitops_bootstrap_precondition.py`
(24 assertions, up from 19) includes the original `supersededBy` bypass case (release record still
says `dev-0001`, rejected, despite `dev-0002` being healthy — refused) and the first-bootstrap
contradiction (a sole pending entry now proceeds without `--allow-first-bootstrap`; a replayed
pending entry still refuses; an `unknown` entry always refuses).

**Durable first-attempt claim, new this round (closes "the checker is a read-only predicate that
cannot prove nothing has run").** Corrected per Codex's third GO-1 review (docs/PROGRESS.md session
log 2026-09-09T14:37:25-06:00): "ran the real checker twice against the same sole-pending fixture;
both return 0... demonstrates identical authorization after a crash before an outcome/repair PR is
recorded." This is correct and not a bug in the checker itself — a read-only predicate over
`status/<environment>.yaml` legitimately returns the same answer when nothing has been recorded in
between, which is exactly why "prove nothing has run" needs a SEPARATE, durable, stateful primitive,
not a smarter read-only check.

New `scripts/gitops_release_attempt_claim.py` (`claim` / `consume` subcommands) adds that primitive:
an atomic create-if-absent claim file keyed on `(environment, releaseId)` — the same atomicity
property a real Kubernetes object's name uniqueness already gives for free (GO-3's real
implementation is `kubectl create configmap claim-<environment>-<releaseId>`, which fails exactly
like this script's `open(path, "x")` fails, with `AlreadyExists`). The required sequence, documented
in `docs/runbooks/gitops-recovery.md`'s bootstrap section:

1. `gitops_release_attempt_claim.py claim` — refuses (exit 1) if a claim already exists for this
   exact `(environment, releaseId)`, whether from a genuinely concurrent second caller or a prior
   attempt that crashed before being consumed. Either way, retrying automatically is never safe.
2. `gitops_bootstrap_precondition_check.py` — unchanged read-only decision logic, now optionally
   given `--claims-dir` as a defense-in-depth second check: if an outstanding claim already exists
   for this exact releaseId, it refuses too (new exit code `6`), even if the outcome-based logic
   above would otherwise proceed. This does not replace step 1 — a caller that skips `claim`
   entirely is not protected by this flag alone unless every caller path is required to pass it.
3. Deploy.
4. Record the outcome in `status/<environment>.yaml` (as already required).
5. `gitops_release_attempt_claim.py consume` — refuses (exit 1) if called without a prior claim
   (an ordering violation, never a silent no-op).

**Crash/restart rule:** there is deliberately no `release`/`unclaim`-without-`consume` operation and
no automatic TTL/staleness expiry on a claim — a crash between `claim` and `consume` MUST leave
durable evidence behind (the claim file persists indefinitely), and resolving it requires an
operator to determine what actually happened and record an explicit outcome (most likely `unknown`,
Gate 6a's existing "attempted, result never confirmed" state, which — unchanged — always refuses and
is never eligible for the first-attempt bypass) before manually removing the stale claim. Guessing
"enough time has passed, retry is probably safe" would reopen exactly the fail-open behavior this
whole gate exists to close, so this script never does that automatically.

**Local, no-cluster evidence produced now:** `scripts/test_gitops_release_attempt_claim.py` (15
assertions, all passing) proves: a fresh claim succeeds; a second claim for the same
`(environment, releaseId)` — modeling both a genuinely concurrent caller and a crash-then-retry,
which a claim file cannot and need not distinguish — refuses; independent claims for a different
releaseId or a different environment do not collide; consuming without a prior claim is refused as
an ordering violation; a properly consumed claim can be legitimately reclaimed afterward (the layer
is not a permanent lock); double-consuming is refused, not a silent no-op.
`scripts/test_gitops_bootstrap_precondition.py`'s new assertions reproduce Codex's exact repro
sequence (check, claim, check again) and prove the second check now diverges from the first (exit 6,
not 0) — directly closing "identical authorization after a crash."

**Explicitly not proven here (T-GO-03/T-GO-05):** behavior under repeated synchronization,
relevant unrelated source changes, and controller restarts against a real Argo installation, the
real Kubernetes-object-based claim mapping (`kubectl create configmap ...`), and this predicate's
actual wiring into a live bootstrap flow (today it is a standalone, tested, correct decision
function plus a standalone, tested, durable claim primitive — neither yet called by anything that
touches a cluster). This gate stays flagged as design-only until that live proof exists.

## Gate 6b — Suspending reconciliation before teardown

**Decision:** scripted suspension, per Application: disable automation FIRST (closing the
new-operation race a second review found), then wait for/force-terminate any active or queued
operation, then re-verify from a fresh, shape-validated query — root fully suspended and verified
before any child is touched. Built now: `scripts/gitops-suspend-reconciliation.sh`.

Addressing the specific gaps named: disabling auto-sync does not by itself terminate an operation
already running, and does not stop Argo Rollouts or other Kubernetes controllers acting
independently — the script bounds this by polling BOTH `.status.operationState.phase` and
`.operation` (a queued-but-not-yet-started request, invisible if only `operationState` were
checked — a second-round finding) and force-terminating via `argocd app terminate-op` only after
an explicit timeout, never waiting unboundedly and never skipping the check. It suspends root
before any child specifically so a live root cannot re-enable a child immediately after the child
is suspended — matching `docs/runbooks/gitops-recovery.md`'s existing "editing a child alone is
insufficient if its parent can immediately re-enable it." It explicitly does **not** quiesce Argo
Rollouts (reserved, undesigned until Gate 4b/GO-6) and explicitly does **not** touch Ingress or
the AWS Load Balancer Controller — the existing runbook's Teardown steps 3–4 stay a separate,
later, sequenced concern; this script only satisfies that runbook's step 2.

**Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log
2026-09-09T14:37:25-06:00): "Application-shape check remains too permissive... mocked successful
argocd responses containing only `{"metadata":{"name":"root"}}` (and the matching child name), with
no spec/status, still yield exit 0 and both apps verified suspended."** The prior shape check only
required `.kind`/`.metadata.name` to match; a truncated response with no `.spec` at all passed it,
and every downstream field lookup then legitimately (but meaninglessly) reported "absent" —
indistinguishable from a genuinely quiesced Application. `validate_application_shape()` now requires
`.spec` to exist as an object (mandatory — a real Application always has one; its total absence
means the response is incomplete, not that the app has no spec), while `.status` stays genuinely
OPTIONAL (a real, valid, never-synced Application can legitimately lack one). When present, the
types of `.spec.syncPolicy`, `.operation`, `.status.operationState` and
`.status.operationState.phase` are also validated, so a malformed value in any of them is refused
rather than silently misread by a later `jq` filter.

**Local, no-cluster evidence produced now (corrected three times — see all three "Corrections
applied" sections above):**
- `scripts/gitops-suspend-reconciliation.sh --help` — exit 0; missing required arguments — exit 2.
- `--dry-run` — exit 0, prints the exact per-app command sequence (disable, then check, then
  verify), contacts nothing.
- `scripts/test-gitops-suspend-reconciliation.sh` (21 assertions, up from 18) runs the real
  `--execute` path against mock `argocd`/`jq` binaries on an isolated `PATH` — no real cluster.
  Proves, across 7 scenarios: total command failure exits non-zero and never claims success or
  touches a child; a stuck-active phase that never clears exits non-zero; a fully healthy path
  exits 0 with the root suspended strictly before either child, AND with the FIRST
  `--sync-policy none` call proven (by call-order log) to happen for root before its own
  quiescence check runs; the second-round counterexample — phase `Succeeded`, `argocd` calls all
  genuinely succeed with `automated: {}` still present, but `jq` fails specifically on the
  `syncPolicy.automated` filter — correctly refuses instead of reporting false success; a response
  with a mismatched `.metadata.name` is refused as untrustworthy, never silently used; a
  `.operation` field present despite a terminal `operationState.phase` is correctly treated as
  still-active and force-terminated, proving `.operation` is actually examined; and **the exact
  third-round counterexample** — a genuinely successful `argocd` response containing only
  `{"metadata":{"name":...}}`, no `.spec` at all — is now refused as an incomplete/untrustworthy
  response, never treated as a verified-suspended Application.
- A real bug was found and fixed in the process (second round): `log()` wrote to stdout, so
  diagnostic messages logged from inside any function invoked via command substitution were
  silently absorbed into the captured return value instead of appearing at all — moved to stderr.

**Deferred cluster evidence:** everything requiring a live `argocd` CLI and an installed Argo — the
actual suspend, the actual verification query, and specifically the **restart/no-recreation test**
(suspend, restart the cluster/controller, confirm nothing re-enabled) the owner named explicitly.
That is GO-3's first local teardown drill and GO-5's extended recovery testing, per the owner's own
sequencing instruction; this script's `--execute` path is unusable until then and is not claimed to
work beyond its argument-handling and dry-run logic, both of which are proven above.

## ADR status

- [ADR 0026](decisions/0026-two-repository-argocd-delivery.md) — **remains Proposed.** This
  document resolves the design gates it names GO-1 must resolve; it does not itself flip ADR 0026
  to Accepted. That is a separate, explicit owner action.
- [ADR 0027](decisions/0027-gitops-profile-migration-jobs.md) — **new, Proposed.** Supersedes ADR
  0005 in part (GitOps-managed environments only); ADR 0005 remains Accepted, unchanged, for the
  legacy path. Also a separate, explicit owner acceptance action.

## Remaining technical blockers and proposed resolutions

1. **Deploy-key rotation cadence** (tied to bootstrap events) is a proposed default, not yet
   owner-confirmed as a standing policy. *Proposed resolution:* owner confirms or adjusts at
   document review; low cost either way since it only affects a checklist, not running
   infrastructure.
2. **The bootstrap-precondition check, the attempt-claim primitive, the suspend script, and both
   renderers are all correct and locally tested, but none is wired into anything that touches a
   real cluster.** *Proposed resolution:* GO-3 integrates `gitops_bootstrap_precondition_check.py`
   and `gitops_release_attempt_claim.py` into the actual bootstrap flow (as the documented
   claim → check → deploy → record → consume sequence), maps the claim's local-file model onto a
   real `kubectl create configmap claim-<env>-<releaseId>` object, integrates
   `gitops-suspend-reconciliation.sh`'s `--execute` path into the actual teardown runbook, and
   integrates `render-gitops-applications.sh`'s mechanism into whatever actually creates the root
   Argo `Application` at bootstrap time — and proves all of it live. This document does not claim
   that integration exists.
3. **Gate 4b's paired-Rollout coordinator (`gitops-paired-rollout-promote.sh`) and its named
   Traefik validation adapter (`p13-traefik-reconciliation-gate.sh`) are a completed, locally
   tested decision MODEL (`gitops_paired_rollout_coordinator_model.py`), not built or tested
   against a real Rollout.** *Proposed resolution:* GO-6 implements both, re-points the reused P13
   gate scripts at Rollout-managed Services, wires the fencing lease to real coordinator process
   lifecycle, and proves live (T-GO-06) that a genuinely divergent pair is caught before serving
   mismatched traffic.
4. **Traefik's kind service-type override (`LoadBalancer` → `NodePort` or equivalent) is named
   but not yet written as an actual values override.** *Proposed resolution:* GO-3 writes the
   concrete `values-kind.yaml`-equivalent override when it actually installs Traefik; low risk,
   well-precedented by this repo's existing per-profile values file pattern.
5. **The release-attempt claim's crash-recovery path requires an operator to manually remove a
   stale claim file after recording an explicit outcome** — there is deliberately no automatic
   TTL/staleness expiry (see Gate 6a). *Proposed resolution:* this is intentional, not an
   oversight, but GO-3's runbook integration should make the manual-removal step an explicit,
   checkable line item so it is not silently skipped under incident pressure.

Router selection (Gate 3: Traefik) and the Application-generation mechanism (Gate 1: multi-source
`Application`) are no longer on this list — both were decided/chosen explicitly across this and the
prior round, with version pins researched and cited and the mechanism locally rendered and tested.

**Outstanding, unrelated, not fixed by this work (reported per owner instruction, not resolved):**
`make docs-check` still fails — `docs/diagrams/gitops-workflow.drawio` (untracked; a `.bkp` autosave
alongside it indicates someone is actively editing it outside this session) has no exported
`gitops-workflow.svg` sibling, which `docs-check`'s diagram-export rule requires. This predates and
is unrelated to GO-1's scripts/fixtures/contract work above; per explicit instruction this diagram
is preserved untouched, not exported, deleted, or claimed resolved here. `scripts/check-github-actions.sh`
(the `actions-check` half of `docs-check`) passes on its own.

None of the above blocks GO-1 from being reviewed as design-complete; none requires installing
anything, creating a repository, or opening an AWS/cluster session to resolve.
