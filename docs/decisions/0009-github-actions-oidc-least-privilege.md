# ADR 0009: GitHub Actions uses a branch-bound OIDC role with namespace-scoped deployment access

- Status: Accepted
- Date: 2026-07-30

## Context

P6 needs a CI/CD path that can push immutable images to ECR and deploy the Helm release to a
short-lived learning EKS cluster. Long-lived AWS access keys in GitHub would violate the
project's identity boundary. Giving the CI role cluster-admin access would also hide an
important least-privilege decision behind a convenient default.

## Decision

Terraform declares one IAM OIDC provider for `https://token.actions.githubusercontent.com`
and one `bedoux-github-actions-role`. Its trust policy requires both the AWS STS audience and
the exact GitHub subject for `bedoux-tech/bedoux-commerce-cloud`'s `main` branch. Pull-request
validation receives no `id-token: write` permission and therefore cannot assume AWS credentials.

The deployment role may obtain an ECR authorization token, push only the two Bedoux ECR
repositories, and describe only the learning EKS cluster. An EKS access entry attaches
`AmazonEKSEditPolicy` only to the `bedoux` namespace. A human operator creates that namespace
as part of P6.4's reviewed session setup; the CI role cannot create namespaces or administer
the cluster.

The OIDC provider, role, and policy have no hourly charge and become persistent-resource
allowlist entries after their first P6.4 creation. They are declared in P6.3 but are not applied
until the manual AWS-session checklist is active.

## Consequences

- GitHub holds no AWS secret and short-lived credentials are issued only to trusted main-branch
  deployment runs.
- A compromised pull request cannot obtain AWS credentials through this workflow.
- P6.4 needs an explicit namespace-bootstrap step by the human operator before the deployment
  workflow runs. This small extra step keeps CI's Kubernetes access materially narrower than
  cluster-admin.
- A future change to GitHub environments, branches, repositories, ECR repositories, or
  Kubernetes scope requires a new ADR rather than broadening this role implicitly.
