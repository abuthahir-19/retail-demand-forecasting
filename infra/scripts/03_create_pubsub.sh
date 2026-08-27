#!/usr/bin/env bash
# Create the Pub/Sub topic transactions are published to for decoupling.
# No subscription is created in the MVP — GCS landing is the batch source
# of truth for the Spark job; the topic exists so future stream consumers
# can attach without changing the ingestion API. Safe to re-run.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-gcp-learning-acnt}"
TOPIC="${TOPIC:-pos-transactions}"

if gcloud pubsub topics describe "${TOPIC}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Topic ${TOPIC} already exists, skipping create."
else
  gcloud pubsub topics create "${TOPIC}" --project="${PROJECT_ID}"
fi

echo "Done. Topic: projects/${PROJECT_ID}/topics/${TOPIC}"
