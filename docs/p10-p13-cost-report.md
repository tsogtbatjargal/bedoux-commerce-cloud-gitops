# P10–P13 cost report

## Result

The conservative P10–P13 calendar envelope accumulated **USD 4.939738** in positive AWS usage
charges from August 9 through September 1, 2026. The work crossed a calendar-month boundary, so
that total is useful as a track measure but is not compared to a single monthly cap for
compliance.

The USD 20 calendar-month guardrail held:

| Billing period | Whole-account usage (USD) | P10–P13 window usage (USD) | Monthly cap (USD) | Cap use | Evidence state |
|---|---:|---:|---:|---:|---|
| 2026-08 | 8.373571 | 4.437893 | 20.000000 | 41.9% | Final |
| 2026-09 through Sep 1 | 0.501845 | 0.501845 | 20.000000 | 2.5% | Estimated |

August retained USD 11.626429 of whole-account headroom. At the read-only refresh on
2026-09-02T09:18:36-06:00, AWS Budgets reported September actual USD 0.502 and forecast USD
4.185, or 20.9% of the cap. Billing ingestion is delayed, so the September row and forecast are
snapshots rather than final invoice values.

## Phase-window attribution

The phase windows are contiguous and non-overlapping. Cost Explorer's start date is inclusive
and end date is exclusive; each amount below sums daily `UnblendedCost` entries filtered to the
positive `Usage` record type.

| Phase | Inclusive calendar dates | Usage (USD) | Share of P10–P13 usage |
|---|---|---:|---:|
| P10 | 2026-08-09–2026-08-11 | 0.182644 | 3.7% |
| P11 | 2026-08-12–2026-08-20 | 0.732013 | 14.8% |
| P12 | 2026-08-21–2026-08-26 | 1.049246 | 21.2% |
| P13 | 2026-08-27–2026-09-01 | 2.975835 | 60.2% |

These are calendar-window attributions, not resource-level chargeback. They include approved
persistent-resource charges incurred during each window, even on days without a live cluster.
That is conservative for the monthly cap and avoids inventing precision that the retained tags
and historical snapshots cannot support. Daily granularity also cannot split transition days:
P13 owns September 1 because T-1302 closed that day, but the estimated row can include later
P14.2 ECR verification and persistent-resource usage from the same date. The phase rows are
therefore operational attribution, not invoice-grade accounting.

## Cost drivers

| Service group | Usage (USD) | Share |
|---|---:|---:|
| EKS control planes | 2.411791 | 48.8% |
| Route 53 | 1.002067 | 20.3% |
| EC2 Spot compute | 0.511206 | 10.3% |
| Application Load Balancers | 0.471604 | 9.5% |
| VPC | 0.295436 | 6.0% |
| Other | 0.247634 | 5.0% |

The result supports the existing operating model: short EKS sessions and same-day teardown
matter more than micro-optimizing the application pods. Route 53 was charged in both calendar
months because the owner-approved hosted zone persists. ECR lifecycle enforcement and the
bounded Spot pool address smaller recurring and compute costs without weakening the node-count
ceiling. No NAT Gateway was used in P10–P13.

## Credits and limitations

Cost Explorer also returned USD 4.939738 of credits against this window, so the credit-adjusted
net rounds to USD 0.000 before any later tax or currency treatment. This report deliberately
uses positive usage charges for the cap comparison: promotional credits are temporary and must
not make the infrastructure appear sustainably free.

The August 31 budget snapshot retained in `docs/PROGRESS.md` was USD 7.632, while finalized
August Cost Explorer usage is USD 8.373571. That difference is expected from billing ingestion
delay and is why session estimates and budget alerts remain controls, not real-time meters.
September data was still marked estimated during this refresh.

## Reproduction and controls

The refresh used the pinned `bedoux-admin` profile and `ca-central-1`. Identity validation
returned only a boolean confirming the expected non-root IAM user; no account identifier or raw
ARN was retained. The only AWS operations were read-only STS, Budgets, and Cost Explorer calls.

The Cost Explorer query shape was:

```text
aws ce get-cost-and-usage \
  --profile bedoux-admin \
  --time-period Start=<inclusive>,End=<exclusive> \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}'
```

`scripts/test-p14-cost-report.sh` independently sums both report tables, checks all monthly
amounts against the USD 20 cap, and proves the check rejects a deliberately inflated phase
fixture. The source semantics are documented by AWS's
[GetCostAndUsage API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_GetCostAndUsage.html),
and AWS documents the update delay in
[AWS Budgets best practices](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-best-practices.html).
