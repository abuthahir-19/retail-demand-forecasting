#!/usr/bin/env bash
# Create the BigQuery dataset and apply ddl.sql (all CREATE TABLE IF NOT
# EXISTS, so safe to re-run).
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
REGION="${REGION:-us-central1}"
DATASET="${DATASET:-retail_analytics}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if bq show --project_id="${PROJECT_ID}" "${DATASET}" >/dev/null 2>&1; then
  echo "Dataset ${DATASET} already exists, skipping create."
else
  bq mk --project_id="${PROJECT_ID}" --location="${REGION}" --dataset "${DATASET}"
fi

echo "Applying DDL from infra/bigquery/ddl.sql"
bq query --project_id="${PROJECT_ID}" --use_legacy_sql=false < "${SCRIPT_DIR}/../bigquery/ddl.sql"

echo "Done. Tables in ${PROJECT_ID}:${DATASET}:"
bq ls --project_id="${PROJECT_ID}" "${DATASET}"
