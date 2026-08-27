#!/usr/bin/env bash
# Enable the GCP APIs this platform needs. Safe to re-run — enabling an
# already-enabled API is a no-op.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"

APIS=(
  run.googleapis.com
  pubsub.googleapis.com
  storage.googleapis.com
  bigquery.googleapis.com
  dataproc.googleapis.com
  artifactregistry.googleapis.com
  cloudscheduler.googleapis.com
  workflows.googleapis.com
  iam.googleapis.com
  cloudresourcemanager.googleapis.com
)

echo "Enabling APIs on project: ${PROJECT_ID}"
gcloud services enable "${APIS[@]}" --project="${PROJECT_ID}"
echo "Done."
