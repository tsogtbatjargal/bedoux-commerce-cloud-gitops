# Cross-computer handoff

Copy the fenced prompt below into the next agent's session. PR #87 merged the planning package
into `main` as `e40912d`; PR #86's toolchain work is included. Both old local branch refs and
the remote planning branch are removed. PR #88 merged the closeout as `6b97979`.
The receiving workstation is `nomad`. PR #89 merged its handoff as `90a7f26`, and the receiving
clone was fast-forwarded cleanly to that exact commit. Receive this subsequent closeout too;
see PROGRESS for evidence. No manual file transfer or new app repository is needed.
This handoff does not activate GitOps/hosting implementation or accept either Proposed ADR.
`docs/PROGRESS.md` remains the only authoritative execution state.

```text
Resume bedoux-commerce-cloud on this computer. First reconcile the transferred planning
package and summarize the next decision for me; do not begin implementation automatically.

LATEST OWNER DIRECTION — 2026-09-09, SUPERSEDES THE HISTORICAL PLANNING CHECKPOINT BELOW
- GO-1 was activated and reviewed; its full contract remains unfinished. The owner now wants
  a working local MVP before the advanced improvements. Read the newest PROGRESS entries.
- Read docs/DEFERRED-WORK.md and maintain it whenever unfinished work is deferred. Reference
  DEF IDs in PROGRESS; revisit them with the owner after the MVP, not as automatic MVP blockers.
- Do not use known-broken deferred automation in the demo or claim it is complete. The exact
  implementation slice still follows the explicit owner-gate workflow; no AWS or remote
  repository creation is implied. Preserve the existing dirty worktree.

REPOSITORY AND TRANSFER CHECK
- Receiving workstation: nomad (SSH alias from the original workstation).
  Owner-selected projects directory: /var/home/tsogtb/src/github.com/bedoux-tech/.
  Existing app clone: /var/home/tsogtb/src/github.com/bedoux-tech/bedoux-commerce-cloud.
  Planned env clone: /var/home/tsogtb/src/github.com/bedoux-tech/bedoux-commerce-env.
  These are sibling repositories, not nested repos, submodules or linked Git worktrees.
  Keep the app clone in place; do not move/copy it into a new app repository.
- Read-only SSH verification on 2026-09-09 found the app clone clean on main at
  0c1c2855ad2d3f6dbb6d2f3dc6270ec927f4e629 and the env directory absent. Its origin/main was
  equally stale; a clean tracking status did not mean it had fetched GitHub's current main.
  That initial inspection was read-only. After PR #89 merged, the separately authorized
  guarded fast-forward brought Nomad to 90a7f26879fa45ba88b55ed1828a85c746781b50, clean;
  its HANDOFF hash matched the source checkout. Fetch any subsequent reviewed closeout too.
  Creating/cloning the env repo belongs to separately activated GO-2, not this handoff.
- PR #87 merged the planning package as e40912d864d14f79e58076d2a4f3e05833005807 after all four
  CI jobs passed on exact head 555647a47f99eae6494aa480db8b9cdea3b3a042 (run 34309225980).
  The owner authorized consolidation/cleanup, NOT design acceptance or implementation.
- Fetch origin and use main, including the subsequent closeout checkpoint. The old
  docs/production-hosting-assessment and chore/declare-local-toolchain refs are removed;
  their commits remain in main. Do not try to fetch a deleted feature branch to recover the plan.
  On a clean existing clone: git fetch origin --prune, git switch main, git pull --ff-only.
  Run these from /var/home/tsogtb/src/github.com/bedoux-tech/bedoux-commerce-cloud on nomad.
  Baseline to include: 6b979797e762204c84e21e8bd2e9b477c9615be2 (PR #88), plus any later
  reviewed updates including PR #89 and its synchronization closeout.
  Preserve local work first; if fast-forward fails, compare histories rather than resetting.
  If the files below are absent, inspect fetched main/history and report the discrepancy rather
  than reconstructing the package or claiming to be caught up.
- Confirm these 12 planning/checkpoint files are present on the retrieved branch:
    README.md
    START-HERE.md
    docs/HANDOFF.md
    docs/IMPLEMENTATION-PLAN.md
    docs/PROGRESS.md
    docs/architecture.md
    docs/decisions/README.md
    docs/decisions/0025-catalog-first-production-hosting.md
    docs/decisions/0026-two-repository-argocd-delivery.md
    docs/gitops-expansion-plan.md
    docs/production-hosting-plan.md
    docs/runbooks/gitops-recovery.md
- If files are missing or stale, ask me for the package before claiming to be caught up.
  Do not reconstruct detailed plans or evidence from this summary. Compare local changes
  and ancestry before integrating; never overwrite a newer clone or reset it to the old base.
- Toolchain commit 4e1790c is already merged through PR #86 as
  614912d2202b236801b733f4ff5f3c9a34c527ba; its remote feature branch was already deleted.
  Preserve the merged mise.toml, mise.lock and updated docs/local-tooling.md. Read these before
  setting up a new host; installation is not automatically authorized by a catch-up request.

READ FIRST
1. AGENTS.md and START-HERE.md, then docs/PROGRESS.md (authoritative state and session log).
2. docs/gitops-expansion-plan.md and Proposed ADR 0026.
3. docs/runbooks/gitops-recovery.md (proposed, not a runtime-tested procedure).
4. docs/production-hosting-plan.md and Proposed ADR 0025 for the deferred hosting assessment.
5. Applicable repository skills/workflows and docs/local-tooling.md before task/tool execution.
Run git status --short, git branch --show-current, and git log --oneline -5. Reconcile
disagreements with the checkpoint; a clean clone does not prove it has the planning changes.

CURRENT STATE
- P0-P14, maintenance M1-M5, and housekeeping H1-H6 are complete. No P15 exists.
- PH-A hosting assessment and GO-A GitOps planning deliverables are merged as proposals,
  awaiting design review. Planning completion/merge is not architecture acceptance or implementation.
- ADRs 0025 and 0026 remain Proposed. GO-1 through GO-8 and PH-1 through PH-5 are NOT STARTED.
- No implementation phase, AWS session, repository creation, or migration is active.
- The owner prioritized GitOps planning before hosting implementation. Domain: bedoux.ca,
  not bedoux.com; Shopify is no longer the intended hosting platform.
- Hosting's catalog-first S3/CloudFront option is a recommendation, not an accepted launch scope.
  Its dated estimates are not current billing evidence. Production Kubernetes is NOT decided.

OWNER-CONFIRMED GITOPS CHOICES — DO NOT REPEAT THE DESIGN INTERVIEW
- Purpose: GitOps learning/interview evidence plus future reuse for bedoux.ca.
- Reuse this repository for both API and web, preserving history. Add ONE environment repo;
  bedoux-commerce-env is the working name. No third app repository or frozen duplicate.
- Use Argo CD. Start with one local kind cluster, separate dev/staging namespaces AND databases,
  then temporary EKS. These are learning environments, not production.
- Ordinary PR CI tests changes. An explicit Prepare release action produces verified immutable
  artifacts and proposes an env PR; no automatic ECR publication on every app-main merge.
- Owner reviews/merges env PRs; Argo reconciles Git state in an authorized running cluster.
  The container runtime pulls images, not Argo CD itself. Merge does not open/extend a session.
- Self-heal Argo-owned configuration, initially disable automatic pruning/deletion, protect
  database/PVC resources, and respect fields owned by other controllers.
- Progressive delivery comes AFTER basic GitOps and recovery proof. Argo Rollouts is the
  proposed integration, not yet installed or fully designed.
- Failed canary: automatically return traffic to stable. Separately repair Git through a reviewed
  revert/fix-forward PR. NO automatic Git revert or rejected-candidate retry. Traffic recovery
  does not restore the database. Document and prove these as separate steps.
- Detailed technical proposals beyond these choices still need review and ADR acceptance.

CLAUDE SUBAGENTS — OWNER PERMITTED, BOUNDED BY THE ACTIVE TASK
- The owner explicitly permits the receiving Claude agent to use subagents. Follow
  docs/workflows/phase-orchestration.md, especially "Delegate bounded work".
- Before activation, delegate only read-only review/catch-up. After an item is activated,
  delegate independent parts of that item, not future GO milestones. Examples for an activated
  GO-1: source-revision binding analysis, migration ordering review, and rollout parity review.
- Give each subagent narrow scope, relevant instructions/files and a concrete output. Assign
  non-overlapping edits only when implementation is authorized; never run concurrent Git
  checkout/commit operations in a shared worktree. Review each result before integrating.
- The primary agent alone owns PROGRESS, task selection, combined evidence and completion
  claims. Owner approvals cannot be delegated. No subagent independently accepts an ADR,
  creates repositories, publishes/merges, installs controllers or opens a cloud/drill session.
- For independent validation, request raw findings rather than supplying the desired verdict.

NEXT ELIGIBLE TASK — GO-1 DESIGN CONTRACT, ONLY AFTER EXPLICIT ACTIVATION
First review the existing package and report concrete blockers or readiness. Catch-up alone
does not authorize creating the env repository or installing anything.
GO-1 must resolve these documented gates before dependent implementation:
- Bind child Application chart/app revision and env values to the same reviewed release;
  root/child templates must not silently mix revisions.
- Argo renders Helm; it does not preserve helm --atomic behavior. Design DB/Secret prerequisites,
  ordered release-specific migration jobs and readiness; no automatic schema downgrade.
- Select/pin supported controllers and a deployment-time image-signature verifier. CI-only
  signature checks are insufficient; define scoped platform exceptions and fail-closed tests.
- Preserve paired API/web releases and P13 ALB reconciliation, healthy targets, drain and
  attributed-error evidence; two independent Rollouts do not automatically guarantee this.
- Define bootstrap and outside-Git secret/session bindings without committing account IDs in
  ECR URLs. Recovery requires Git PLUS bindings/secrets, not Git alone.
- Protect rejected releases across sync/restart and fresh-cluster recovery. Suspend root AND
  child reconciliation before teardown; pruning disabled does not remove obsolete resources.
Later sequence: GO-2 env scaffold, GO-3 local reconciliation, GO-4 immutable release/promotion,
GO-5 recovery, GO-6 progressive delivery, GO-7 bounded EKS proof, GO-8 ownership handover and
closeout. Each has evidence and activation gates in the plan.
Never let old push-deploy helpers and Argo simultaneously own the same resources. Keep
Terraform ownership/state in place until the separately authorized handover.

VERIFICATION AND PUBLICATION
- Prior planning checks: docs-check passed (18 immutable Action references), 89 local Markdown
  links resolved, proposed evidence IDs/ADR status checked, whitespace and added-text identifier/
  key scans passed. These are LOCAL documentation checks, not CI or live GitOps proof.
- Re-run relevant local checks here. On the original workstation docs-check was:
    toolbox run -c bedoux-aws /usr/bin/make docs-check
  Inspect tooling first; do not assume toolbox, host make, paths, credentials, kubeconfig
  contexts or inotify settings transferred. Report missing prerequisites; do not auto-install
  software or start a cluster just to complete handoff verification.
- The initial Nomad SSH check found toolbox, mise and a Claude command shim; no host make
  resolved, the stale clone lacked mise.toml, and its default .git/hooks/pre-push was not
  executable. Tool versions, toolbox contents, effective custom hooksPath and credentials were
  not verified. After updating Git, follow docs/local-tooling.md's Nomad checklist; do not
  assume the original workstation's installations, guardrails or runtime state carry over.
- Run git diff --check; also check new/untracked documents, which that command omits.
- Update docs/PROGRESS.md before ending a work session. Preserve historical evidence and
  accepted ADRs. Do not silently accept Proposed ADRs or activate later tasks.
- The owner authorized checking and merging the existing planning branch, updating this handoff,
  and cleaning proven-merged branches afterward. This is repository consolidation only, not a
  combined implementation authorization. Later work needs its own scoped approval and focused
  PRs. Never push main directly. Check recorded exact-head CI and actual merge evidence;
  neither a published branch nor a Proposed ADR proves runtime readiness.

SAFETY AND HONEST EVIDENCE
- No AWS account API or Kubernetes endpoint was contacted in this planning work.
- Last recorded clean AWS inventory is historical, NOT a current check. Only the persistent
  allowlist remained. Original-machine local cleanup is not evidence about this computer.
- No old alarm, plan hash, apply, merge or dispatch authorization carries into this session.
- Future cloud/drill work follows docs/runbooks/aws-session.md and the applicable guardrail
  skill: independent owner alarm, cutoff, exact-plan approvals and verified teardown.
- USD 20/month cap, USD 16 forecast stop; ca-central-1; bedoux-admin, never root; standard tags
  project=bedoux-commerce-cloud and environment=learning; no NAT without a reviewed exception;
  local proof before AWS, same-day teardown under the persistent allowlist.
- Never record secrets, private keys, tokens, AWS account IDs, personal emails or raw identities.
  Do not transfer credentials, Terraform state/plans, kubeconfigs or temporary artifacts as
  part of this documentation package. Credentials/bootstrap require separate secure setup.

Your first response should state whether the transferred files are present, summarize the agreed
direction and outstanding GO-1 gates, and identify the next owner decision. Stay planning-only.
```
