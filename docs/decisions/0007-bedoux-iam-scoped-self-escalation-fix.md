# ADR 0007: Close a self-escalation hole in bedoux-iam-scoped; add the EKS nodegroup SLR check

- Status: Accepted
- Date: 2026-07-28

## Context

P5.1's `eksctl create nodegroup` failed with `AccessDenied` on `iam:GetRole` for
`AWSServiceRoleForAmazonEKSNodegroup` — EKS's `CreateNodegroup` API always checks whether
this account-wide service-linked role exists, using the caller's own IAM permissions to do
the check. `bedoux-admin`'s scoped policy (`bedoux-iam-scoped`, from P4.1, see
`docs/local-tooling.md`'s "AWS CLI identity" section) only granted role/policy actions on
`bedoux-*`-named resources, and this role isn't (and can't be) named `bedoux-*`. Creating
the service-linked role directly (`iam:CreateServiceLinkedRole`) succeeded — that action
isn't resource-scoped the same way — but the *existence check* (`iam:GetRole`) still failed
on retry, confirming this needed a real policy change, not a one-time bootstrap step.

While diagnosing this, a second and more serious problem surfaced: `bedoux-iam-scoped`
granted `iam:*Policy*` on `arn:aws:iam::*:policy/bedoux-*` — and `bedoux-iam-scoped` is
itself a `bedoux-*`-named resource. That means `bedoux-admin` had `iam:CreatePolicyVersion`
and `iam:SetDefaultPolicyVersion` on its own constraining policy, fully contradicting the
P4.1 design intent ("cannot grant itself more power" — `docs/PROGRESS.md`'s Known facts).
Confirmed by reading the live policy document (`aws iam get-policy-version`), not assumed.
`bedoux-admin` could not attach a *new* policy to itself (no `iam:AttachUserPolicy` on the
user resource), but rewriting the content of an already-attached policy in place and
setting that as the default version achieves the same result — a real, exploitable
privilege-escalation path from `bedoux-admin` to full account admin.

## Decision

Both fixes were applied as a single policy edit, made by the owner via the console
(root/admin identity), deliberately **not** via `bedoux-admin`'s own API access — using
`bedoux-admin` to patch the very policy that constrains it would exercise the escalation
path being closed, even for an otherwise-reasonable change.

`bedoux-iam-scoped` v2 adds two statements to the original v1 grant:

1. **`DenySelfEscalationViaOwnPolicy`** — an explicit `Deny` on
   `iam:CreatePolicyVersion`, `iam:SetDefaultPolicyVersion`, `iam:DeletePolicy`,
   `iam:DeletePolicyVersion`, scoped to exactly one resource:
   `arn:aws:iam::*:policy/bedoux-iam-scoped`. `bedoux-admin` can still read, attach, and
   detach this policy, and can still fully manage every other `bedoux-*`-named role and
   policy — only this one policy's own content is now permanently protected. Any future
   change to `bedoux-iam-scoped` requires the owner, via root/console, same as this one.
2. **`EksNodegroupServiceLinkedRoleCheck`** — `iam:GetRole` (read-only), scoped to
   exactly `arn:aws:iam::*:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup`
   — the single service-linked role EKS's managed-nodegroup creation needs to check.

Both fixes verified live, not assumed: after the console edit,
`aws iam create-policy-version ... --set-as-default` with a wide-open test document
(`{"Effect":"Allow","Action":"*","Resource":"*"}`) was attempted against
`bedoux-iam-scoped` as `bedoux-admin` and returned `AccessDenied ... explicit deny`; and
`aws iam get-role --role-name AWSServiceRoleForAmazonEKSNodegroup` succeeded where it had
previously failed.

## Consequences

- The self-escalation hole is closed without narrowing `bedoux-admin`'s legitimate
  `bedoux-*` role/policy management — the fix is a single scoped `Deny`, not a rewrite of
  the broader grant.
- `bedoux-iam-scoped` itself is now effectively frozen from the inside: any future
  legitimate change to it (e.g. a new pending decision needing another IAM action) must go
  through the owner via console/root, the same one-time-friction pattern used for every
  other account-level action in this project (root MFA, budget setup, this fix).
- The same self-review should be applied to any *future* custom IAM policy in this
  project before it's trusted: if a scoped policy's resource pattern can match the policy's
  own ARN, check for this exact class of hole before relying on the "can't self-escalate"
  claim.
- `eksctl create nodegroup` can now proceed for P5.1.
