# Handoff

Paste the fenced block into a fresh Claude Code, Codex, OpenClaw, or human-operator session.
`docs/PROGRESS.md` remains authoritative if this summary ever disagrees with it.

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/bedoux-commerce-cloud.

Read AGENTS.md and START-HERE.md first, then read the overall status and newest session entry in
docs/PROGRESS.md. Preserve unrelated changes and never push main directly.

Current state:
- P0–P14 and T-001–T-1404 are complete and gate-approved.
- PR #66 merged the final P14 reconciliation and standalone owner gate commit to main as
  9a2fe597f79018a68bfbe53580acebf8d91b0248.
- The owner-approved post-P14 maintenance track (M1-M5, explicitly not P15) is also complete:
  M1 Helm render validation (521f3a3), M2 shared canary pod spec / ADR 0024 (83b2eaa), M3 named
  deployment profiles (ff81bfc), M4 typed P12/P13 gate diagnostics (38cadaf), M5 lazy app.db
  engine + isolated order pricing (4e63213), plus docs/verification-lessons.md (950775b). Final
  merge: 40bb39d.
- Post-track housekeeping H1-H4 are complete. H2 exposes the merged M1-M5 local verification
  commands consistently in START-HERE.md and this handoff. H3 removed the merged maintenance
  branches/worktrees. H4 refreshed the current API image scan: zero fixable HIGH/CRITICAL
  findings, 54 unfixed package records representing 18 unique CVEs; its checkpoint awaits
  review/publication. H5 remains inactive.
- The owner closed the P10–P14 optimization track and, separately, the M1-M5 maintenance track,
  without activating P15 or another unplanned phase.
- No temporary or hourly billed AWS resource is live. Only the approved persistent ECR/IAM,
  Route 53/ACM, and Terraform state-storage allowlist remains; website aliases are absent.
- The retained Calico-backed kind node is stopped with its PVC preserved. The host inotify value
  is 128. A default kubeconfig may point to a deleted EKS endpoint; use an explicit context.

Resume checks:
1. Run git status --short and git log --oneline -5.
2. Run toolbox run -c bedoux-aws /usr/bin/make docs-check.
3. Run the maintenance checks that match the area being resumed:
   - M1/M2: toolbox run -c bedoux-aws /usr/bin/make helm-test
   - M3: python3 scripts/test_deploy_profile.py
   - M4: python3 scripts/test_gate_checks.py
   - M5: (cd apps/api && python3 -m pytest -q tests/test_pricing.py
     tests/test_database_credentials.py) with apps/api's .[dev] dependencies installed.
4. These are local checks. Do not contact AWS/Kubernetes merely to reconfirm completed work.
5. If future AWS work is explicitly approved, open docs/runbooks/aws-session.md first and obey its
   identity, cost, deadline, teardown, and evidence gates.

Next action:
- Review/publish H4's focused vulnerability-evidence refresh. H5 requires separate continuation
  in sequence. Do not infer a P15, or an M6+ continuation of the closed M1-M5 track, from the
  historical plan or logs.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; standard project tags; no NAT
Gateway without a reviewed exception; same-day teardown; never record secrets, account IDs,
personal email addresses, or raw identity output.
```
