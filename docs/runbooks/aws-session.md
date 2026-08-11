# AWS learning-session runbook

This runbook prevents an EKS exercise from turning into an unplanned monthly
environment. Slash commands: `/aws-session-start` walks "Before the session",
`/aws-teardown-verify` walks "Teardown" with concrete read-only sweep commands, and
`/closeout` handles "Session closeout". Every checklist result is recorded as evidence in
`docs/PROGRESS.md`.

## Before the session

- [ ] Confirm the intended AWS account and identity: **`aws sts get-caller-identity
      --profile bedoux-admin`** must show the `bedoux-admin` IAM user, never `root`
      (see `docs/local-tooling.md`'s AWS CLI section). Root is only for account-level
      actions (MFA, billing) done manually by the owner in the console.
- [ ] Confirm the selected region; do not infer it from a console URL — pinned to
      `ca-central-1` (`docs/PROGRESS.md` Known facts).
- [ ] Review month-to-date cost, credit balance, and budget status. `aws budgets
      describe-budgets` is reliable immediately; `aws ce get-cost-and-usage`
      (Cost Explorer) can return `DataUnavailableException` for roughly the first 24h
      on a brand-new account while it ingests its first billing data — not a runbook
      failure, just don't rely on it being populated during that early window.
- [ ] Confirm no unexpected resources already exist.
- [ ] Review the current Terraform plan and regional cost estimate.
- [ ] Set the session end time and teardown reminder.
- [ ] Set an independent operator alarm for that deadline. Do not allow an agent command or
      terminal operation to extend the session: begin teardown at the alarm even if evidence
      capture is still running.
- [ ] Confirm the destruction command and inventory commands are available.
- [ ] Record the planned persistent-resource exceptions.

## During the session

- [ ] Apply the standard project tags to every supported resource.
- [ ] Record cluster creation and destruction timestamps.
- [ ] Create only the milestone's required resources.
- [ ] Capture learning evidence without recording secrets or account IDs.
- [ ] Investigate unexpected resources before proceeding.

## Kubernetes drill integration

Use this section for both local kind drills and AWS/EKS drills so Kubernetes failure work does
not need a separate skill or duplicated operating procedure.

Before a drill:

- [ ] Name the owning phase item and test ID, the healthy baseline, the single fault to induce,
      the tooling-only diagnostic path, the recovery action, and the required evidence.
- [ ] Use the phase-specific runbook when one exists. For the four already-proven incident
      shapes, use `docs/runbooks/p8-troubleshooting.md`.
- [ ] Prefer kind for the first proof. A local-only kind drill does not open an AWS session, but
      it still follows the active phase, evidence, rollback, and closeout rules.
- [ ] For EKS drills or any drill that changes AWS resources, complete every **Before the
      session** item above and obtain the required owner approval before mutation. A standalone
      read-only AWS check verifies identity/region and sanitizes output but does not claim that a
      billable session is open.
- [ ] Reserve teardown margin inside the session deadline. The independent alarm overrides the
      drill: stop evidence capture and begin teardown when it fires.

During a drill:

- [ ] Prove the baseline healthy before injecting one reversible fault.
- [ ] Diagnose from `kubectl`, Helm, application, and approved read-only AWS output before using
      knowledge of the injected cause.
- [ ] Change only the declared fault surface. Do not stack faults or broaden permissions to make
      a drill pass.
- [ ] Recover through the declared rollback path and re-run the same health checks used for the
      baseline.
- [ ] Delete debug pods, temporary namespaces, test objects, and other drill-only Kubernetes
      state before infrastructure teardown.

An AWS/EKS drill is not complete until the **Teardown** checklist below is clean. Record a local
kind drill as `AWS: none`; never run AWS sweeps merely to decorate local evidence.

## Teardown

- [ ] Delete Kubernetes Ingress resources and wait for ALB deletion.
- [ ] Destroy Terraform-managed application infrastructure.
- [ ] Confirm EKS cluster and node group deletion.
- [ ] Confirm RDS instance, snapshots, and subnet groups match the allowlist.
- [ ] Confirm ALBs, target groups, NAT Gateways, and elastic IPs are absent.
- [ ] Confirm no unattached EBS volumes or snapshots remain.
- [ ] Confirm CloudFormation or `eksctl` stacks are absent or expected.
- [ ] Confirm persistent S3/ECR resources match the allowlist.
- [ ] Review the AWS resource inventory across the selected region.
- [ ] Recheck Billing after AWS usage data has had time to update.

## Session closeout

- [ ] Update the phase checklist and append a session log entry in `docs/PROGRESS.md`
      (including AWS resources created/destroyed and the estimated session cost).
- [ ] Refresh the "Current checkpoint" block in `START-HERE.md`.
- [ ] Regenerate the fenced prompt in `docs/HANDOFF.md`.
- [ ] Commit using the convention (`<TaskID> complete: ...`).

## Stop conditions

Stop creating resources if:

- the identity or account is uncertain;
- the Terraform plan contains a NAT Gateway or unplanned service;
- the projected monthly cost exceeds USD 16;
- an existing resource cannot be explained;
- the teardown path has not been tested;
- a required permission would need broad administrator access without review.
