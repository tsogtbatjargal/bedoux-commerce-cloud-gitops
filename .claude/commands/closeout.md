---
description: End the session - update PROGRESS, refresh the checkpoint, regenerate HANDOFF, commit
---

Close out the current work session per the closeout section of
`docs/runbooks/aws-session.md` (it applies to non-AWS sessions too):

1. `docs/PROGRESS.md`: update the overall-status table and phase checklist (evidence on every
   newly checked item), and append a session log entry following the schema in
   `START-HERE.md` — including the `AWS:` line (resources created/destroyed + estimated cost,
   or `AWS: none`).
2. If the session touched AWS and `/aws-teardown-verify` has not been run: run it now, before
   anything else.
3. Refresh the "Current checkpoint" block in `START-HERE.md` (state, active phase, next
   action).
4. Regenerate the fenced prompt in `docs/HANDOFF.md` to match the new state.
5. Run `make docs-check`; fix anything it reports.
6. Show the operator a proposed commit message using the convention
   (`<TaskID> complete: ...` / gate / `Fix ...`) and commit once confirmed.

Never include secrets, tokens, or AWS account IDs in any of the updated files or the commit
message.
