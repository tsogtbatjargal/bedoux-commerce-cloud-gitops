# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/worktrees/bedoux-commerce-cloud/raspy-lantern/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git; preserve unrelated changes.

Current state as of 2026-08-23:
- P0-P11 are complete and gate-approved. P12 is active; P12.1 is the single active item on branch
  `p12-1-route53-acm` in green draft PR #50. P12.2 and P12.3 have not started.
- Main was clean at merged commit `648b4f3` when this focused branch was created.
- The owner selected the new apex domain `bedoux.com`; accepted ADR 0020 records the new-domain
  path required by ADR 0014. Website implementation has not started.
- The local implementation adds a disabled-by-default `route53-acm` Terraform module, exact
  `bedoux.com` + `www.bedoux.com` profile, root outputs, CI profile validation, and
  `docs/runbooks/p12-1-domain-tls-session.md`.
- The module deliberately excludes domain registration. It stages the live work: hosted zone
  first, then certificate after public registrar delegation is verified. ACM validation is capped
  at 45 minutes; the runbook reserves a three-hour alarmed session.
- Terraform formatting and credential-free validation pass for default, P11, and P12 profiles;
  `make docs-check` and `git diff --check` pass. GitHub run `32678920103` passed all four PR jobs.
  No AWS or Kubernetes endpoint was contacted.
- T-1201 is not complete. Public DNS currently has a non-Route 53 delegation and Shopify-directed
  apex/`www` records. Do not replace it until the owner confirms control and replacement permission.
- No temporary AWS resources are live. Persistent allowlist remains the state bucket/history, two
  ECR repositories, six IAM roles/policies, and GitHub OIDC provider.

Next action:
1. Review green draft PR #50; do not claim P12.1 complete from CI alone.
2. Before opening a live session, owner confirms: control of `bedoux.com`; permission to replace
   its current Shopify-directed DNS; and approval to retain the USD 0.50/month Route 53 zone.
3. Only then schedule the three-hour independent alarm and follow
   `docs/runbooks/p12-1-domain-tls-session.md`. T-1201 requires ACM status `ISSUED`.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No live DNS
or ACM mutation is authorized from this checkpoint.
```
