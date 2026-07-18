# AWS learning-session runbook

This runbook prevents an EKS exercise from turning into an unplanned monthly
environment. Slash commands: `/aws-session-start` walks "Before the session",
`/aws-teardown-verify` walks "Teardown" with concrete read-only sweep commands, and
`/closeout` handles "Session closeout". Every checklist result is recorded as evidence in
`docs/PROGRESS.md`.

## Before the session

- [ ] Confirm the intended AWS account and temporary identity.
- [ ] Confirm the selected region; do not infer it from a console URL.
- [ ] Review month-to-date cost, credit balance, and budget status.
- [ ] Confirm no unexpected resources already exist.
- [ ] Review the current Terraform plan and regional cost estimate.
- [ ] Set the session end time and teardown reminder.
- [ ] Confirm the destruction command and inventory commands are available.
- [ ] Record the planned persistent-resource exceptions.

## During the session

- [ ] Apply the standard project tags to every supported resource.
- [ ] Record cluster creation and destruction timestamps.
- [ ] Create only the milestone's required resources.
- [ ] Capture learning evidence without recording secrets or account IDs.
- [ ] Investigate unexpected resources before proceeding.

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

