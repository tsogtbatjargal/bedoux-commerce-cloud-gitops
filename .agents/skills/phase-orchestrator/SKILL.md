---
name: phase-orchestrator
description: Resume and coordinate this repository's gated phase workflow from its authoritative checkpoint. Use for catch-up, selecting or continuing the active checklist item, verifying evidence, updating progress or handoff state, closing out a session, or deciding whether a phase gate permits the next task. Do not use it to bypass owner approval or run a later phase early.
---

# Phase Orchestrator

Resolve the repository root, then read `AGENTS.md` and `START-HERE.md` completely.

Follow `docs/workflows/phase-orchestration.md` as the canonical procedure. Read
`docs/PROGRESS.md` as the only authoritative execution state, then load only the active phase
section and documents it references.

Keep exactly one checklist item active. Reconcile conflicting filesystem, GitHub, or live-system
state in the progress log before proceeding. Never infer a merge, completion, owner approval, or
phase transition.

When delegation is explicitly permitted, use the bounded-subtask rules in the canonical workflow
so smaller agents can save context without owning phase state or completion decisions.
