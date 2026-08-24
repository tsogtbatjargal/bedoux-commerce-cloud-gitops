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

Current state as of 2026-08-24:
- P0-P11 are complete and gate-approved. P12 is active; P12.1 is the single active item on branch
  `p12-1-route53-acm`. Draft PR #50 still points at the prior `.com` design until this local
  correction is published. P12.2 and P12.3 have not started.
- Main was clean at merged commit `648b4f3` when this focused branch was created.
- The owner corrected the target to the `bedoux.ca` apex and retired Shopify because of its
  recurring cost. Accepted ADR 0022 supersedes ADR 0021 and records the owned-domain path
  required by ADR 0014.
- The local implementation adds a disabled-by-default `route53-acm` Terraform module, exact
  `bedoux.ca` + `www.bedoux.ca` profile, root outputs, CI profile validation, and
  `docs/runbooks/p12-1-domain-tls-session.md`.
- The module deliberately excludes registration, registrar settings, and Shopify cancellation.
  It stages the live work: apex hosted zone first, registrar nameserver replacement second, then
  the certificate after public Route 53 delegation is verified. ACM validation is capped at 45
  minutes; the runbook reserves a three-hour alarmed session.
- Terraform formatting and credential-free validation pass for the default, P11, and corrected
  P12 profiles; `make docs-check` and `git diff --check` pass. The previous GitHub run
  `32680010700` covered the now-superseded `cloud.bedoux.com` head, so a fresh PR run is still
  required before live work. No AWS or Kubernetes endpoint was contacted.
- T-1201 is not complete. Public DNS currently has non-Route 53 authoritative nameservers and
  Shopify-directed apex/`www` records. The owner intentionally retires those records during the
  apex cutover. P12.1 then has an accepted temporary no-site window until P12.2 creates the ALB
  and Route 53 aliases.
- No temporary AWS resources are live. Persistent allowlist remains the state bucket/history, two
  ECR repositories, six IAM roles/policies, and GitHub OIDC provider.

Next action:
1. Validate and publish the `bedoux.ca` correction to draft PR #50, then review its fresh checks;
   do not claim P12.1 complete from CI alone.
2. Before opening a live session, owner confirms registrar nameserver access, the Shopify
   retirement, and approval to retain the USD 0.50/month Route 53 apex zone.
3. Only then schedule the three-hour independent alarm and follow
   `docs/runbooks/p12-1-domain-tls-session.md`. T-1201 requires ACM status `ISSUED`.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No live DNS
or ACM mutation is authorized from this checkpoint.
```
