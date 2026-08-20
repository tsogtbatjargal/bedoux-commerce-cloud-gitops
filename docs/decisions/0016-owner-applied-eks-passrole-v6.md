# ADR 0016: Add exact EKS execution-role PassRole to the owner-managed policy

- Status: Accepted
- Date: 2026-08-17
- Supersedes: the live v4 policy declaration in ADR 0015's execution procedure

## Context

The P11.3 Terraform plan was valid, but EKS creation stopped because the non-root
`bedoux-admin` operator could not pass the Bedoux cluster execution role to EKS. The owner
then created policy versions v5 and v6 in the AWS console. The v6 default document was read
back after the live session and includes the earlier narrow role-introspection grant plus the
new execution-role grant.

## Decision

Keep the v4 boundary, self-protection, and role/policy/OIDC scoping unchanged. Add only
`iam:PassRole` on the four exact Bedoux EKS execution roles, conditioned on
`iam:PassedToService=eks.amazonaws.com`. Keep the committed v4 JSON as historical evidence and
store the current owner-applied default as `infra/iam/bedoux-iam-scoped-v6.json`.

## Consequences

Terraform can create the bounded EKS cluster and managed node group under the operator profile,
while the operator cannot pass arbitrary roles or pass these roles to another AWS service. The
verification script must compare the live default with v6. Any further live policy change needs
another superseding ADR and a new committed declaration.
