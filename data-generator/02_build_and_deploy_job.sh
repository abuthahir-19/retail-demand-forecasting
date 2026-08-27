#!/usr/bin/env bash
# Build the generator image, push it, and create (or update) the Cloud
# Run Job that runs it in --mode live against the deployed ingestion-api.
# Safe to re-run - `gcloud run jobs create` fails if the job already
# exists, so this falls back to `update` in that case.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
JOB_NAME="${JOB_NAME:-pos-generator}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/retail-analytics/pos-generator:latest"
API_URL="${API_URL:-https://ingestion-api-63464347864.us-central1.run.app}"
SA_EMAIL="data-generator-sa@${PROJECT_ID}.iam.gserviceaccount.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building ${IMAGE}"
docker build -t "${IMAGE}" "${SCRIPT_DIR}"

echo "Pushing ${IMAGE}"
docker push "${IMAGE}"

JOB_ARGS="--mode,live,--num-stores,15,--num-skus,20,--seed,42,--api-url,${API_URL}"

if gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Job ${JOB_NAME} already exists, updating."
  gcloud run jobs update "${JOB_NAME}" \
    --project="${PROJECT_ID}" --region="${REGION}" \
    --image="${IMAGE}" \
    --service-account="${SA_EMAIL}" \
    --args="${JOB_ARGS}" \
    --max-retries=1 --task-timeout=600
else
  gcloud run jobs create "${JOB_NAME}" \
    --project="${PROJECT_ID}" --region="${REGION}" \
    --image="${IMAGE}" \
    --service-account="${SA_EMAIL}" \
    --args="${JOB_ARGS}" \
    --max-retries=1 --task-timeout=600
fi

echo "Done. Job: projects/${PROJECT_ID}/locations/${REGION}/jobs/${JOB_NAME}"
echo "Trigger a manual test run with:"
echo "  gcloud run jobs execute ${JOB_NAME} --region=${REGION} --project=${PROJECT_ID}"
