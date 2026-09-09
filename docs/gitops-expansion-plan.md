# Bedoux GitOps expansion plan

Status: **Planning deliverable ready for review**, 2026-09-08. Task: GO-A.
Owner design-interview answers are recorded below. Technical implementation proposals remain
subject to review through [Proposed ADR 0026](decisions/0026-two-repository-argocd-delivery.md).
[PROGRESS.md](PROGRESS.md) is authoritative. GO-1–GO-8 are NOT STARTED; no repositories have
been created, files migrated, controllers installed, or implementation phase activated.

This plan includes the [proposed recovery procedure](runbooks/gitops-recovery.md). It preserves
the completed learning track and keeps the production-hosting proposal separate.

## Confirmed direction

- Primary purpose: GitOps learning and interview evidence, with reuse intended for the future
  bedoux.ca project. This does not decide that the future website must run on Kubernetes.
- Controller: **Argo CD**, selected by the owner on 2026-09-08. Flux remains comparison context,
  not a parallel implementation target.
- Reuse **bedoux-commerce-cloud** as the application repository, retaining its history while
  evolving its responsibilities. Add one environment repository; no third app repository or
  frozen duplicate is needed. `bedoux-commerce-env` is the working name.
- Start with local **dev** and **staging** environments, then a temporary EKS learning
  environment. These stages are learning environments, not a claim of real production.
- Local topology: one kind cluster, separate dev/staging namespaces and separate databases.
  This saves workstation resources but does not provide independent cluster failure domains.
- Enable automatic drift repair for Argo-owned configuration, initially disable automatic
  resource deletion, and explicitly protect database/PVC resources. Review exceptions for
  HPA/rollout-owned fields so legitimate controller changes are not treated as drift.
- Include **progressive delivery as a later milestone**, following basic reconciliation and
  rollback proof. Plan around Argo Rollouts alongside Argo CD; integration details and P13
  acceptance parity need design and testing before any implementation.
- CI builds/verifies immutable images and proposes an environment-repository PR. The owner
  reviews/merges it; Argo CD automatically reconciles that approved desired state while the
  authorized cluster is running. Promotion does not authorize cluster creation or longer sessions.
- Release publication starts with an **explicit Prepare release action**; ordinary PRs run tests
  and build checks. ECR publication remains limited to authorized AWS sessions.
- A failed canary automatically returns traffic to the known-good version. Git recovery is a
  **separate owner-reviewed revert or fix-forward PR**. No automatic Git revert or automatic
  retry of the rejected candidate. Document both steps and demonstrate their independence.
- Separate application development/build concerns from environment desired state across two
  repositories, inspired by the examples below and adapted to Bedoux.
- Discuss consequential choices with the owner before finalizing the implementation plan.
- Do this planning before implementing the [hosting proposal](production-hosting-plan.md).
  That proposal and Proposed ADR 0025 remain available; GitOps does not imply acceptance of
  static hosting, an always-on Kubernetes cluster, or a larger budget.
- Preserve completed P0–P14, M1–M5 and H1–H6 history/evidence. Existing AWS/local-first rules
  continue to apply. Repository creation and migration are future work.

## Reference pattern and meaning of GitOps

The course's [application repository](https://github.com/LinkedInLearning/gitops-foundations-app-2892009)
contains source/build assets and explains the separation of image production from desired state.
Its [environment repository](https://github.com/LinkedInLearning/gitops-foundations-env-2892009)
contains examples for Terraform, Argo CD, Flux, Flagger and other course tools. It uses a different
application/cloud toolchain; its setup scripts and credentials are not Bedoux bootstrap commands.

OpenGitOps defines declarative, versioned/immutable desired state that agents pull automatically
and reconcile continuously. Two repositories provide a useful boundary but are not sufficient
without that operational behavior.
[OpenGitOps principles](https://opengitops.dev/).

## Proposed responsibility split

| Responsibility | Application repository | Environment repository |
|---|---|---|
| Source | FastAPI/React, application tests, Dockerfiles, migrations | Environment-specific desired state and deployment policy |
| Build | Test, scan, produce immutable API/web artifacts, SBOMs and signatures | Validate proposed artifact references and deployment configuration |
| Release | Publish compatible API/web digests with traceable source/build evidence | Select reviewed release and chart versions for each environment |
| Reconciliation | CI proposes desired-state changes; target end state removes routine cluster deployment credentials from app CI | Controller pulls approved configuration and reports actual health/drift |
| Charts/infrastructure | Reusable `charts/bedoux` source and compatibility tests | Environment values, Argo Applications, bootstrap and eventually Terraform; operator still owns Terraform apply |
| Documentation | Authoritative `docs/PROGRESS.md`, track decisions, historical evidence and app guidance | Environment runbooks/evidence summaries with links to the authoritative app-repo checkpoint |

The owner confirmed reuse of the current repository as the app repository (both API and web).
Preserve history while moving environment ownership incrementally; retain historical operational
evidence with explicit links rather than maintaining two live copies of the same configuration.
Keep both repositories private, retaining `bedoux-tech/bedoux-commerce-cloud` and using
`bedoux-tech/bedoux-commerce-env` as the proposed new name. Keep this repository's PROGRESS as
the only cross-repository execution checkpoint; the env repo links to it instead of maintaining
a competing phase checklist. Check visibility/protection capabilities again at repo creation.

Proposed env layout: `bootstrap/` for reviewed root/application templates, `environments/dev/`,
`environments/staging/`, and `environments/eks-learning/` for release selections/values;
`policies/`, `tests/`, `scripts/`, and `docs/runbooks/` for validation and operation. Infrastructure
eventually lives under `infra/terraform/` there after an explicit ownership handover. Initially
leave current Terraform in this repo while the GitOps path is proved; never keep two active
copies managing the same remote state.

## Nomad workspace and bounded delegation

The workstation layout and delegation rules below are handoff logistics, not activation of
the release workflow or approval to create the environment repository.

The owner selected `/var/home/tsogtb/src/github.com/bedoux-tech/` on workstation `nomad` as the
continuation location. Reuse `bedoux-commerce-cloud/` there as the existing app clone. Reserve
the sibling path `bedoux-commerce-env/` for the future env clone; do not nest it inside the app,
turn it into a submodule, or use an app-repo worktree as a substitute for a separate repository.
The read-only 2026-09-09 check found the app clone clean but stale at `0c1c285` and the env
directory absent. Bring the app clone up to reviewed main before resuming; env creation/clone
remains GO-2 after explicit activation. Scripts should resolve repository roots/configuration,
not hardcode this workstation path into deployment manifests or CI.

The owner permits Claude subagents for independent, bounded work under the
[phase-orchestration workflow](workflows/phase-orchestration.md#delegate-bounded-work).
Before activation, only review/catch-up is in scope. After activation, parallel subtasks must
stay within the single active GO item, use non-overlapping edit ownership, and return evidence
for primary-agent review. The primary agent retains progress/gate state, integration and final
verification; owner approvals are never delegated. Subagents do not independently publish,
create repos, modify shared Git state, run later milestones or operate AWS/Kubernetes.
This permits delegation; it does not require subagents or change any acceptance criterion.

## Agreed release flow

1. Application changes pass PR CI; no AWS publication occurs automatically on app-main merge.
2. An explicit Prepare release action on a reviewed exact app-main commit produces verified
   immutable API/web images and release evidence, then proposes an env PR selecting them for dev.
3. Owner review and merge approve the desired state; Argo CD pulls the tracked Git configuration
   and reconciles the Kubernetes resources. The node's container runtime pulls the referenced
   images when Kubernetes starts the pods; Argo CD does not itself pull application images.
4. Dev health/evidence precedes a separate reviewed staging promotion of the same artifacts.
   Exact success criteria and automation that prepares the next PR remain to be specified.
5. EKS promotion follows local proof and a separately authorized bounded AWS session.

The separate dev/staging promotion PR in step 4 is the proposed implementation of the owner's
agreed reviewed-promotion model, not permission for autonomous merging. Repository paths and
branch protections/compensating controls still need design. Argo CD sync status and application
health must both be checked; a merged PR is not evidence of successful deployment.
[Argo CD automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).

Owner-approved local topology: one kind cluster with separate namespaces and independent
application/database instances for dev and staging. This demonstrates release separation with
lower workstation overhead but does not prove separate-cluster failure isolation. Namespace RBAC,
network boundaries, resource budgets and state retention must be specified before the drill.

## Migration requirements and design gates

1. **Deployment ownership.** `.github/workflows/deploy-learning.yml` currently builds/signs
   images, obtains EKS access, verifies signatures and invokes Helm or the P13 rollout helper.
   A migration needs a precise handover per resource. Direct Helm and GitOps must not compete
   for the same release; controller-owned subresources also need clear boundaries.
2. **Database lifecycle.** ADR 0005 uses `post-install,pre-upgrade`, requires fresh database/Secret
   availability and prohibits automatic schema downgrade. Argo CD renders Helm templates and
   owns the lifecycle; its hook mappings do not reproduce all Helm semantics. Flux manages Helm
   releases with configurable remediation. Neither option inherits Bedoux's past evidence
   without new install, failed-migration and rollback tests.
   [Argo CD Helm semantics](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/),
   [Flux HelmRelease semantics](https://fluxcd.io/flux/components/helm/helmreleases/).
3. **Canary ownership.** ADR 0023 deliberately uses one workflow/Helm release. Its helper makes
   several temporary desired-state changes that a reconciler could undo. The owner agreed to
   progressive delivery after basic GitOps proof; plan Argo Rollouts with explicit ownership of
   selectors, ReplicaSets and routing fields. Do not run the old P13 mutation helper against
   those resources. Specify coordination of API/web candidates to preserve P13's end-to-end
   stable/canary pairing; two independently progressing Rollouts do not establish that property.
   Keep real HTTP error correlation, healthy targets, applied weights and drain-before-cleanup
   as acceptance requirements. ALB integration exists, but does not itself prove those contracts.
   [Argo Rollouts ALB integration](https://argo-rollouts.readthedocs.io/en/stable/features/traffic-management/alb/).
4. **Trust across repositories.** Decide who can propose versus approve image updates, how the
   controller reads private Git, and where image signature checks are enforced after app CI
   loses deployment responsibility. Git commit signatures and image signatures prove different
   things. Repository/workflow renaming also changes existing OIDC/signature identity contracts.
   Full private ECR image URLs contain an AWS account ID, which current repository rules prohibit
   committing. The final design must resolve this explicitly through an approved policy decision
   or a reproducible bootstrap/configuration mechanism; placeholder URLs alone are not deployable.
5. **Immutable reproducibility.** Pin image digests and chart/source revisions together; avoid
   rebuilding for promotion. Retain desired and rollback artifacts so ECR lifecycle expiry cannot
   prevent rebuilding a cluster or restoring a prior release.
6. **Data/secrets.** Keep credentials out of ordinary Git. Choose a secret bootstrap/delivery
   mechanism, recovery procedure and explicit PVC/namespace deletion protection. Git revert
   restores configuration, not database contents.
7. **Bounded sessions.** A controller can recreate removed Ingresses and therefore ALBs. Teardown
   must first stop reconciliation through a defined procedure, then remove resources and verify
   the inventory. Recreating a cluster must require an explicitly opened session and bootstrap.
8. **Production relationship.** The owner wants learning/interview value and future bedoux.ca
   reuse. The proposed static S3/CloudFront catalog has no Kubernetes runtime. Carry forward
   artifact, promotion and desired-state practices, while keeping the future hosting runtime
   undecided; Argo CD selection for this track does not approve a persistent EKS cluster.

No accepted ADR is amended here. The eventual decision must identify which portions of the
existing delivery, identity and migration ADRs it supersedes for the new profile.

## Design interview outcome

| Round | Decisions needed | Why it matters |
|---|---|---|
| 1 — intent and migration | Learning/interview with future bedoux.ca reuse; retain current app repo; add env repo; Argo CD | Owner confirmed |
| 2 — delivery behavior | One kind cluster, dev/staging namespaces and separate databases; reviewed promotion followed by sync | Owner confirmed |
| 3 — reconciliation and canary | Self-healing, initial pruning disabled, data protected; progressive delivery after basic GitOps | Owner confirmed |
| 4 — release and recovery | Explicit release preparation; automatic traffic recovery and separate reviewed Git repair | Owner confirmed; technical proposal awaits review |

Confirmed: learning/interview with future production reuse, Argo CD, existing app-repo reuse,
one local cluster with separate dev/staging namespaces/databases then temporary EKS, reviewed PR
promotion with automatic reconciliation, self-healing with initial automatic pruning disabled,
and a later progressive-delivery milestone using the recommended Argo Rollouts direction.
Automated sync, self-heal and pruning are distinct settings; automatic deployment does not
approve arbitrary resource deletion.
[Argo CD sync controls](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/),
[Argo Rollouts scope](https://argoproj.github.io/argo-rollouts/).

## Release and recovery policy

The owner accepted an explicit release action and separate traffic/Git recovery. A canary
failure must restore stable traffic, retain failed/degraded status and notify the operator.
Repeated reconciliation must not retry the rejected candidate. Git continues to reference the
failed desired release until a reviewed recovery PR is merged; this is visible failure state,
not a successful deployment. No schema downgrade is part of either recovery step.
[Argo Rollouts FAQ](https://argoproj.github.io/argo-rollouts/FAQ/).

The [recovery procedure](runbooks/gitops-recovery.md) specifies abort, Git repair, restart/rebuild,
data restore and teardown separately. It requires a healthy Git release before fresh bootstrap:
a new cluster has no memory of the previous controller's aborted status. No implicit last-known-
good override may hide a mismatch between Git and the running release.

## Proposed technical contracts

- Keep both repositories private, consistent with the current hosting policy. Preserve the
  current account budget and explicit Terraform saved-plan approvals; Argo CD does not provision
  or destroy EKS. Environment-repo Terraform placement does not imply continuous Terraform apply.
- Keep reusable chart source with application code, pin compatible chart source revisions, and
  place environment values plus Argo Applications in the env repo. Plan an explicit owner handover
  for Terraform, shared docs and scripts; no duplicate mutable infrastructure state.
- Use a narrowly scoped GitHub App for cross-repo PR automation; separate it from Argo's read-only
  repository credential. Store private key material outside Git, scope installation access to
  the required repositories, and document owner setup/rotation/recovery. GitHub documents App
  tokens for access beyond the workflow's own repo.
  [GitHub App workflow authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow).
- Bootstrap local secret fixtures outside Git; retain the existing AWS application secret-retrieval
  contract unless a reviewed replacement is needed. Document credential recovery separately from
  Git recovery. Do not add a new secrets controller merely because the deployment uses GitOps.
- Treat signing enforcement, ECR identifier handling, private registry pulls, schema sequencing,
  paired API/web rollout and teardown suspension as design/test requirements to resolve before
  live use, not waived details. Verify support of all pinned controllers and local traffic routing.

### Controller selection and ownership

Argo CD is the owner's choice and makes desired/live differences visible for demonstrations.
Flux remains a credible Helm-lifecycle alternative but is not in the implementation scope.
Argo CD uses Helm for rendering, so retaining chart source does not retain Helm `--atomic`
behavior. Argo Rollouts will own progressive deployment resources, while the AWS Load Balancer
Controller owns AWS routing infrastructure. Re-prove migration and rollout semantics rather than
claiming the completed Helm evidence transfers unchanged.

Proposed bootstrap: a small, operator-installed root Argo Application renders a fixed allowlist
of child Applications from the env repository. Children use the app chart at the exact source
revision selected in that environment's release record and env-specific values. Automated
generation of unrelated Applications/clusters is out of scope. Root templates are privileged
operator configuration, not files the release bot may modify.
[Argo bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/),
[multiple-source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/).

For a release change, pin both the app/chart commit and the reviewed env values revision in the
generated child Application. Do not combine a reviewed chart with independently moving values.
GO-1 must prove how the root selects and passes the same release revision; if the bootstrap
renderer cannot guarantee this, revise it before implementing promotion automation.

Registry prefix, cluster identity and workload-role identifiers are operator-supplied session
bindings, kept outside Git under the current no-account-ID rule. The root receives these bindings
as bootstrap parameters and passes them to child rendering; env Git stores image repository
names and digests only. Bootstrap validates destination/repository allowlists and rejects missing
or conflicting values. Record a sanitized binding fingerprint, never raw identifiers. Root
Application installation and secret restoration are explicit bootstrap exceptions: recovery is
from Git **plus these documented bindings/secrets**, not from Git alone. Do not let a parent
reconciler overwrite the operator's root bindings or resume it during teardown.

Restrict Argo AppProjects to the intended source repos, namespaces and resource kinds. Separate
root/platform permissions from workload permissions; the release bot only proposes release-file
edits. Existing private-repo CI gates are process controls unless GitHub enforcement is actually
verified. No bot merge permission or claim of enforceable branch protection is added here.

### Images, signatures and local-first releases

Define one release record containing app commit, chart commit, API/web digests, expected signing
identity, migration compatibility metadata and build evidence. Pin chart source by Git SHA first;
OCI chart distribution is optional future work. A promotion reuses artifacts; it never rebuilds.

Provide two explicit preparation adapters: local operator preparation to an ephemeral kind-reachable
registry, and the AWS GitHub workflow to ECR during an active session. Local signing uses a
documented test identity and is not claimed as proof of GitHub OIDC/ECR integration. The local
adapter must check the reviewed app commit and produce the same release-record schema. GitHub-hosted
runners are not assumed to reach the workstation's private registry. No new GHCR/Docker Hub
subscription or public image publication is implied.

Env CI verifies release provenance and allowed file changes. The cluster deployment boundary must
also reject unsigned/wrong-identity images, including migration and canary images; checking only
the release PR leaves a bypass. GO-1 selects a minimal supported admission verifier and GO-4 proves
its failure behavior, exceptions for operator-pinned platform images, registry authentication and
recovery. No broad registry trust, always-allow outage fallback or custom security plugin is assumed.

Before a session, confirm all desired/stable/rollback digests and signatures exist. Do not change
the existing ECR lifecycle silently: a pinned release whose artifacts expired blocks bootstrap;
retention changes need their own reviewed scope. Local registry disappearance similarly requires
explicit reconstruction and validation, never silently substituting new image digests.

### Migrations, secrets and deletion

Render the GitOps workload with legacy Helm migration hooks disabled. Proposed ordering within
each environment: credentials/database prerequisites, a release-specific forward migration Job,
then API/web workloads. Use Argo sync ordering with health checks that actually wait for database
readiness and Job success; a child Application being created is not proof that its DB is ready.
Migration failure stops workload promotion. Avoid `.Release.Revision` as the migration identity
under Argo; derive it from reviewed release metadata. Retries must be bounded and migrations
idempotent/backward-compatible. Seed only a fresh synthetic database under explicit bootstrap
authorization. A downgrade never runs on abort or Git revert.

Before Rollouts is introduced, ordinary Argo sync is not an atomic Helm rollback. Configure and
test rolling-update/readiness behavior to retain healthy capacity on failure; restore the full
release through the reviewed Git recovery path. Do not label a failed sync as automatically
rolled back merely because old pods remain available.

Bootstrap local database and Git credentials out of band; reference existing Secrets from the
GitOps profile instead of rendering development passwords. Preserve ADR 0012's direct Secrets
Manager retrieval when that AWS profile is explicitly enabled. Separate Argo Git-read, CI
cross-repo-write, node image-pull and application AWS identities, with rotation/recovery tests.

Initially set auto-sync/self-heal on, prune/allow-empty off. Protect namespaces/PVCs against both
pruning and Application deletion; these are different deletion paths. Manual prune remains a
reviewed operator action. Never broadly ignore spec differences to accommodate Rollouts: enumerate
the routing/selector/HPA fields another controller owns and test that normal drift is still fixed.
[Argo sync options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/).

### Progressive delivery contract

Introduce Argo Rollouts only after ordinary deployment, migration failure and Git rollback pass.
The first rollout design gate must specify how one release coordinates API/web candidates and
their Service routing. Do not silently weaken P13's paired stable/canary request paths to two
independent services. If the selected topology cannot preserve this property, stop for an explicit
design revision before a live drill.

Use bounded analysis with actual application-error attribution, healthy backend targets, observed
weighted traffic, weight reconciliation before drain, and safe cleanup. Classify failed health
tests, infrastructure failures and inconclusive analysis separately; only a deliberately observed
regression earns regression-drill evidence. Notifications and retry suppression must be tested.
Keep ALB weight/target verification even if the chosen controller has similar features. A local
replica ratio alone cannot be claimed as measured 90/10 HTTP traffic; validate a currently supported
local traffic router and its resources before pinning it.

## Migration and acceptance milestones — NOT STARTED

Each item requires separate activation through PROGRESS. Estimates are focused work, excluding
owner review, credential setup, CI queues and cloud delays; a working day means roughly 6 hours.

| Task | Deliverable and boundary | Required evidence | Estimate |
|---|---|---|---|
| GO-1 — design contract | Review ADR 0026; finalize source/binding rendering, migration order, signature verifier and paired-rollout design; pin supported controller/router versions; no installation | T-GO-01: ownership/trust map, rendered fixture validation, explicit ADR supersession and recovery contracts; unresolved design choices block dependent tasks | 1–2 days |
| GO-2 — repository boundary | Create private env repo after authorization; scaffold env CI, narrow bot/read credentials, chart/values contracts and cross-links; no workload handover | T-GO-02: both repos' checks pass; wrong-file bot proposal rejected; credentials absent; all history preserved; exact source revisions traceable | 1 day |
| GO-3 — local reconciliation | Alarmed kind bootstrap with dev/staging, migration adaptation and protected data; existing Helm release remains separate | T-GO-03: fresh install/failed migration/idempotent sync; controlled drift repaired; data/Application deletion protections; namespace separation; documented cleanup | 1–2 days |
| GO-4 — release and promotion | Explicit local preparation, signed release record, environment PR, owner merge and automatic sync; app CI loses direct deployment responsibility for GitOps targets | T-GO-04: same digests promoted dev→staging, signed-only deployment rejection, app health, forged provenance/expired credential failures, no cluster mutation from app CI | 1–2 days |
| GO-5 — recovery | Revert/fix-forward procedure, secret/data restore and fresh-cluster reconstruction; protected manual deletion path | T-GO-05: timed Git recovery, schema unchanged by revert, restored test records, missing artifacts/bindings fail closed, no hidden desired-state override | 1 day |
| GO-6 — progressive delivery | Argo Rollouts migration with explicit API/web coordination and analysis; no legacy P13 helper on controller-owned targets | T-GO-06: successful canary plus attributed regression; stable traffic restored, Git initially unchanged, degraded state visible, no retry after repeated sync/controller restart; reviewed recovery PR; safe drain/cleanup | 2–3 days |
| GO-7 — bounded AWS evidence | Fresh plan/session approvals; ECR/OIDC and EKS bootstrap; apply only after hash approval; verify controller capacity within the one-node default or stop/replan | T-GO-07: immutable promotion, private-registry/signature gates, real ALB traffic and regression proof, recovery and full same-session teardown; incomplete proof is not completion | One session up to 4 hours per attempt; no deadline extension implied |
| GO-8 — handover and closeout | Retire active push-deploy ownership, transfer Terraform code ownership without changing state addresses/backend, update docs and interview demo | T-GO-08: one owner per resource/state, old dispatcher refuses GitOps targets, no-op infrastructure handover plan under separate session authority, both repos green, clean inventory, owner gate review | 1 day plus bounded read-only handover review |

These T-GO IDs belong to this plan and must be added to the relevant test-plan index during GO-1;
they do not rename completed T-001–T-1404. Every task records sanitized evidence in this repo's
PROGRESS. A later task is not started merely because the preceding one passes.

Before moving Terraform code, prove the same backend, resource addresses, lockfile and provider
configuration in the new repo. Source-directory movement alone is not permission for state
imports/removals. Keep the old location inactive once the handover succeeds. Preserve the existing
deployment path as a documented fallback until GitOps acceptance, but never enable both writers
for the same namespace/resource. A cutback requires controller suspension, explicit ownership
transfer and a reviewed compatible release; running Helm over Argo-owned objects is not rollback.

Because automatic pruning is disabled, handover must inventory and explicitly remove each
superseded workload/controller object after routing ownership is verified. Deleting a manifest
does not retire its live Deployment. Preserve Service identity where required by ALB routing,
and verify no orphaned old pods continue serving or consuming resources after cutover.

## Budget and session boundaries

Local milestones incur no AWS usage; they consume workstation resources and may use existing
GitHub CI allowances. Measure combined controllers plus both environments before selecting kind
node memory/CPU; never modify host inotify or retain local data without the drill procedure.

Keep USD 20/month, the USD 16 forecast stop, `ca-central-1`, one Spot-node default, standard
learning tags, no NAT and same-day teardown. Argo CD adds CPU/memory, not permission for an extra
node. EKS evidence is optional to *attempt* until authorized, but required to claim T-GO-07 and
the full track complete. Refresh all regional rates, inventory and account forecast at preflight;
historical P13 session costs are not a new quote.

Use the existing [AWS session runbook](runbooks/aws-session.md), with the GitOps suspension
addendum proved locally before live use. A four-hour slot must reserve at least the existing
75-minute teardown margin (or more if the canonical runbook requires it). Stop new rollout/retry
work at that cutoff; teardown never waits for optional evidence. Publish a per-attempt estimate
and fresh exact plan before applying; this planning document opens no session.

## Plan review and next action

GO-A's deliverables are this plan, Proposed ADR 0026, proposed recovery procedure, consistent
checkpoint/index links, and passing local docs/link/whitespace checks. No controller, migration,
runtime, GitHub enforcement or AWS evidence is claimed from documentation review.

Next: review the concrete proposal and activate **GO-1 only** if accepted. GO-1 resolves the
specified technical design gates before repository creation or installation. Publication, merging,
ADR acceptance and implementation activation remain distinct from the owner's interview answers.
