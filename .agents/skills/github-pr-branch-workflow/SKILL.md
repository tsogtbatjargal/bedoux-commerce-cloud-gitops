---
name: github-pr-branch-workflow
description: Move this repository's active checklist item through a focused Git feature branch and GitHub pull request. Use for branch creation, scoped commits, pushes, draft PRs, CI/check diagnosis, review updates, merge verification, and post-merge checkpoint reconciliation. Preserve unrelated changes, never push main directly, and do not mistake the clone-local hook for server-enforced branch protection.
---

# GitHub PR Branch Workflow

Resolve the repository root and follow `docs/workflows/phase-orchestration.md` first to confirm
the active checklist item and verified base.

Follow `docs/workflows/github-pr-branch.md` as the canonical branch-to-merge procedure. Read
`docs/runbooks/github-branch-protection.md` for the current private-repository limitation and the
clone-local pre-push control.

Treat push, PR creation, review submission, and merge as external state changes; perform only
the actions the user or owner authorized. Verify actual GitHub state before recording a PR,
check, or merge as complete.

Use smaller agents only for explicitly permitted bounded review or diagnosis. Keep commit scope,
publication, progress reconciliation, and completion decisions with the primary operator.
