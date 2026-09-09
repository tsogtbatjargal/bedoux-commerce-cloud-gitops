# Cross-computer handoff

Copy the fenced prompt below into the next agent's session. The owner has authorized committing
and pushing this complete planning package to `docs/production-hosting-assessment`.
Check the publication evidence in PROGRESS and retrieve that branch, not just `main`.
This handoff does not authorize PR creation, merge, repository creation, or implementation.
`docs/PROGRESS.md` remains the only authoritative execution state.

```text
Resume bedoux-commerce-cloud on this computer. First reconcile the transferred planning
package and summarize the next decision for me; do not begin implementation automatically.

REPOSITORY AND TRANSFER CHECK
- Repository: bedoux-tech/bedoux-commerce-cloud. Locate its clone on THIS computer.
  Previous path: /var/home/tsogtb/git-projects/bedoux/bedoux-commerce-cloud.
  Do not assume that path or its toolchain exists here.
- Source branch: docs/production-hosting-assessment, based on
  0c1c2855ad2d3f6dbb6d2f3dc6270ec927f4e629 (PR #85 merge).
- The owner authorized committing/pushing all planning files on 2026-09-08 for this handoff.
  Check the newest PROGRESS entry and remote branch before claiming publication succeeded.
  From a clean clone, fetch origin, then switch to a local branch tracking
  origin/docs/production-hosting-assessment. If that branch already exists locally, compare
  histories and preserve changes rather than resetting it. Main alone lacks this package.
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
- The source checkout preserved a separate chore/declare-local-toolchain branch at 4e1790c.
  It was intentionally not bundled here; do not delete it or assume it merged. Preserve any
  newer tooling changes on the receiving computer.

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
- PH-A hosting assessment and GO-A GitOps planning deliverables are complete LOCALLY,
  awaiting review. Planning completion is not architecture acceptance or implementation.
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
- Run git diff --check; also check new/untracked documents, which that command omits.
- Update docs/PROGRESS.md before ending a work session. Preserve historical evidence and
  accepted ADRs. Do not silently accept Proposed ADRs or activate later tasks.
- The owner authorized publishing the complete documentation package together for transfer.
  This is not permission to open a combined implementation PR. For later review PRs, separate
  hosting/GitOps scopes and reconcile shared checkpoints. Never push main directly.
  Further publication, PR creation, exact-head review, CI, ready/merge and live dispatch remain
  separately scoped actions; no PR or green CI is implied by the handoff branch push.

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
