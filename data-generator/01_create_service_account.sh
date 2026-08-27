#!/usr/bin/env bash
# Runtime identity for the pos-generator Cloud Run Job. It only makes
# outbound HTTPS POSTs to the public (--allow-unauthenticated)
# ingestion-api - it never touches GCS/BigQuery/etc directly - so it needs
# zero IAM roles of its own. Kept as a dedicated identity anyway rather
# than the default compute service account, for the same
# least-privilege/one-identity-per-component reasons as ingestion-api-sa
# and etl-job-sa. Safe to re-run.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
SA_NAME="data-generator-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Service account ${SA_NAME} already exists, skipping create."
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Retail Analytics - POS data generator (Cloud Run Job)"
fi

echo "Done. Service account: ${SA_EMAIL}"
