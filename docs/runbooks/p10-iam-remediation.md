# P10 IAM remediation session

This runbook applies accepted [ADR 0015](../decisions/0015-bound-delegated-project-roles.md)
and closes P10.4 finding F-1004-1. It also stages the narrower node, VPC CNI, and EBS CSI
identities that P10.5 verifies during its real-cluster NetworkPolicy drill.

Do not run this procedure merely because the declarations exist. It mutates IAM and therefore
requires explicit owner approval for a time-bounded AWS session. Codex has no
`/aws-session-start`: manually complete every **Before the session** item in
[`aws-session.md`](aws-session.md), including an independent teardown alarm, before step 1.

## Safety and order

The order is deliberate:

1. Terraform attaches the immutable `PowerUserAccess` permissions boundary to every existing
   project role while `bedoux-iam-scoped` v3 is still active.
2. Terraform creates the bounded `bedoux-vpc-cni-role`, configures the pinned VPC CNI add-on to
   use the exact `kube-system/aws-node` identity, adds node ECR pull-only, and adds EBS CSI v2.
3. Only after the replacement identities are healthy are the three legacy managed-policy
   attachments removed.
4. The owner applies `bedoux-iam-scoped` v4 in the console. The project operator never edits its
   own constraining policy.
5. The verifier reads back all boundaries and v4, then proves an unbounded project role is denied.

If any step fails, do not apply v4 and do not remove a working legacy attachment. Preserve the
last known-working identity path, record the result in `docs/PROGRESS.md`, and begin teardown at
the independent alarm.

## 1. Import and review

From the repository root, after initializing the documented S3 backend:

```bash
scripts/terraform-persistent-state.sh import
scripts/terraform-persistent-state.sh import --execute
terraform -chdir=infra/terraform plan -out=/tmp/bedoux-p10.tfplan
terraform -chdir=infra/terraform show /tmp/bedoux-p10.tfplan
```

The reviewed plan must keep NAT absent and show:

- `permissions_boundary = arn:aws:iam::aws:policy/PowerUserAccess` on all imported persistent
  roles and the new `bedoux-vpc-cni-role`;
- `AmazonEC2ContainerRegistryPullOnly` added to the node role;
- `AmazonEBSCSIDriverPolicyV2` added to the EBS CSI role;
- `AmazonEKS_CNI_Policy` attached to the new VPC CNI role;
- pinned `vpc-cni` `v1.22.4-eksbuild.3` using that role with
  `enableNetworkPolicy = "true"` in its managed add-on configuration;
- no removal of `bedoux-iam-scoped`, no broad admin policy, and no unexpected service.

The three old attachments are persistent but not tracked after prior state detachment, so their
absence from the plan is expected. Step 3 removes them explicitly only after replacement proof.

## 2. Apply and prove replacement identities

Apply only the saved, reviewed plan:

```bash
terraform -chdir=infra/terraform apply /tmp/bedoux-p10.tfplan

aws eks describe-addon --profile bedoux-admin --region ca-central-1 \
  --cluster-name bedoux --addon-name vpc-cni \
  --query 'addon.{status:status,version:addonVersion,role:serviceAccountRoleArn,configuration:configurationValues}' --output json
aws eks describe-addon --profile bedoux-admin --region ca-central-1 \
  --cluster-name bedoux --addon-name aws-ebs-csi-driver \
  --query 'addon.{status:status,version:addonVersion,role:serviceAccountRoleArn}' --output json
kubectl -n kube-system get daemonset aws-node
kubectl -n kube-system get pods -l k8s-app=aws-node
kubectl get nodes
```

Both add-ons and every `aws-node` pod must be healthy, the VPC CNI configuration must report
`enableNetworkPolicy` as `true`, the `aws-node` pod must contain the network-policy agent sidecar,
and the node must be `Ready`. Do not retain full role ARNs in committed evidence; record role
names and the expected exact ServiceAccounts.

## 3. Remove only the superseded attachments

After step 2 passes:

```bash
aws iam detach-role-policy --profile bedoux-admin \
  --role-name bedoux-eks-nodegroup-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam detach-role-policy --profile bedoux-admin \
  --role-name bedoux-eks-nodegroup-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam detach-role-policy --profile bedoux-admin \
  --role-name bedoux-ebs-csi-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

Read back the three affected roles with exact-name `list-attached-role-policies`. The node must
retain only worker-node plus ECR pull-only; VPC CNI must retain CNI; EBS CSI must retain v2.

## 4. Owner console: install `bedoux-iam-scoped` v4 (superseded by v6)

The owner performs these steps using the root/admin console identity, never `bedoux-admin`:

1. Open IAM → Policies → `bedoux-iam-scoped` → **Versions**.
2. Create a new version by pasting the exact contents of
   `infra/iam/bedoux-iam-scoped-v4.json`.
3. Review that its required boundary is exactly AWS-managed `PowerUserAccess`, that unbounded
   role creation and boundary removal/replacement are explicitly denied, and that
   `DenySelfEscalationViaOwnPolicy` remains present.
4. Save it as the new default version. If IAM's five-version limit has been reached, delete only
   the oldest **non-default** version first; never delete the current default.
5. Report the new default version identifier for evidence, without account identifiers.

Stop and investigate if the console summary differs from the committed document.

For all sessions after 2026-08-17, use the owner-applied v6 declaration in
`infra/iam/bedoux-iam-scoped-v6.json`. v6 preserves the v4 controls, adds the narrow role
introspection needed by Terraform, and allows `iam:PassRole` only for the four Bedoux EKS
execution roles when passed to `eks.amazonaws.com`; ADR 0016 records the change.

## 5. Exact read-back and bounded negative test

Preview, then execute the repository verifier:

```bash
scripts/verify-iam-boundary.sh
scripts/verify-iam-boundary.sh --execute
```

Success requires all six exact persistent roles to have the boundary, live v6 to match the
committed JSON semantically, and the unbounded `bedoux-boundary-negative-test` create call to fail
with an explicit deny. The verifier refuses to run the negative test if that role already exists.
If creation unexpectedly succeeds, stop: v6 intentionally prevents `bedoux-admin` from cleaning
up an unbounded role, so the owner must delete that exact powerless test role in the admin console
before any other work continues.

Record the sanitized PASS lines and timestamp in `docs/PROGRESS.md`. Never record the AWS account
ID, full ARNs containing it, or raw denial output.

## 6. Continue P10.5 and tear down

P10.5 may continue its NetworkPolicy drill only after the IAM proof passes. Before the session
deadline, run the guarded destroy path and every teardown sweep item from `aws-session.md`.
The persistent allowlist after this change contains six bounded project roles; all temporary EKS,
VPC, load-balancer, storage, database, and observability resources must still be absent.
