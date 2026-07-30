# GitHub branch-protection checklist

Complete this once the `PR validation` workflow has run successfully at least once. It is an
owner-operated GitHub setting: do not assume a collaborator or an agent can change it.

1. In the repository, open **Settings → Branches** and add a protection rule for `main`.
2. Require a pull request before merging. Do not require an approving review for this solo
   learning repository, because that would prevent the owner from merging their own work.
3. Require these status checks to pass and require branches to be up to date:
   `API tests`, `Web lint, test, and build`, `Terraform and Helm validation`, and
   `Container build and scan`.
4. Require conversation resolution before merging; block force pushes and branch deletion.
5. Apply the rule to administrators too, then report the enabled settings and the successful
   workflow run URL or run number. Record that evidence in `docs/PROGRESS.md`.

Do not add AWS repository secrets. The P6.4 deployment workflow will use GitHub OIDC and an
AWS role instead of static credentials.
