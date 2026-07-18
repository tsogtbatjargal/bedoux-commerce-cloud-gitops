# ADR 0004: Host at bedoux-tech, start private, flip to public before the interview package

- Status: Accepted
- Date: 2026-07-18

Supersedes [ADR 0003](0003-repo-hosting-and-branch-discipline.md).

## Context

ADR 0003 chose a public repo from day one for portfolio value. At creation time the owner
chose to start private instead: the early phases are docs-heavy and exploratory, and
visibility is a one-click flip later. Everything else in ADR 0003 stands unchanged.

## Decision

- Host at **`bedoux-tech/bedoux-commerce-cloud`**, created **private**.
- The owner's personal account (`tsogtbatjargal`) is a collaborator with push access; local
  development pushes over SSH from the workstation.
- Flip to **public before P9** (interview package), preceded by a fresh secrets/history
  sweep (rerun T-003 against the full git history, not just the working tree).
- Branch discipline and commit convention carry over from ADR 0003 verbatim: direct-to-main
  until P6, then PR flow with branch protection; `<TaskID> complete: ...`, gate commits,
  `Fix ...` prefix.

## Consequences

- No public portfolio URL until the flip; acceptable since nothing is interview-ready yet.
- The no-secrets rule still applies at full strength — the history becomes public later, so
  nothing sensitive may enter it at any point.
- The pre-flip history sweep is a hard prerequisite; add it to the P9 checklist when P9 opens.
