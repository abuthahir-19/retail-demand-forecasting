#!/usr/bin/env bash
# Deploy (or update) the nightly ETL orchestration workflow. Safe to
# re-run - `workflows deploy` upserts.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
WORKFLOW_NAME="${WORKFLOW_NAME:-retail-etl-orchestration}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gcloud workflows deploy "${WORKFLOW_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --source="${SCRIPT_DIR}/workflow.yaml" \
  --service-account="orchestration-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Done. Workflow: projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}"
echo "Trigger a manual test run with:"
echo "  gcloud workflows run ${WORKFLOW_NAME} --location=${REGION} --project=${PROJECT_ID}"
