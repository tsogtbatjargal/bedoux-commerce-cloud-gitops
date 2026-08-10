# P10.4 IAM re-review

Review date: 2026-08-10
Status: **IN PROGRESS — ADR 0015 is accepted and its offline remediation is staged; live
application and negative verification are still required before T-1004 can pass.**

## Scope and method

This review covers every role and customer-managed policy created by the project since P5:
five persistent roles, three session-only roles, two persistent customer policies, and two
session-only customer policies. It also re-checks `bedoux-iam-scoped` because ADR 0007 requires
future customer policies to be tested for the same class of self-escalation risk.

Evidence was collected without IAM mutation:

- exact-name `get-role`, `list-attached-role-policies`, and `list-role-policies` calls;
- exact-ARN `get-policy` and `get-policy-version` calls for Bedoux-managed policies;
- exact-provider `get-open-id-connect-provider` calls derived from the reviewed role trusts;
- committed Terraform trust and permission documents;
- IAM Access Analyzer `validate-policy` for all four customer-policy declarations;
- current AWS-managed-policy and EKS identity guidance from AWS documentation.

No broad account role/policy enumeration was used. AWS account identifiers and credentials were
not retained in this document or command output. `bedoux-admin` was correctly denied
`iam:GetPolicy` for AWS-managed policies, so their current documents were reviewed from AWS's
official managed-policy reference rather than broadening the operator policy.

## Role inventory

| Role | Lifetime | Trust boundary | Attached permission | Result |
|---|---|---|---|---|
| `bedoux-eks-cluster-role` | Persistent | `eks.amazonaws.com` only | `AmazonEKSClusterPolicy` | Live declaration match. AWS-required service role; broad service actions are accepted for the EKS control plane. Missing permissions boundary is part of F-1004-1. |
| `bedoux-eks-nodegroup-role` | Persistent | `ec2.amazonaws.com` only | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` | Live declaration match. F-1004-2 and F-1004-3 narrow the two latter attachments. Missing boundary is part of F-1004-1. |
| `bedoux-ebs-csi-role` | Persistent | Cluster OIDC; exact `kube-system/ebs-csi-controller-sa` subject and STS audience | `AmazonEBSCSIDriverPolicy` | Live declaration match, but F-1004-4 replaces the legacy policy with AWS's narrower v2. Missing boundary is part of F-1004-1. |
| `bedoux-alb-controller-role` | Persistent | Cluster OIDC; exact `kube-system/aws-load-balancer-controller` subject and STS audience | `bedoux-alb-controller-policy` | Live declaration match; no inline policies. Its upstream controller policy contains necessary service wildcards and tag conditions and produced zero Access Analyzer findings. Missing boundary is part of F-1004-1. |
| `bedoux-github-actions-role` | Persistent | GitHub OIDC; exact custom numeric-ID repository/main subject and STS audience | `bedoux-github-actions-policy` | Live trust match; no inline policies. The live policy is intentionally one declaration behind P10.3 and will add only `ecr:GetDownloadUrlForLayer` in P10.5. Missing boundary is part of F-1004-1. |
| `bedoux-product-images-role` | Session-only | Cluster OIDC; exact `bedoux/bedoux-api` subject and STS audience | `bedoux-product-images-read-policy` | Correctly absent after teardown. Declaration permits only `s3:GetObject` on the generated bucket's `products/*` prefix. Missing boundary on future creation is part of F-1004-1. |
| `bedoux-secrets-manager-role` | Session-only | Cluster OIDC; exact `bedoux/bedoux-api-secrets` subject and STS audience | `bedoux-secrets-manager-policy` | Correctly absent after teardown. Declaration permits only `secretsmanager:GetSecretValue` on the one generated secret. Missing boundary on future creation is part of F-1004-1. |
| `bedoux-cloudwatch-observability-role` | Session-only | Cluster OIDC; exact `amazon-cloudwatch/cloudwatch-agent` subject and STS audience | `CloudWatchAgentServerPolicy` | Correctly absent after teardown. The AWS-managed policy is broad, but use is restricted to one add-on ServiceAccount and the whole role is same-session temporary. Missing boundary on future creation is part of F-1004-1. |

All five live roles have the standard project/environment tags, a one-hour maximum session, no
inline policies, and currently no permissions boundary. The persistent GitHub OIDC provider has
only the STS audience and standard tags. The cluster OIDC provider is correctly absent after
teardown, so the retained EBS and ALB roles cannot currently be assumed.

## Customer-policy inventory

| Policy | Live state | Resource scope | Validation/result |
|---|---|---|---|
| `bedoux-alb-controller-policy` | Persistent, v1, one attachment | AWS Load Balancer Controller's reviewed permission set; unsupported resource scoping uses `*`, while creation/deletion paths use service-name and controller resource/request tags where AWS supports them | Live document matches source; Access Analyzer returned zero findings. Accepted behind the exact controller ServiceAccount trust and absent session OIDC provider. |
| `bedoux-github-actions-policy` | Persistent, v1, one attachment | ECR auth token on required `*`; image actions on exactly `bedoux-api`/`bedoux-web`; describe exactly cluster `bedoux` | Live state is the pre-P10.3 version. Terraform adds only layer download for signature/SBOM reads. Expected declaration returned zero Access Analyzer findings. |
| `bedoux-product-images-read-policy` | Correctly absent | One temporary bucket's `products/*` objects | Declaration returned zero Access Analyzer findings. |
| `bedoux-secrets-manager-policy` | Correctly absent | One temporary database secret | Declaration returned zero Access Analyzer findings. |

## Findings

### F-1004-1 — high: ADR 0007 leaves a second-hop self-escalation path

`bedoux-iam-scoped` v3 still has both `iam:*Role*` on `bedoux-*` roles and
`iam:*Policy*` on `bedoux-*` policies. Its explicit deny prevents `bedoux-admin` from rewriting
`bedoux-iam-scoped` itself, but does not prevent this sequence:

1. create or modify another `bedoux-*` role trust;
2. create, rewrite, or attach a policy with permissions beyond the intended operator ceiling;
3. use STS directly or through a chosen federated/service principal to obtain that role's
   effective permissions.

AWS-managed `PowerUserAccess` currently permits STS actions because only IAM, Organizations, and
Account actions are excluded from its main allow. None of the project roles has a permissions
boundary. The combined path is therefore real from the policy documents; no exploit was attempted.

Accepted remediation is [ADR 0015](decisions/0015-bound-delegated-project-roles.md): attach
AWS-managed `PowerUserAccess` as the permissions boundary on every project role, then replace
`bedoux-iam-scoped` v3 with an owner-applied v4 that requires that exact boundary for delegated
role creation and permission/trust changes and denies removing or replacing it. A boundary grants
nothing by itself; it limits any project role to the intersection of its narrow attached policy
and the operator's existing non-IAM ceiling. The boundary is AWS-managed, so `bedoux-admin` cannot
rewrite it.

The owner accepted ADR 0015 on 2026-08-10. Terraform now declares the boundary on every project
role, and `infra/iam/bedoux-iam-scoped-v4.json` plus
`docs/runbooks/p10-iam-remediation.md` stage the owner-controlled change. Access Analyzer returned
zero findings for v4. Applying it still requires an active AWS session because the repository
forbids IAM mutation outside the session runbook. T-1004 remains open until the owner-applied
policy change and live negative verification exist.

### F-1004-2 — medium: VPC CNI permissions sit on the whole node identity

`AmazonEKS_CNI_Policy` is attached to `bedoux-eks-nodegroup-role`. AWS permits this but recommends
a separate role associated only with the `kube-system/aws-node` ServiceAccount, then removing the
policy from the node role. The remediation will add `bedoux-vpc-cni-role`, bind the pinned EKS VPC
CNI add-on to it through IRSA, and remove the node attachment after the new identity is proven.

### F-1004-3 — low: node ECR policy exposes read APIs beyond image pulls

The node currently uses `AmazonEC2ContainerRegistryReadOnly`. Current EKS node-role guidance uses
`AmazonEC2ContainerRegistryPullOnly`, which drops repository-policy, lifecycle, scan, tag, and
inventory reads that kubelet does not require. Terraform will switch to the pull-only attachment;
the old persistent attachment must be explicitly detached in the reviewed P10.5 session because
the repository deliberately detaches persistent attachment state before every session destroy.

### F-1004-4 — medium: EBS CSI uses the legacy managed policy

The role predates `AmazonEBSCSIDriverPolicyV2`, published by AWS in April 2026. V2 restricts volume
and snapshot management through CSI ownership tags more consistently than the legacy policy.
Terraform will switch the exact EBS controller ServiceAccount role to v2; the old attachment will
be detached and real gp3 provisioning re-verified during P10.5.

## Reviewed broad grants that remain accepted

- `AmazonEKSClusterPolicy` and `AmazonEKSWorkerNodePolicy` are AWS's standard control-plane and
  kubelet policies. Their `Resource: "*"` read/control actions are service-defined and are bounded
  by service-only trust plus the proposed maximum boundary.
- The ALB controller policy is the upstream controller permission set. Wildcards that can be
  conditioned are constrained by service or controller tags; exact ServiceAccount trust and
  same-session OIDC deletion prevent use outside the controller/session. Access Analyzer found no
  policy errors, security warnings, warnings, or suggestions.
- `CloudWatchAgentServerPolicy` is broad, but its role is exact-ServiceAccount and session-only;
  live teardown confirms both role and cluster trust provider are absent. A custom telemetry
  policy would add maintenance risk without changing standing exposure.
- ECR `GetAuthorizationToken` cannot be repository-scoped. All subsequent GitHub image actions
  remain restricted to the two project repositories.

## Verification sources

- [AWS EKS node IAM role](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html)
- [AWS VPC CNI IRSA guidance](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html)
- [AmazonEBSCSIDriverPolicyV2 reference](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEBSCSIDriverPolicyV2.html)
- [PowerUserAccess reference](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/PowerUserAccess.html)
- [IAM permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
