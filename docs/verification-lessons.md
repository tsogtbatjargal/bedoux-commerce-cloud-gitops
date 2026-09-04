# Verification lessons

Concrete failures this repository actually hit, why each one happened, and the rule that came
out of it. Every entry is traceable to a commit, a PR, or a CI log — nothing here is generic
advice.

Written during the post-P14 maintenance track (M1–M2). Ordered by how much trouble each one
caused.

---

## 1. An assertion that cannot run locally will eventually be certified as passing

**What happened.** P14.1 (`7c2676a`) added a CI assertion that the canary Deployment inherits the
stable API's resource block. It extracted the canary pod spec with:

```bash
sed -n '/        - name: api-canary/,/        - name: web-canary/p'
```

In the rendered manifests, `api-canary` is the **Deployment's `metadata.name`**, at two-space
indent. The **container** inside it is named `api`, at eight-space indent. The range matched
nothing, `canary_resources` was always empty, and `test "0" -eq 1` failed — aborting the whole
`set -euo pipefail` step.

It had never run anywhere. No `Makefile` target executed the workflow's embedded shell, and the
branch was unpushed, so GitHub Actions had never seen it. `docs/PROGRESS.md` recorded "stable and
canary P14.1 assertions passed." That claim was false, and only an independent review caught it.

**Why.** The assertion lived as a line of shell inside a YAML string. There was no way to run it
without opening a pull request, so nobody did.

**Rule.** *CI must invoke the same command a human can run.* M1 moved the render contracts into
`scripts/test_helm_render.py` behind `make helm-test`; the workflow step is now one line that
calls it. If a check cannot be run locally, treat its "passing" status as unverified.

**Corollary.** In rendered Kubernetes YAML, resource names and container names are different
namespaces at different indent levels. Locate objects structurally — by `kind` plus
`metadata.name` — never by guessing at indented text.

---

## 2. A test that has never failed is not known to work

**What happened.** Twice.

- The P14.1 fix added a negative fixture: deliberately diverge the canary, prove the assertion
  rejects it. Correct instinct — but the reviewer did not take the script's own exit code as
  proof, and instead rebuilt the divergent fixture by hand to confirm the rendered values really
  changed. They did.
- In M2, two of the first-draft fixtures written for the new contracts were themselves vacuous
  (see §3). They were caught before commit only because each fixture is required to *fail*.

**Why.** A positive assertion tells you the current state satisfies it. It says nothing about
whether the assertion would notice if the state changed. Those are different properties and only
one of them is what a test is for.

**Rule.** *Every contract carries a fixture that breaks it.* `scripts/test_helm_render.py` runs a
fail-sensitivity pass: copy the chart, mutate one template, and require the named contract to
raise. A contract with no fixture, or whose fixture still passes, is a contract that has not been
tested.

---

## 3. Once two things share a module, breaking that module proves nothing

**What happened.** M2 collapsed the stable and canary pod specs into shared `_helpers.tpl`
partials. The first-draft fixture for `stable-and-canary-pod-specs-stay-equivalent` changed a
probe value in the shared helper:

```
initialDelaySeconds: 3   ->   initialDelaySeconds: 4
```

Both sides render from that helper, so both changed identically, the two pod specs stayed
equivalent, and the contract correctly did **not** fire. The fixture "passed" while testing
nothing.

The same trap hit `scripts/test-p14-resource-right-sizing.sh`, whose negative fixture edited
`canary.yaml` directly. After M2 that text lived in the shared helper, and a symmetric edit there
no longer diverged the two sides. The script failed outright — which is how it was found.

**Why.** Deduplication changes what a mutation means. Before the refactor, editing `canary.yaml`
affected one side. After, editing the helper affects both.

**Rule.** *A fixture for an equivalence contract must be asymmetric.* Both now branch on the
parameter that distinguishes the callers:

```gotmpl
{{- if and $api.topologySpread.enabled (eq .app "api") }}
{{- toYaml (ternary $api.resources $ctx.Values.web.resources (eq .app "api")) | nindent 6 }}
```

**Corollary.** Refactoring invalidates fixtures. Any test that anchors on template or source text
must be re-verified whenever that text moves — and it will move.

---

## 4. Copy-paste manufactures decisions nobody made

**What happened.** `canary.yaml` was created by copying `api.yaml` and `web.yaml` and changing the
image source. Of its 73-line API pod spec, three lines genuinely differed. The copy silently
dropped the `topologySpreadConstraints` block.

Result: on the HA profile, `api` and `web` spread across availability zones and `api-canary` /
`web-canary` did not. Reproducible in one command:

```
$ helm template bedoux charts/bedoux -f values-aws.yaml -f values-aws-ha.yaml \
    --set canary.enabled=true | grep topologySpreadConstraints
  HAS SPREAD: api
  HAS SPREAD: web
  (api-canary, web-canary — absent)
```

No ADR mentioned it. No test covered it. It was found only by rendering the profile during an
architecture audit.

**Why.** Duplication makes omissions invisible. A missing block in a copied file looks exactly
like a deliberate difference, and neither the author nor a reviewer can tell them apart later.

**Rule.** *Share the thing, parameterise the difference.* ADR 0024 replaced both copies with
`bedoux.apiPodSpec` / `bedoux.webPodSpec`. What varies is an explicit argument; what does not is
shared by construction and cannot silently diverge.

**The honest part.** ADR 0024 also records that inheriting the spread is **a no-op at
`canary.replicas: 1`** — the selector matches only that Deployment's own pods, so a single pod has
nothing to balance against. It was adopted so the gap cannot reopen if replicas are ever raised,
not for a runtime effect it does not have. Recording a change as more valuable than it is costs
more credibility than the change is worth.

---

## 5. "Not yet" and "broken" must not share an exit code

**What happened.** `scripts/p13-alb-reconciliation-gate.sh` evaluates ALB state with 17 inline
`python -c` programs, every one ending `2>/dev/null || return 1`. Inside a polling loop with a
300-second deadline, that means a Python syntax error, a missing JSON key, an unexpected AWS
response shape, and a genuinely unreconciled load balancer are **all the same signal**. A broken
assertion is indistinguishable from a slow ALB, and the operator waits out the full deadline
before seeing a timeout that explains nothing.

Two pairs of those snippets are also byte-identical within the same file.

**Why.** Suppressing stderr is convenient when a non-zero exit is the expected control flow. It
also destroys the only channel that distinguishes the two meanings.

**Rule.** *Separate the channels.* `scripts/test_helm_render.py` raises `ContractError` ("the
chart is wrong", exit 1) and `HarnessError` ("I could not evaluate this", exit 2). This earned its
keep immediately: during M2, three fixtures still pointed at template text the refactor had moved,
and the run exited **2 with a named stale-anchor message** instead of reporting a chart failure.

Generalising this to the ALB gates is maintenance item M4.

---

## 6. Prove a "no behaviour change" refactor with golden output

**What happened.** M2 rewrote four templates and claimed to change nothing except the canary
spread blocks. Reading the diff cannot establish that — Helm partial indentation is fiddly and a
one-space error renders as valid but different YAML.

**What we did instead.** Render all 13 profiles from the pre-refactor commit, render them again
after, and diff:

| Result | Profiles |
|---|---|
| Byte-identical | 10 |
| Comments only | `aws-canary`, `aws-canary-regression` |
| Intended change | `aws-ha-canary` — spread on both canary Deployments |

**14 non-comment changed lines across every profile**, all of them the two intended seven-line
blocks.

**Rule.** *When the claim is "output is unchanged", compare the output.* A golden-render
comparison is cheap, needs no new test infrastructure, and is the only evidence that actually
matches the claim being made.

---

## 7. A green check is not evidence the check ran

**What happened.** M1 changed how the Helm job executes its assertions. A passing job would look
identical whether the new module ran all 16 contracts or silently ran none.

**What we did.** Read the CI log and confirmed the contract names and the summary line
(`OK — 16 render contracts and 5 negative fixtures passed`) were actually printed. Same again for
M2's 17 contracts.

**Rule.** *After changing how tests are invoked, read the log once.* Green means the step exited
zero. It does not mean the step did what you think.

---

## 8. Verify a patch landed in full

**What happened.** The M1 patch arrived half-applied: 107 assertion lines had been removed from
`pr-validation.yml` and the `Makefile` already called `scripts/test_helm_render.py` — but that file
was never created. `make helm-test` and the CI job would both have failed immediately.

**Why.** A multi-file change that deletes in one file and adds in another is only coherent when
every part lands. Deletions apply cleanly on their own; the new file is what goes missing.

**Rule.** *Run the entry point before believing a patch is complete.* `git status` showed no
untracked files, which was the tell — a patch that adds a module and shows nothing new has not
finished. CI would also have caught this, which is an argument for pushing early rather than
reviewing prose about what a patch supposedly does.

---

---

## 9. A number retyped from output you have already seen is not verified

**What happened.** M2's golden-render comparison printed a per-profile result list. Writing it up,
the count of byte-identical profiles was reported as **nine**. It was **ten** — `aws-cleanup` sets
`canary.enabled=false`, is unchanged, and sits in the output between the two changed canary
entries, which is exactly where an eye skips.

The wrong figure reached four places before anyone noticed: the commit message of `d9fde03`, ADR
0024, the `docs/PROGRESS.md` session log, and the golden-render table in this document. It was
caught by the reviewer of PR #70, who re-rendered all 13 profiles independently instead of
trusting the reported number.

**Why.** The script counted correctly and printed the evidence. The error was introduced by a
human summarising machine output into prose — a step with no check on it. Every *load-bearing*
claim was exact (14 non-comment changed lines, all of them the two intended blocks); the incorrect
number was the incidental one, which is precisely why it survived several readings.

**Rule.** *If a number appears in a commit message, an ADR, or a progress log, have the tooling
emit it.* Print `len(identical)`; do not count a list by eye and retype the total. Where that is
impractical, treat summary figures as unverified until someone re-derives them — which is what the
reviewer did.

**Corollary — some records are immutable.** ADR 0024 and `docs/PROGRESS.md` were corrected with an
explicit note saying what they previously said and why it changed, following the P14.1 precedent
of correcting the record visibly rather than quietly. The commit message of `d9fde03` cannot be
changed and still reads "nine"; the ADR's correction section says so, so the discrepancy is
explained rather than left to confuse the next reader. Prefer putting derived figures where they
can be corrected.

## What these have in common

Every failure above is the same shape: **something was believed to be verified when the
verification could not have detected the problem.** The broken `sed`, the vacuous fixtures, the
symmetric mutation, the suppressed stderr, the unread green check, the half-applied patch, the
hand-counted total — none were logic errors in the system under test. They were gaps between what a check appeared to prove
and what it actually proved.

The practices that close that gap, in order of leverage:

1. Make every check runnable locally, and have CI call that same command.
2. Require each contract to have a fixture that makes it fail.
3. Keep "wrong" and "unevaluable" on separate exit codes.
4. Compare golden output when claiming behaviour is unchanged.
5. Read the log once after changing how tests are invoked.
6. Have the tooling emit any number you are going to write down.

## References

| Lesson | Evidence |
|---|---|
| §1 broken anchor | `7c2676a`, corrected in `3538989`; M1 in PR #69 (`521f3a3`) |
| §2 fail sensitivity | `scripts/test_helm_render.py` — `FIXTURES`, `check_fail_sensitivity` |
| §3 asymmetric fixtures | M2 in PR #70; `scripts/test-p14-resource-right-sizing.sh` |
| §4 canary divergence | `docs/decisions/0024-shared-pod-spec-and-canary-topology-spread.md` |
| §5 error channels | `scripts/p13-alb-reconciliation-gate.sh`; maintenance item M4 |
| §6 golden render | M2 session log entry, `docs/PROGRESS.md` |
| §7 reading CI logs | PR #69 and #70 "Terraform and Helm validation" job logs |
| §9 hand-counted total | PR #70 post-merge review; correction note in ADR 0024 |
