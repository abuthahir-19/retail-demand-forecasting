#!/usr/bin/env bash
# Nightly Cloud Scheduler trigger for the orchestration workflow. Safe to
# re-run - deletes and recreates the scheduler job if it already exists,
# since `scheduler jobs update` has more limited flag support than create.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
WORKFLOW_NAME="${WORKFLOW_NAME:-retail-etl-orchestration}"
SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-retail-etl-nightly-trigger}"
# 03:00 UTC nightly, after the day's transactions have fully landed.
SCHEDULE="${SCHEDULE:-0 3 * * *}"

SA_EMAIL="orchestration-sa@${PROJECT_ID}.iam.gserviceaccount.com"
WORKFLOW_URI="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}/executions"

if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Scheduler job ${SCHEDULER_JOB_NAME} already exists, deleting before recreate."
  gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" --location="${REGION}" --project="${PROJECT_ID}" --quiet
fi

# workflowexecutions.googleapis.com is a Google Cloud API, not a
# customer-run backend - it needs an OAuth2 access token (oauth-token),
# not an OIDC identity token (oidc-token, which is for calling your own
# services like Cloud Run that verify the token themselves). Using OIDC
# here caused every real nightly trigger to fail with a 401
# UNAUTHENTICATED against the Workflows Executions API.
gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --schedule="${SCHEDULE}" \
  --time-zone="Etc/UTC" \
  --uri="${WORKFLOW_URI}" \
  --http-method=POST \
  --oauth-service-account-email="${SA_EMAIL}" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"

echo "Done. Scheduler job ${SCHEDULER_JOB_NAME} triggers ${WORKFLOW_NAME} nightly at ${SCHEDULE} UTC."
