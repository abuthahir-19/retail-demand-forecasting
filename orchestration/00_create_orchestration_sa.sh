#!/usr/bin/env bash
# Service account the Cloud Workflows execution runs as. Distinct from
# etl-job-sa (which the Dataproc cluster's VMs run as) - this identity
# instead needs permission to manage Dataproc clusters/jobs from the
# control-plane side, plus the right to attach etl-job-sa to a cluster it
# creates. Also used as the Cloud Scheduler job's OIDC caller identity, so
# it needs workflows.invoker too. Safe to re-run.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
SA_NAME="orchestration-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
ETL_SA="etl-job-sa@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Service account ${SA_NAME} already exists, skipping create."
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Retail Analytics - Nightly orchestration (Workflows + Scheduler)"
fi

echo "Granting project-level roles to ${SA_EMAIL}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/dataproc.editor" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/workflows.invoker" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/logging.logWriter" --condition=None
# Needed for the workflow's own validate_row_count step, which runs a
# BigQuery query directly (not via the Dataproc job) to sanity-check the
# new date partition landed.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/bigquery.jobUser" --condition=None
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/bigquery.dataViewer" --condition=None

echo "Granting serviceAccountUser on ${ETL_SA} to ${SA_EMAIL} (needed to attach it to Dataproc clusters)"
gcloud iam service-accounts add-iam-policy-binding "${ETL_SA}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/iam.serviceAccountUser"

echo "Done. Service account: ${SA_EMAIL}"
