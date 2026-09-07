# Phase orchestration workflow

Use this workflow to resume, execute, and close out repository work without bypassing the
phase gates in `AGENTS.md`. `docs/PROGRESS.md` remains the only authoritative execution state;
this document explains how to operate that state, not replace it.

## Resume

1. Read `AGENTS.md`, `START-HERE.md`, and `docs/PROGRESS.md` completely.
2. Run the resume checks recorded in `START-HERE.md`, including `git status --short`, recent
   history, and the latest recorded verification command.
3. Reconcile the filesystem, Git/GitHub state, and any live-system evidence with the progress
   log. Record a discrepancy before continuing; never silently infer that a task or merge
   completed.
4. Identify the one checklist item marked `IN PROGRESS`. Read its active-phase section in
   `docs/IMPLEMENTATION-PLAN.md` and only the referenced decisions, tests, and runbooks.
5. If no item is active, wait for the owner to activate the next eligible item. Do not start a
   later phase or infer gate approval.

## Execute one item

1. State the intended outcome and evidence before editing.
2. Prefer the smallest reversible change that can produce that evidence.
3. Preserve unrelated changes. Stop if an existing change overlaps and cannot be separated
   safely.
4. Verify after each meaningful change. Use local fixtures and local infrastructure before AWS.
5. Keep secrets, AWS account IDs, personal email addresses, and raw identity output out of
   committed artifacts and evidence.
6. Mark the item complete only after every named test-plan artifact exists and its result is
   recorded in `docs/PROGRESS.md`.

## Delegate bounded work

Use a smaller subagent only when the user or active agent policy permits delegation and the
subtask is independent and bounded. Give it the minimum relevant source files and ask for a raw
artifact, diff review, test result, or diagnosis. Keep these responsibilities with the primary
operator:

- selecting or changing the active checklist item;
- editing authoritative progress and gate state;
- approving architecture or scope changes;
- opening an AWS session or authorizing a mutation;
- combining evidence and declaring completion.

Do not pass conclusions or expected answers into an independent validation task.

## Close out

1. Run the task's stated checks and the standing
   `toolbox run -c bedoux-aws /usr/bin/make docs-check` gate when documentation or diagrams
   changed.
2. Review `git diff --check`, the scoped diff, and `git status --short`.
3. Update the checklist and prepend an ISO 8601 session entry to `docs/PROGRESS.md`, including
   commands, results, exact next action, and `AWS: none` when no AWS system was touched.
4. Refresh `START-HERE.md` and `docs/HANDOFF.md` when the current checkpoint or handoff changed.
5. Use the repository commit convention. Phase completion still requires a separate explicit
   owner gate commit before the next phase becomes active.
