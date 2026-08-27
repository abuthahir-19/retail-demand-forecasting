#!/usr/bin/env bash
# Create the GCS landing bucket (raw POS data, partitioned by date/store)
# and the Dataproc staging bucket (job jars, cluster staging), then grant
# the service accounts bucket-scoped access. Safe to re-run.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
LANDING_BUCKET="${LANDING_BUCKET:-retail-analytics-landing-${PROJECT_ID}}"
STAGING_BUCKET="${STAGING_BUCKET:-retail-analytics-staging-${PROJECT_ID}}"
INGESTION_SA="ingestion-api-sa@${PROJECT_ID}.iam.gserviceaccount.com"
ETL_SA="etl-job-sa@${PROJECT_ID}.iam.gserviceaccount.com"

create_bucket_if_missing() {
  local bucket="$1"
  if gsutil ls -b "gs://${bucket}" >/dev/null 2>&1; then
    echo "Bucket gs://${bucket} already exists, skipping create."
  else
    gcloud storage buckets create "gs://${bucket}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --uniform-bucket-level-access
  fi
}

echo "Creating buckets on project: ${PROJECT_ID} (region ${REGION})"
create_bucket_if_missing "${LANDING_BUCKET}"
create_bucket_if_missing "${STAGING_BUCKET}"

echo "Granting bucket-level roles"
gcloud storage buckets add-iam-policy-binding "gs://${LANDING_BUCKET}" \
  --member="serviceAccount:${INGESTION_SA}" --role="roles/storage.objectCreator"
gcloud storage buckets add-iam-policy-binding "gs://${LANDING_BUCKET}" \
  --member="serviceAccount:${ETL_SA}" --role="roles/storage.objectAdmin"
gcloud storage buckets add-iam-policy-binding "gs://${STAGING_BUCKET}" \
  --member="serviceAccount:${ETL_SA}" --role="roles/storage.objectAdmin"

echo "Done. Buckets:"
echo "  gs://${LANDING_BUCKET}  (raw/dt=YYYY-MM-DD/store=<id>/*.json)"
echo "  gs://${STAGING_BUCKET}  (Dataproc jars + staging)"
