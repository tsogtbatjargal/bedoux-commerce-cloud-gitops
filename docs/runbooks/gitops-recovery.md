# GitOps recovery and teardown — proposed procedure

Status: **Planning only**, 2026-09-08. No commands here authorize or execute a drill.
Companion to the [GitOps plan](../gitops-expansion-plan.md) and
[Proposed ADR 0026](../decisions/0026-two-repository-argocd-delivery.md).
GO-3–GO-7 must turn these requirements into version-pinned, locally tested commands with explicit
contexts, timeouts, help and dry-run support before live use. The
[AWS session runbook](aws-session.md) remains mandatory for AWS operations.

## Three different recovery actions

| Action | Trigger/owner | Result | Does not do |
|---|---|---|---|
| Traffic abort | Failed canary analysis; Rollouts acts automatically | Known-good stable traffic restored; failed candidate held and failure visible | Edit Git, restore a DB, or permit an automatic retry |
| Desired-state repair | Owner-reviewed env PR | Revert to a compatible known-good release or deploy a reviewed fix-forward release | Automatically reverse schema/data changes |
| Data recovery | Separately authorized operator procedure | Restore selected backup into the intended database after validation | Substitute for a Git/code rollback |

Returning traffic to stable while Git still selects a failed candidate is an aborted/degraded
deployment, not a green rollout. Argo Rollouts does not write a Git revert itself.
[Argo Rollouts FAQ](https://argoproj.github.io/argo-rollouts/FAQ/).

## Failed canary: traffic recovery first

1. Record the environment, exact Git/app/chart revisions, API/web digests, Rollout/analysis status
   and failure classification. Keep credentials and account identifiers out of evidence.
2. The configured analysis aborts the candidate. Verify stable target health and actual routing;
   declaring 100/0 in a manifest is insufficient. The stable web/API pair must serve requests
   successfully, not cross into candidate dependencies.
3. Only after the routing state is observed and the drain interval expires may the zero-traffic
   candidate be scaled down/cleaned up under the reviewed rollout contract. If routing cannot be
   proven, retain diagnostic resources and escalate within the session deadline.
4. Surface the failure to the operator and leave the rollout failed/degraded. Do not automatically
   retry or promote. Prove repeated sync and controller restarts do not restart the rejected
   candidate; root reconciliation must not reset an intentional failure hold.
5. Verify the env Git revision is unchanged by the abort. Record both stable availability and
   incomplete desired-state convergence. Do not claim rollback completion from either one alone.

## Git repair: separate reviewed change

1. Inspect failure evidence and migration compatibility. Select a revert to the last healthy
   release or a fix-forward release. Capture the complete chart/API/web/config tuple, not just
   one tag. Confirm all referenced artifacts and expected signatures still exist.
2. Prepare an env PR that changes only the intended release/configuration. No automated Git
   revert or automatic merge. CI verifies source/digest provenance and migration compatibility.
3. After owner review/merge, Argo CD reconciles the approved revision. Its reconciliation must
   respect Rollouts-owned fields and the documented recovery transition.
4. Verify actual app health, stable API/web pairing and the new desired/live state. Verify no
   schema downgrade and no unexpected database change. Record the healthy revision and evidence
   as the next recoverable baseline. If recovery fails, repeat triage without an unbounded retry.

## Bootstrap after failure or cluster loss

1. Inspect the last session checkpoint and env Git release before installing/enabling controllers.
   A newly created cluster does not retain the old Rollout's aborted status.
2. If the previous release was rejected and Git still selects it, refuse automatic bootstrap.
   First merge a reviewed recovery PR or obtain an explicit plan for a new fix-forward baseline.
   Missing outcome evidence is a review condition, not permission to assume a successful release.
3. Restore approved session bindings, repository credentials and database secrets outside Git.
   Verify artifact availability and identity. Never rebuild a missing image and silently reuse
   its previous digest/reference.
4. Restore data only if required and separately authorized. With synthetic disposable data,
   seed only under explicit fresh-environment approval; do not seed over a restored database.
5. Bootstrap the reviewed revision, run migration and health gates, and record the distinction
   between a first-install test and recovery of existing data. No hidden root parameter may pin
   an older app release while the env repo continues to declare another one.

## Teardown: stop recreation before removal

1. Stop new release preparation/promotion at the cutoff. Capture the current desired/live state
   and any aborted candidate; preserve sanitized diagnostic and data-recovery evidence.
2. Disable the bootstrap/root reconciler's ability to restore child auto-sync, then suspend
   workload reconciliation. Verify suspension in actual controller state. Editing a child alone
   is insufficient if its parent can immediately re-enable it.
3. Quiesce progressive-delivery activity after a bounded stable-traffic recovery where possible.
   At the hard cutoff, proceed with authorized teardown even if the optional recovery proof is
   incomplete. Do not let active Rollouts compete with resource removal.
4. Remove Ingress first; keep AWS Load Balancer Controller running until its finalizers finish
   and every session ALB/target group is gone. Wait with bounded checks; never force-remove
   finalizers merely to make the inventory appear empty.
5. Remove workloads and controller Applications using the tested deletion policy. Initial
   prune-disabled/data-protected configuration means deletion requires explicit operator action;
   removing a YAML file from Git is not cleanup. Delete only the session's explicitly authorized
   synthetic databases, PVCs/namespaces and controllers, following the data-retention decision.
6. Run canonical persistent-state reconciliation, generate a temporary-only destroy plan and
   obtain exact-hash approval before applying it. Use the canonical resumable Terraform transport.
   Remove the captured temporary OIDC provider and complete the full inventory sweep.
7. Closeout records remaining resources against the existing persistent allowlist, actual failure
   outcome, recovery PR status, cost estimate, and last healthy release. Same-day teardown still
   applies when Git repair is unfinished; next bootstrap must follow the rejection check above.

For local kind, use the equivalent suspension sequence and inventory check, remove only the
authorized cluster/registry/volumes, restore any changed host settings, and record what data was
deleted. Restoring database backups or deleting retained local data needs explicit scope.

## Required failure tests

Prove normal and failed migration; wrong image signer; same-candidate reconciliation after abort;
root/child restart and suspension; cluster recreation with a rejected Git release; Git recovery
without DB downgrade; restore with known test records; protected PVC/Application deletion; and
no ALB recreation during teardown. Until these pass, this is a proposed procedure rather than
an operationally verified runbook. Target timed local recovery within 15 minutes of operator
action, excluding human PR-review time; measure it and revise the target if evidence disagrees.
