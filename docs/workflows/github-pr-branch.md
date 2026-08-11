# GitHub pull-request branch workflow

Use this workflow for repository changes that should move through a feature branch and pull
request. It complements `docs/runbooks/github-branch-protection.md`; it does not turn the local
pre-push hook into server-enforced branch protection.

## Prepare

1. Use `docs/workflows/phase-orchestration.md` to confirm the active checklist item and last
   verified checkpoint.
2. Inspect `git status -sb`, `git log --oneline -5`, the current branch or detached commit, and
   relevant remotes. Preserve unrelated worktree changes.
3. Confirm the intended base commit. If the worktree is detached, create the feature branch from
   that exact reviewed commit. If it is on `main`, update it only when the user requested or
   approved network-changing Git operations.
4. Create one narrowly named feature branch for the active checklist item.

## Implement and review locally

1. Make small reversible changes and run the checklist item's required tests.
2. Run `make docs-check` for documentation or diagram changes.
3. Review `git diff --check`, `git diff --stat`, the full scoped diff, and `git status --short`.
4. Update `docs/PROGRESS.md` with truthful local evidence before publishing a completion claim.
5. Commit only the intended paths using the repository convention. Do not include secrets,
   account identifiers, personal email addresses, generated credentials, or unrelated changes.

## Publish and validate

Publishing is an external state change. Do it only when the user's request includes publication
or the owner has explicitly directed it.

1. Push the feature branch; never push `main` directly.
2. Open a draft pull request with the task scope, evidence, risks, rollback, and any deliberately
   deferred live proof.
3. Inspect every required check. Diagnose failures from logs, make a focused repair on the same
   branch, rerun local checks, and push again.
4. Keep the pull request draft until its declared review boundary and automated checks are ready.
5. Do not claim merge or completion from a green check alone. Verify the actual PR and merge
   state, then reconcile it into `docs/PROGRESS.md`.

## Merge handoff

1. Confirm the merged commit and that the next operator can reach it from the intended base.
2. Record the PR, CI run, merge state, and remaining live proof without exposing sensitive data.
3. Do not activate a later phase. A phase gate still requires the owner's explicit, dedicated
   gate commit.

Use `docs/runbooks/github-branch-protection.md` to install or verify the clone-local pre-push
guardrail and to understand the current private-repository enforcement limitation.
