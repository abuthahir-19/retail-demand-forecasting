#!/usr/bin/env bash
# Create the two service accounts this platform runs as, and grant each the
# minimum IAM roles it needs. Safe to re-run: gcloud no-ops on an existing SA
# and IAM bindings are idempotent (add-iam-policy-binding on an existing
# binding is a no-op).
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
LANDING_BUCKET="${LANDING_BUCKET:-retail-analytics-landing-${PROJECT_ID}}"
STAGING_BUCKET="${STAGING_BUCKET:-retail-analytics-staging-${PROJECT_ID}}"

INGESTION_SA_NAME="ingestion-api-sa"
ETL_SA_NAME="etl-job-sa"
INGESTION_SA="${INGESTION_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
ETL_SA="${ETL_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

create_sa_if_missing() {
  local name="$1" display="$2"
  if gcloud iam service-accounts describe "${name}@${PROJECT_ID}.iam.gserviceaccount.com" \
      --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Service account ${name} already exists, skipping create."
  else
    gcloud iam service-accounts create "${name}" \
      --project="${PROJECT_ID}" \
      --display-name="${display}"
  fi
}

echo "Creating service accounts on project: ${PROJECT_ID}"
create_sa_if_missing "${INGESTION_SA_NAME}" "Retail Analytics - Ingestion API (Cloud Run)"
create_sa_if_missing "${ETL_SA_NAME}" "Retail Analytics - Spark ETL job (Dataproc)"

echo "Granting project-level roles to ${INGESTION_SA}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${INGESTION_SA}" --role="roles/pubsub.publisher" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${INGESTION_SA}" --role="roles/bigquery.jobUser" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${INGESTION_SA}" --role="roles/bigquery.dataViewer" --condition=None

echo "Granting project-level roles to ${ETL_SA}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${ETL_SA}" --role="roles/bigquery.jobUser" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${ETL_SA}" --role="roles/bigquery.dataEditor" --condition=None
# The spark-bigquery connector always goes through the BigQuery Storage
# API (even for writes in "direct" mode), which needs readsessions.create
# on top of dataEditor/jobUser.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${ETL_SA}" --role="roles/bigquery.readSessionUser" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${ETL_SA}" --role="roles/dataproc.worker" --condition=None

# Bucket-scoped storage roles are granted in 02_create_storage.sh once the
# buckets exist (storage.objectCreator for the ingestion SA on the landing
# bucket, storage.objectAdmin for the ETL SA on landing + staging buckets).

echo "Done. Service accounts:"
echo "  ${INGESTION_SA}"
echo "  ${ETL_SA}"
