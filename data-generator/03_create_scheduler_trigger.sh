#!/usr/bin/env bash
# Nightly Cloud Scheduler trigger for the pos-generator Cloud Run Job, 2
# hours before the ETL orchestration workflow (03:00 UTC) so each day's
# live transactions land before that day is processed as "yesterday" by
# the following night's run. Reuses orchestration-sa (already proven to
# need OAuth2, not OIDC, for calling a Google-managed API directly - see
# orchestration/02_create_scheduler_job.sh) rather than a new SA, granted
# run.invoker scoped to just this job. Safe to re-run.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
JOB_NAME="${JOB_NAME:-pos-generator}"
SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-pos-generator-nightly-trigger}"
SCHEDULE="${SCHEDULE:-0 1 * * *}"

ORCHESTRATION_SA="orchestration-sa@${PROJECT_ID}.iam.gserviceaccount.com"
RUN_URI="https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/jobs/${JOB_NAME}:run"

echo "Granting run.invoker on ${JOB_NAME} to ${ORCHESTRATION_SA}"
gcloud run jobs add-iam-policy-binding "${JOB_NAME}" \
  --project="${PROJECT_ID}" --region="${REGION}" \
  --member="serviceAccount:${ORCHESTRATION_SA}" --role="roles/run.invoker"

if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Scheduler job ${SCHEDULER_JOB_NAME} already exists, deleting before recreate."
  gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" --location="${REGION}" --project="${PROJECT_ID}" --quiet
fi

gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --schedule="${SCHEDULE}" \
  --time-zone="Etc/UTC" \
  --uri="${RUN_URI}" \
  --http-method=POST \
  --oauth-service-account-email="${ORCHESTRATION_SA}" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"

echo "Done. Scheduler job ${SCHEDULER_JOB_NAME} triggers ${JOB_NAME} nightly at ${SCHEDULE} UTC."
