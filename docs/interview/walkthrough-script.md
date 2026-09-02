# P9.1/P14.5 — 15-minute technical walkthrough script

Speaking notes for a technical tour of bedoux-commerce-cloud. P14.5 extends the original P9
walkthrough with measured P10–P14 security, reliability, TLS, delivery, performance, and cost
evidence; it does not replace the original application/platform story. Every claim below points
to a completed T-NNN gate, a named ADR, or evidence in `docs/PROGRESS.md`.

---

## 1. Problem and operating model (1 min 30 sec)

> I built bedoux-commerce-cloud to show that I can operate a real workload on EKS under a hard
> constraint: USD 20 per calendar month. The application is intentionally small—React, FastAPI,
> PostgreSQL, catalog and orders—because the portfolio is about the platform around it: identity,
> networking, delivery, reliability, incident response, and cost control.
>
> The operating model is as important as the architecture. Every milestone works locally first.
> AWS work happens only in an owner-approved, alarmed session with an exact scope and same-session
> teardown. Configuration does not count as proof: the project records the observed result, the
> failure path, and the final inventory. [Show the P10–P14 optimization-evidence diagram.] The
> post-P9 track deliberately revisited the system with measurements instead of adding product
> features: harden it, stress it, expose it through trusted TLS, prove progressive delivery, then
> use the evidence to right-size and account for cost.

## 2. Architecture, request path, and public entry (2 min 15 sec)

> [Show system-context, then request-path.] A browser reaches `bedoux.ca` or `www.bedoux.ca`
> through Route 53, an ACM certificate, and an internet-facing ALB. P12 proved trusted HTTPS and
> the HTTP 301 redirect in both `curl` and a real Chrome session. The ALB and DNS aliases are
> session-temporary; the explicitly approved hosted zone, certificate, and validation records
> persist. Teardown verified that distinction instead of leaving a dangling hostname.
>
> The runtime path contains a useful real-world correction. I originally expected ALB Ingress to
> route `/api` directly to FastAPI, like nginx Ingress does locally after a rewrite. AWS Load
> Balancer Controller has no equivalent path-rewrite annotation. ADR 0008 therefore sends public
> traffic to the web target; nginx serves React and proxies `/api/*` internally to the API Service
> while stripping the prefix. FastAPI is never a public ALB target in the stable path.
>
> PostgreSQL is the system of record. The cheapest baseline keeps it in-cluster; bounded P7
> sessions also proved Single-AZ RDS, Secrets Manager, and S3 product images through scoped IRSA.
> The frontend stays storage-neutral because the API returns either a static path or a presigned
> S3 URL. None of those temporary managed services is implied to be always running.

## 3. Security and identity boundaries (2 min 30 sec)

> [Show identity.] GitHub Actions uses OIDC, not repository access keys. The deploy role trusts
> only this repository's `main` workflow subject, verified against a live token in ADR 0009. Pull
> request jobs have no `id-token: write`, so they cannot mint AWS credentials. The deployment role
> has namespace-scoped EKS edit access; cluster-wide add-ons and storage stay operator-only.
>
> The strongest IAM lesson came from finding two self-escalation paths rather than assuming a
> `bedoux-*` naming condition was enough. First, the scoped policy could rewrite itself because its
> own name matched that pattern. ADR 0007 added an explicit deny. P10 then found the second hop: a
> delegated role could be created with broader permissions. ADR 0015 requires the reviewed
> permissions boundary and denies creating or modifying a role without it. The owner applied the
> policy change independently, and a bounded live test proved the forbidden path was denied.
>
> P10 also moved security into workload and supply-chain controls. Default-deny NetworkPolicies
> plus explicit web-to-API and API-to-PostgreSQL allows were first proven with Calico on kind, then
> repeated with EKS VPC CNI enforcement against an unauthorized pod. CI emits SPDX SBOMs and
> keylessly signs immutable images; deployment verifies the exact workflow identity and digest
> before Helm. Image rescans still disclose unfixed base-image CVEs rather than hiding them behind
> a passing scan.

## 4. Bounded scaling and failure tolerance (2 min 45 sec)

> [Show vpc-network and the optimization evidence.] Reliability is deliberately bounded so it
> cannot become an unbounded cost feature. The HPA target is 60 percent with `maxReplicas: 3`.
> T-1101 proved scale-out and scale-in locally; the live load run reached the ceiling with zero
> request failures. PDBs and soft topology spread complement an opt-in HA profile containing two
> AZ-pinned one-node Spot groups—exactly two workers, not an autoscaling fleet.
>
> The node-loss drill is the result I would emphasize. One worker was cordoned and drained during
> five minutes of traffic. Stateless workloads recovered in the surviving AZ, PostgreSQL was
> explicitly excluded from the HA claim, and 33,507/33,507 requests succeeded. Measured p95 was
> 155.35 ms against a two-second threshold. Earlier attempts had exposed two genuine design bugs:
> invalid topology-spread semantics and an ALB deregistration race. ADRs 0018 and 0019 record the
> corrections—soft failover placement, a measured deregistration bound, readiness gates, and a
> shutdown sequence that the final drill actually exercised.
>
> P14 widens the eligible pool from only `t3.medium` to same-shape `t3.medium` and `t3a.medium`
> while preserving one-node and two-node ceilings. EKS managed-node Capacity Rebalancing is best
> effort, not a guarantee. The ordinary workloads retain a 30-second grace period and no long
> preStop hook; the measured HA profile keeps its explicit exception. This is interruption-aware,
> not a claim of PostgreSQL high availability.

## 5. Delivery, rollback, and diagnosis (3 min 30 sec)

> [Show ci-cd.] Pull requests run API/PostgreSQL tests, web lint/test/build, Terraform and Helm
> validation, container scanning, SBOM generation, and ephemeral-key signature verification
> without AWS access.
> After an approved merge, the manually dispatched workflow obtains short-lived OIDC credentials,
> pushes commit-SHA images to ECR, signs and verifies their digests, and deploys with Helm atomic
> rollback. Branch protection is an honestly disclosed limitation: this private repository's plan
> cannot enforce a server-side ruleset, so ADR 0010 documents the clone-local pre-push control as a
> compensating guardrail, not as equivalent protection.
>
> P13 adds progressive delivery inside the same Helm release. The successful drill staged stable
> and canary API/web pairs behind an exact ALB 90/10 action, required both target groups healthy,
> sampled direct and public traffic, and correlated requests with canary logs. Only after the
> listener reconciled to 100/0 and stable readiness was true did cleanup remove the canary. That is
> stronger than checking Kubernetes rollout status while assuming the ALB caught up.
>
> The blocked-canary drill injected API 404s only into the canary nginx configuration, leaving the
> pods Ready so that the application health gate—not a startup probe—had to catch it. The gate
> attributed the observed errors, blocked promotion, reconciled back to stable 100/0, restored the
> exact stable images, removed every canary object, and passed final public health and catalog
> checks. A generic infrastructure failure cannot emit the T-1302 success marker.
>
> Earlier P8 drills remain the diagnosis foundation: unhealthy ALB target, failed pod, database
> connection loss, and failed Helm rollout were induced, diagnosed from tooling output, recovered,
> and torn down. One session overran while I diagnosed an Alembic percent-encoding bug; I recorded
> it, fixed it locally, and replaced intention with an enforced background alarm. The useful story
> is not that nothing failed—it is that each failure changed the system or runbook.

## 6. Measured cost and performance decisions (2 min 30 sec)

> [Return to the optimization-evidence diagram.] P14 closes the loop with measurements. During
> P11 load, the API used about 229m CPU—roughly 92 percent of its old 250m limit. I kept the 50m
> request so the HPA remains sensitive, raised only the API limit to 500m, and left memory, web,
> and PostgreSQL unchanged because no retained measurement justified changing them. The stable and
> canary renders are tested to inherit the same values.
>
> ECR exposed another evidence-versus-intent gap: images are tagged with a bare commit SHA, while
> the lifecycle policy looked for `sha-`, so it matched nothing. P14 changed the tagged selector to
> the documented wildcard, pushed real bare-SHA verification images, confirmed images beyond the
> newest ten were expiration candidates, and removed the temporary tags.
>
> The conservative P10–P13 calendar envelope cost USD 4.939738 in positive usage. Final August
> whole-account usage was USD 8.373571, or 41.9 percent of the USD 20 cap. EKS control planes were
> 48.8 percent of track usage and Route 53 was 20.3 percent, so short sessions and teardown matter
> more than shaving a few millicores. Credits offset the observed window, but the report evaluates
> positive usage because promotional credit is not sustainable architecture.
>
> The honest boundary remains: the learning profile is inexpensive and production-shaped, not
> production-sized. Multi-AZ databases, private nodes, more replicas, WAF, and durable monitoring
> would cost more. What transfers is the discipline—least privilege, exact artifacts, measured
> gates, automatic rollback, explicit trade-offs, and verified cleanup.

---

## Evidence map

| Topic | Proof to cite | Primary artifact |
|---|---|---|
| P10 security | T-1001–T-1005: scan, NetworkPolicy, signing/SBOM, IAM review, live deny | ADRs 0015–0016 and `docs/PROGRESS.md` |
| P11 reliability | T-1101–T-1104: bounded HPA, live load, zero-failure node loss, teardown | ADRs 0017–0019 and `docs/PROGRESS.md` |
| P12 public entry | T-1201–T-1203: issued certificate, HTTPS/301, deliberate persistence | ADR 0022 and `docs/PROGRESS.md` |
| P13 delivery | T-1301–T-1302: successful canary plus attributed block/rollback | ADR 0023 and `docs/PROGRESS.md` |
| P14 decisions | T-1401–T-1403: measured resources, live ECR expiry, actual cost | `docs/resource-right-sizing.md`, `docs/spot-diversification.md`, `docs/p10-p13-cost-report.md` |

## Timing verification

The original P9.3 script was measured at 1,332 spoken words and fit in 14:19 at a deliberately
slow 100 words per minute including 60 seconds of diagram and transition overhead. P14.5 retains
the same conservative method: count only blockquoted speaking notes, then add 60 seconds for seven
diagram references, five transitions, and opening/closing pauses.

| Version | Spoken words | 100 wpm + 60 sec | 130 wpm + 60 sec | 15-minute result |
|---|---:|---:|---:|---|
| P9.3 baseline (2026-08-07) | 1,332 | 14:19 | 11:15 | Pass |
| P14.5 extension (2026-09-02) | 1289 | 13:53 | 10:55 | Pass |

P14.5 per-section spoken-word counts are 140, 193, 212, 215, 293, and 236. The allocated section
times still total 15:00 and leave about 1:07 of whole-script margin at the deliberately slow pace.

`scripts/test-p14-interview-package.sh` enforces a maximum of 1,400 spoken words, verifies that
P10–P14 and their key measured outcomes remain in both the walkthrough and new diagram, and checks
the editable/exported diagram pair. `make docs-check` remains the final T-1404 gate.

Practical delivery notes:

- Pre-open all seven SVGs. Use `optimization-track.svg` as the P10–P14 spine, then switch to the
  detailed P9 diagrams only where the script calls for them.
- If time is shortened, keep the P13 blocked-canary result, P11 zero-failure node drain, and P14
  cost result; offer IAM, NetworkPolicy, and teardown details as follow-up depth.
- If asked what is not production-ready, answer directly: PostgreSQL HA, private-node egress,
  durable observability, and server-enforced branch protection remain outside this learning cap.
