# ADR 0003: Public bedoux-tech repo; direct-to-main until CI/CD

- Status: Accepted
- Date: 2026-07-17

## Context

The project doubles as an interview portfolio, is developed solo by one owner with AI agents,
and follows a strict no-secrets discipline (`.gitignore` covers env files, keys, tfstate;
AGENTS.md forbids account IDs and secrets in tracked files). Heavy branch process would add
friction during the docs- and local-heavy early phases.

## Decision

- Host at **`bedoux-tech/bedoux-commerce-cloud`**, **public**.
- Until P6 (CI/CD), commit **directly to `main`** using the commit convention:
  `<TaskID> complete: <what + evidence pointer>`, gate commits
  `Phase N gate approved by owner; activate Phase N+1`, and `Fix ...` for bug fixes.
- At P6, introduce pull-request flow with branch protection on `main` (PR validation
  workflow as the required check). The ready-made local enforcement option is the
  root-owned pre-push hook pattern from `bedoux-vm-iac/scripts/git-hooks/pre-push` +
  `install-git-guardrails.sh`, if agent-driven pushes ever need a hard local block.

## Consequences

- Portfolio visibility from day one; every commit message is public, so the no-secrets rule
  extends to commit messages and evidence text.
- Low friction now; protection arrives exactly when a CI check exists to require.
- If an agent misbehaves before P6, `main` has no protection — mitigated by the small blast
  radius (docs + local code only, no AWS credentials in repo).
