# Terraform state bootstrap

This independent configuration creates the persistent S3 bucket used for
Terraform state. It uses local state only while bootstrapping, and the bucket is
an explicit exception to same-day teardown under `docs/cost-guardrails.md`.

Run its plan and apply only inside an AWS session. Do not destroy this
configuration as part of a short-lived EKS session.
