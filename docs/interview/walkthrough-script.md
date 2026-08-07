# P9.1 — 15-minute technical walkthrough script

Speaking notes for a timed technical tour of bedoux-commerce-cloud. Six sections, 15 minutes
total, timed to the allocation in `docs/IMPLEMENTATION-PLAN.md`'s P9 goal. Every claim below cites
real evidence already recorded in `docs/PROGRESS.md`'s session log or a named ADR — nothing here
describes hypothetical capability. P9.3 times this against a clock and trims to fit; this draft
runs slightly long on purpose so trimming has somewhere to come from.

---

## 1. The problem (1 min)

> I built bedoux-commerce-cloud to prove I can run a real workload on EKS the way a small team
> actually would, under a hard constraint: USD 20 a month. That budget forced almost every
> architectural decision — no NAT Gateway, one Spot node, same-day teardown as the default, and a
> strict "prove it locally first, then in AWS" discipline. It's a small commerce app — catalog,
> cart, orders — but the app itself was never the point. The point was the platform work around
> it: identity boundaries, CI/CD, observability, and — the part most portfolios skip —
> real incident response, including my own mistakes and how I recovered from them.

## 2. Architecture and request path (3 min)

> The stack is deliberately small: React/Vite frontend, FastAPI backend, PostgreSQL. [Show the
> system-context diagram.] A request comes in through an internet-facing ALB, hits the frontend
> pod, and — this is a real finding, not a design I planned from day one — the frontend's own
> nginx proxies `/api/*` internally to the API Service. I originally expected the ALB to route
> `/api` directly to the API target group, the way kind's nginx Ingress does after a rewrite. AWS
> ALB Ingress has no path-rewrite annotation at all, so that shape doesn't exist on this ingress
> controller. ADR 0008 documents the fix: route everything through the frontend and let its
> already-built nginx reverse proxy — which existed for Compose since Phase 2 and was just
> sitting dormant in Kubernetes — do the prefix-stripping instead. That's the theme of this whole
> project: real infrastructure surfaces real constraints that a diagram drawn in advance won't
> show you.
>
> Data-wise, PostgreSQL is the system of record; product images are either bundled static assets
> or, in the S3 profile (ADR 0011), served through API-generated presigned URLs from a
> ServiceAccount-scoped IRSA role — never a public bucket, never an image proxy.

## 3. Kubernetes and AWS responsibilities (3 min)

> The split is deliberate and IAM-enforced, not just documented. EKS runs the workload: one Spot
> `t3.medium` node, Helm-managed Deployments, a `gp3` StorageClass through the EBS CSI driver.
> AWS supplies everything stateful and everything identity-related: RDS for the database,
> Secrets Manager for credentials, IAM/IRSA for every workload identity.
>
> The IAM boundary is the part I'd talk longest about if asked, because I found and closed a real
> self-escalation hole in it. `bedoux-admin`'s scoped policy allowed `iam:*Policy*` on any
> `bedoux-*`-named resource — which included the policy's own ARN, since the policy is itself
> named `bedoux-iam-scoped`. That meant the constrained identity could rewrite its own
> constraining policy: a real path to full account admin, not a theoretical one. ADR 0007 is the
> fix — an explicit Deny scoped to exactly that one policy ARN — and I deliberately had the owner
> apply it via console/root rather than through `bedoux-admin`'s own API access, so fixing the
> hole never exercised the hole itself.
>
> On the Kubernetes side, EKS access entries scope exactly who can do what: the GitHub Actions
> deployment role gets `AmazonEKSEditPolicy` in the `bedoux` namespace only — not cluster-admin —
> so a compromised CI run can't touch cluster-wide resources like the StorageClass or the ALB
> controller. Those stay operator-only steps for exactly that reason.

## 4. CI/CD and identity (3 min)

> GitHub Actions authenticates via OIDC, not long-lived keys — the trust policy is bound to
> `bedoux-tech/bedoux-commerce-cloud`'s `main` branch and, as a real finding, to this specific
> repo's actual GitHub-emitted subject claim format, which I verified against a live token rather
> than assuming the documented default (ADR 0009). PR-triggered workflows get zero AWS
> credentials — `id-token: write` only exists on the manually-dispatched deploy workflow, so a
> pull request literally cannot mint AWS access no matter what it changes.
>
> The pipeline: PR validation runs API/Postgres tests, web lint/test/build, Terraform/Helm
> validation, and a Trivy container scan on every PR. The deploy workflow builds commit-SHA-tagged
> immutable images, pushes to ECR, and deploys via `helm upgrade --install --atomic`. That
> `--atomic` flag isn't decorative — I proved it live in P8.3: I deployed a build with a
> deliberately nonexistent image tag, watched the new pod hit `ImagePullBackOff` while the
> previous release kept serving with zero downtime, and watched Helm's own timeout trigger an
> automatic rollback with no manual intervention. `helm history` shows the exact sequence: revision
> 2 `failed`, revision 3 `Rollback to 1`, `deployed`.
>
> Branch protection on `main` is a real, disclosed limitation: this repo's GitHub plan can't
> enforce server-side rulesets while private, so ADR 0010 documents a local pre-push guardrail as
> an honest compensating control — I'm explicit in the docs that it protects this one clone, not
> other clones or the GitHub web UI, rather than overstating what it does.

## 5. Observability and troubleshooting (3 min)

> The API emits one structured JSON completion event per request to stdout — timestamp, request
> ID, method, path, status, duration — deliberately excluding bodies, headers, and credentials.
> EKS's CloudWatch Observability add-on forwards that to a temporary Container Insights log group
> through an IRSA role scoped to exactly the CloudWatch agent's ServiceAccount. A dashboard derives
> 5xx rate from two metric filters and shows ALB unhealthy-target and RDS CPU alongside pod
> restarts. All of it — log groups, dashboard, alarms — is session-temporary, three-day retention,
> torn down same-day; there's no always-on observability cost.
>
> P8.3 is where I'd spend the most time here, because it's real incident practice, not staged
> demo content. Four drills, each induced, then diagnosed using only `kubectl`/`aws` CLI output —
> no prior knowledge assumed:
> - **Unhealthy ALB target**: scaled the frontend to zero, watched the ALB target go `draining`
>   via `describe-target-health`, confirmed the public `503`, then fixed and confirmed recovery.
> - **Failed pod**: broke the API container's startup command, diagnosed purely from
>   `kubectl logs` showing the exact injected error, fixed via `rollout undo`.
> - **DB connection error**: revoked the RDS security group's own ingress rule — the pod stuck at
>   `Init` phase with no log output by design, so I proved the cause two independent ways: a debug
>   pod's `pg_isready` timeout, and the security group's rule list coming back empty.
> - **Failed rollout**: covered above under CI/CD — Helm's atomic rollback.
>
> I'd also be honest here about a real mistake: an earlier P8.3 attempt hit a genuine
> previously-undiscovered bug — Alembic's config parser choking on a `%`-encoded character in a
> generated password — and while I was root-causing it, I lost track of the session clock and
> overran the planned teardown by about three hours. I recorded that plainly in the project log
> instead of hiding it, fixed the root cause, proved the fix with both a unit test and a real local
> migration run, and on the next attempt armed an actual enforced background alarm instead of just
> intending to watch the clock. That session finished under budget. I'd rather show that than
> pretend nothing ever went wrong — the discipline is in how a mistake gets caught and closed out,
> not in never making one.

## 6. Cost and reliability trade-offs (2 min)

> Every reliability shortcut here is a named, deliberate decision, not an oversight. One Spot
> node and one replica per service — ADR 0006 accepts Spot interruption risk explicitly in
> exchange for real cost savings, while still proving the storage/IAM setup (a genuine `gp3` PVC
> through EBS CSI) that would carry over to a properly multi-node production profile. No NAT
> Gateway — nodes sit in public subnets with `publicly_accessible=false` on RDS and
> security-group-only access, which was itself a real P5.5 finding: eksctl silently defaults to
> creating a NAT Gateway, and I only caught it because the teardown sweep's tag-based inventory
> flagged it, not because I'd anticipated it. Same-day teardown, independently alarmed, is the
> default for every session — not a nice-to-have, a hard rule with a background timer enforcing it
> after the first time I broke it.
>
> The honest trade-off: this profile trades availability for cost on purpose. Single-AZ RDS, one
> node, no autoscaling — none of that is production-grade, and the docs say so explicitly
> (`docs/architecture.md`'s MVP-vs-production table). What *is* production-shaped is everything
> around it: the IAM boundaries, the OIDC trust, the atomic-rollback CI/CD, and the drill practice
> — because those are the things that don't change much between a $20/month learning cluster and
> a real production account. The infrastructure gets bigger; the discipline doesn't change.

---

## Timing notes (for P9.3)

- Target: 15:00. This draft reads at roughly 15:30–16:00 aloud — trim section 5 (observability/
  troubleshooting) first, since it has the most material to cut without losing the point.
- Have the system-context and learning-path diagrams (P9.2) visible/ready before section 2.
- If asked to go deeper on any one area, the natural extension points are: the IAM
  self-escalation finding (ADR 0007) for identity questions, the P8.3 drills for
  troubleshooting/SRE questions, and the two deadline-overrun incidents for questions about
  working under pressure or operational discipline.
