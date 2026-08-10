# ADR 0015: Bound every delegated project role to the operator's non-IAM ceiling

- Status: Accepted
- Date: 2026-08-10
- Supersedes: ADR 0007's conclusion that its direct-policy deny fully closes self-escalation

## Context

ADR 0007 correctly closed one direct path: `bedoux-admin` cannot create a new version of the
`bedoux-iam-scoped` policy that grants its own IAM user more permissions. P10.4's required
re-review found a second-hop path that ADR 0007 did not model.

`bedoux-iam-scoped` v3 allows role and policy management on `bedoux-*` resources. That combination
lets the operator create or modify a project role's trust and attach or rewrite another project
policy. `PowerUserAccess` permits STS, and none of the project roles currently has a permissions
boundary. Protecting only `bedoux-iam-scoped` therefore does not stop an operator from obtaining
broader permissions through a different role. The finding is documented as F-1004-1 in
`docs/iam-review-p10.md`; no exploit was attempted.

P10.4 also found three narrower managed-policy improvements: move VPC CNI permissions from the
node role to an exact-ServiceAccount IRSA role, replace ECR read-only with pull-only on the node,
and migrate EBS CSI to AWS's v2 policy. Those declaration changes do not themselves close the
delegated-IAM path.

## Decision

1. Every Terraform-managed `bedoux-*` role receives AWS-managed `PowerUserAccess` as a
   **permissions boundary**, including session-only roles. The boundary does not grant power; a
   role receives only the intersection of its existing narrow permissions and the boundary. It
   caps a rewritten or newly attached policy at the same non-IAM service ceiling already granted
   to `bedoux-admin`, while excluding general IAM, Organizations, and Account administration.
2. After the boundary is attached to all existing persistent roles, the owner replaces
   `bedoux-iam-scoped` v3 with v4 through the root/admin console. The v4 policy:
   - preserves `DenySelfEscalationViaOwnPolicy`;
   - allows role creation and permission/trust changes only when the target role has the exact
     AWS-managed `PowerUserAccess` boundary;
   - explicitly denies deleting that boundary or replacing it with another boundary;
   - preserves only the already-proven service-linked-role check and OIDC/project-IAM operations.
3. The boundary and v4 edit are applied only inside a manually opened AWS session. Terraform
   first attaches the boundary; the owner then applies v4, avoiding a state where the delegated
   policy requires a boundary that existing roles do not yet have.
4. T-1004 requires live read-back of every role boundary and the v4 document plus negative policy
   simulation (or a bounded, cleaned-up denied API test) showing an unbounded project role cannot
   be created or modified. Static Terraform validation alone is insufficient.
5. As part of the same declaration hardening, the node role moves from ECR read-only to pull-only,
   VPC CNI gets an exact `kube-system/aws-node` IRSA role, and EBS CSI moves to
   `AmazonEBSCSIDriverPolicyV2`. P10.5 applies and live-verifies those staged changes before its
   NetworkPolicy drill.

## Consequences

- Rewriting a project policy or trust can no longer produce an IAM-capable role session; the
  permissions boundary remains the maximum even if an attached policy says `Action: "*"`.
- Existing narrow role policies and exact OIDC/service trusts remain the primary controls. The
  boundary is defense in depth, not a replacement for least privilege.
- The boundary is AWS-managed and outside `bedoux-admin`'s edit capability, avoiding a second
  owner-maintained policy whose own mutability would need protection.
- Some unused optional IAM reads in vendor policies, such as legacy IAM server-certificate reads,
  may be ineffective under the boundary. The learning profile uses ACM, not IAM server
  certificates; any future requirement must be reviewed rather than widening the boundary
  silently.
- ADR 0007 remains historically accurate for the direct hole it fixed, but its claim of complete
  self-escalation closure is superseded by this decision.
