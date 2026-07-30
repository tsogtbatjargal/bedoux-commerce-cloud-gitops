# GitHub branch-protection / local-guardrail runbook

## Current private-repository constraint

P6.3's GitHub Actions workflow is green, but GitHub reports that rulesets cannot be enforced
for this private repository without an eligible organization plan. The classic `main` branch
protection endpoint is also unavailable. Per ADR 0010, use the local pre-push guardrail below
as a compensating control until server-side protection becomes available.

This is intentionally **not** described as branch protection: it only protects a clone where
the hook is installed. A different clone, the GitHub web UI, or a user who removes the hook can
bypass it. The PR workflow remains the actual automated validation evidence.

## Install and verify the local guardrail

1. From the repository root, preview the target with:

   ```text
   scripts/install-git-guardrails.sh --dry-run
   ```

2. Install it only after reviewing that target:

   ```text
   scripts/install-git-guardrails.sh --install
   ```

   The installer refuses to overwrite an existing `pre-push` hook. Stop and review any existing
   hook rather than replacing it.

3. Verify the installed hook blocks a simulated direct `main` update:

   ```text
   printf 'refs/heads/main %040d refs/heads/main %040d\n' 1 0 | \
     "$(git rev-parse --git-path hooks/pre-push)" origin origin
   ```

   It must exit non-zero and say it is refusing a direct push of `main`.

4. Push feature branches normally and use PR #1's required workflow checks as the review gate.
   Do not add AWS repository secrets; P6.4 uses GitHub OIDC, not static credentials.

## Future server-side rule

After the P9 history review and a move to a GitHub plan/visibility that supports enforcement,
replace this compensating control with a server-side `main` rule: pull requests, the four
`PR validation` checks, up-to-date branches, conversation resolution, no force pushes or
deletion, and administrators included. Record the live API/console evidence then.
