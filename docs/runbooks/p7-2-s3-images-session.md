# P7.2 S3 image-adapter learning session

Use this runbook only after manually completing every **Before the session** item in
[aws-session.md](aws-session.md), confirming current spend remains below the USD 16 stop
threshold, setting an independently alarmed same-day teardown deadline, and reviewing the
Terraform plan. This is a short-lived private-S3 and IRSA exercise, not a production asset
pipeline.

## Apply the reviewed infrastructure

1. Start from the P7.1 infrastructure profile: provide the out-of-band RDS password only in
   the current shell, and enable both `rds_enabled=true` and `s3_images_enabled=true` for this
   session. Do not put the password, generated bucket name, role ARN, database URL, or a
   presigned URL in a committed file, terminal evidence, or screenshot.
2. Inspect the plan before applying. In addition to the reviewed no-NAT VPC, EKS, and private
   Single-AZ RDS resources, expect only the temporary S3 bucket hardening/versioning resources,
   six synthetic SVG objects beneath `products/`, and the API's S3-read IRSA role/policy. Stop
   if it contains a NAT Gateway, a public bucket policy/ACL, or an unplanned service.
3. Apply only that reviewed plan. The S3 bucket, objects, role, and policy are session-scoped;
   they are never persistent-resource exceptions.

## Bootstrap the scoped API identity

Complete the namespace, `gp3` StorageClass, and ALB-controller setup in
[p6-4-ci-deploy.md](p6-4-ci-deploy.md). Then create the API ServiceAccount and its non-secret
runtime configuration before CI deploys the chart's S3 overlay:

```text
image_role_arn="$(terraform -chdir=infra/terraform output -raw product_images_api_role_arn)"
image_bucket="$(terraform -chdir=infra/terraform output -raw product_images_bucket_name)"

kubectl -n bedoux create serviceaccount bedoux-api
kubectl -n bedoux annotate serviceaccount bedoux-api \
  eks.amazonaws.com/role-arn="$image_role_arn"
kubectl -n bedoux create configmap bedoux-image-storage \
  --from-literal=BEDOUX_S3_BUCKET="$image_bucket" \
  --from-literal=BEDOUX_S3_REGION=ca-central-1 \
  --dry-run=client -o yaml | kubectl apply -f -

unset image_role_arn image_bucket
```

The Helm S3 overlay deliberately sets `api.serviceAccount.create=false`. That preserves this
operator-created IRSA annotation across the namespace-scoped CI Helm upgrade. The ConfigMap holds
only a generated bucket name and region, not a credential.

## Deploy and prove T-702

1. Dispatch **Deploy learning session** from `main` with `use_rds=true`,
   `use_s3_images=true`, and `seed_catalog=true` for the fresh RDS database. The workflow
   refuses to continue unless the ServiceAccount and ConfigMap exist. Its final smoke test masks
   the returned presigned URL, confirms it is HTTPS, fetches the image directly from S3, and
   never prints the URL.
2. Confirm the API pod actually uses the expected IRSA role without exposing its account ID:

   ```text
   kubectl -n bedoux exec deployment/api -- python -c \
     "import boto3; arn=boto3.client('sts').get_caller_identity()['Arn']; assert ':assumed-role/bedoux-product-images-role/' in arn; print('API IRSA caller identity: expected role')"
   ```

3. Record T-702 evidence: the successful workflow run, that catalog responses used `image_url`
   rather than the former storage path, its masked direct-image smoke passed, the IRSA
   caller-identity assertion passed, and the Terraform policy allowed only `s3:GetObject` on the
   temporary bucket's `products/*` prefix. Do not preserve the bucket name, role ARN, image URL,
   database URL, or any credential in the evidence.

## Rollback and teardown

For a configuration rollback before teardown, redeploy without `use_s3_images`; the API returns
its existing static image URLs and the frontend stays unchanged. Do not delete the ServiceAccount
while an S3-mode API pod is still running.

At the independently alarmed deadline, delete the release and namespace, wait for the ALB to
disappear, remove the ALB controller, then use the standard session-destroy sequence:

```text
scripts/terraform-session-destroy.sh prepare
scripts/terraform-session-destroy.sh prepare --execute
scripts/terraform-session-destroy.sh plan
scripts/terraform-session-destroy.sh apply --execute
```

The reviewed destroy plan must include `module.product_images` and must not include any persistent
addresses. Complete the `aws-session.md` teardown sweep, explicitly confirming no project S3
bucket, S3 objects, product-image IRSA role/policy, RDS instance/snapshots/subnet group, EKS
cluster, ALB/target groups, VPC/security groups, NAT Gateway, EIP, or EBS leftovers remain.
