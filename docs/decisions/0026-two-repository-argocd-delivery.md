# ADR 0026: Separate application and environment repositories with Argo CD delivery

- Status: Proposed
- Date: 2026-09-08
- Scope: GO-A GitOps expansion plan; no implementation activated.
- Related: [GitOps plan](../gitops-expansion-plan.md),
  [recovery procedure](../runbooks/gitops-recovery.md).

## Context

The owner wants GitOps learning/interview evidence reusable for a future bedoux.ca project,
retaining the existing repository. The owner selected Argo CD, local dev/staging on one kind
cluster, eventual temporary EKS proof, reviewed promotion, self-healing with deletion protection,
later progressive delivery and separate traffic/Git recovery.

Current GitHub Actions directly deploys signed images through Helm and a P13 canary helper.
The application chart has migration hooks whose behavior depends on Helm's lifecycle. Merely
splitting repositories or pointing Argo at the chart would not preserve those guarantees.

## Proposed decision

Use `bedoux-commerce-cloud` for API/web code, tests, migrations and reusable chart source. Add
one private `bedoux-commerce-env` repository for release selections, environment values, Argo
configuration and eventually infrastructure operations. Retain the current repository's history
and PROGRESS as the cross-repository execution authority.

An explicit release action builds/verifies immutable artifacts and proposes an env PR. Owner
merge authorizes automatic reconciliation of that approved desired state in the authorized
running cluster. Promote the same artifact tuple between environments. Application CI stops
directly deploying to GitOps-owned namespaces after a tested handover.

Argo CD reconciles desired resources; later Argo Rollouts manages progressive deployment.
Enable stateless self-healing, initially disable automatic pruning/allow-empty, and separately
protect PVCs/namespaces from Application deletion. Define narrow exceptions for controller-owned
fields. Terraform and session bootstrap remain operator-controlled, with existing plan approvals.

Use a small fixed bootstrap root to generate scoped Applications from env Git, combining a pinned
app/chart source and the reviewed env values revision. Keep environment-specific identifiers
and credentials in documented bootstrap bindings outside Git. This is an explicit recovery
dependency, not a claim that Git alone restores a cluster. GO-1 must prove consistent revision
selection, identifier handling and the privilege boundary before implementing automation.

Replace Helm event-dependent migration behavior only in the GitOps profile with ordered,
release-specific forward migration Jobs after DB/credential readiness and before app promotion.
No automatic schema downgrade. Preserve signature enforcement at the deployment boundary and
P13's paired API/web, measured traffic, target-health and drain requirements in the new design.

On canary failure, automatically restore stable traffic and retain failed/degraded status.
Git repair is a separate owner-reviewed revert or fix-forward PR; no automatic Git revert or
rejected-candidate retry. A fresh cluster must not blindly replay a known rejected release.
Teardown suspends root/workload reconciliation before resource deletion.

## Relationship to earlier decisions

No accepted ADR is edited or superseded while this record is Proposed. If accepted and activated,
the new profile supersedes these delivery-specific portions while preserving learning history:

| Earlier ADR | Change for the GitOps profile | Preserved contract |
|---|---|---|
| 0005 | Argo-ordered migration Jobs replace Helm install/upgrade event triggers | Forward migration before promotion, no downgrade, explicit seeding |
| 0009 | App CI publishes artifacts/proposes releases; Argo owns workload deployment | Least privilege, scoped identities, reviewed trust changes |
| 0023 | Argo Rollouts replaces the workflow/Helm canary orchestrator after parity tests | Error attribution, paired paths, observed routing/health and safe draining |

ADRs 0010/0013's private-repo limitations, 0012's application secret retrieval, and the budget,
region, tags and same-day teardown policies remain. ADR 0025 stays Proposed; this decision does
not choose a production runtime, accept persistent EKS or activate hosting implementation.

## Alternatives and consequences

Flux's Helm controller would retain more Helm release semantics; the owner chose Argo CD for
this track. Keep that comparison as rationale, without implementing both. Argo's chart rendering
still requires a new migration/rollback contract.
[Argo Helm semantics](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/),
[Flux Helm releases](https://fluxcd.io/flux/components/helm/helmreleases/).

A third application repo would duplicate an existing source/history boundary; reusing the
current repo avoids that migration. Two repos introduce credential, provenance, CI and review
coordination costs. Initial manual pruning adds operator cleanup work. Aborted Git state remains
visible until a reviewed repair, which requires an explicit next-bootstrap guard.

## Acceptance boundary

The interview settles desired behavior, not acceptance of every technical proposal above.
Review this ADR and activate GO-1 separately to resolve its named design gates. Repository
creation, pushes/merges, local drills and AWS sessions keep their existing authorization
boundaries. Completion requires the T-GO evidence in the plan; no runtime claim is made here.
