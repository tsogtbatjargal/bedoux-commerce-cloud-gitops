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

Current state as of 2026-08-26:
- P0-P12 are complete and gate-approved. The owner explicitly approved the P12 gate on
  2026-08-26 and activated P13. P13.1 is next but remains `NOT STARTED`.
- ADR 0022 supersedes ADR 0021: the owner retired Shopify, selected the `bedoux.ca` apex plus
  `www`, and explicitly approved hosted-zone/certificate persistence.
- PR #53 passed all four jobs in final run `33006117123` and merged the P12.2 HTTPS/redirect,
  certificate-discovery, staged-alias, proof-helper, and guarded-session path to `main` as
  `775dfe1`.
- T-1201 remains proven: the public Route 53 zone is delegated and the Amazon-issued certificate
  is `ISSUED` for exactly `bedoux.ca` and `www.bedoux.ca`, with two DNS validation records.
- T-1202 passed in bounded workflow run `33013651632`: signed immutable images deployed through
  the HTTPS ALB; system, Cloudflare, Google, and Quad9 resolved both aliases; the fail-closed
  helper proved trusted HTTPS and HTTP 301 redirects for both names; real Google Chrome loaded
  the apex without a certificate warning and rendered the seeded catalog.
- T-1203 passed: exact approved plans removed the apex/`www` aliases before deleting the Ingress,
  ALB, application, controller, EKS, cluster OIDC provider, and no-NAT VPC. The 18:56 Edmonton
  sweep returned zero temporary compute, network, storage, database, load-balancing, alias, and
  cluster-OIDC resources.
- The persistent allowlist is exactly one protected/versioned state bucket, two ECR repositories,
  six persistent IAM roles, GitHub OIDC provider, and the delegated `bedoux.ca` zone with issued
  certificate/validation records. The zone has no website `A` aliases and the certificate is not
  attached to deleted infrastructure. Budget actual was USD 5.384 of USD 20.
- All exact `/tmp/bedoux*` session files are removed. Persistent resources are intentionally
  detached from session Terraform state; any future AWS session must run the guarded persistent
  import first. No AWS call ran after the clean closeout sweep.
- Local branch `docs/p12-2-merge-checkpoint` contains separate PR #53 merge, P12 completion, and
  P12-gate commits. Preserve these changes and use a focused PR; never push `main`.

Next action:
1. With explicit publication authorization, push the focused checkpoint branch, open/review its
   PR, and merge it. Then begin P13.1 locally by reviewing the merged deploy workflow/chart and
   defining the staged rollout plus automated health-gate boundary. P13.2 remains gated.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No AWS session
is open; initial P13.1 design is local-only.
```
