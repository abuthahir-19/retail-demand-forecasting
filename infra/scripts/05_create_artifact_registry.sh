#!/usr/bin/env bash
# Create the Artifact Registry Docker repo the ingestion API image is
# pushed to. Safe to re-run.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
REPO="${REPO:-retail-analytics}"

if gcloud artifacts repositories describe "${REPO}" \
    --project="${PROJECT_ID}" --location="${REGION}" >/dev/null 2>&1; then
  echo "Artifact Registry repo ${REPO} already exists, skipping create."
else
  gcloud artifacts repositories create "${REPO}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --repository-format=docker \
    --description="Retail analytics container images"
fi

echo "Done. Repo: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}"
