# Retail Sales Analytics & Demand Forecasting Platform

**Business scenario:** A mid-sized retail chain with ~200 stores wants near-real-time visibility into sales performance and next-week demand forecasts per SKU/store, so store managers can optimize inventory and reduce stockouts/overstock.

## Architecture

**1. Ingestion API (Spring Boot on Cloud Run)**
- REST endpoints receive point-of-sale transactions (`POST /transactions`) and expose analytics/forecast queries (`GET /forecasts?store=&sku=`).
- Publishes raw transactions to **Pub/Sub** for decoupling; writes to a landing zone in **Cloud Storage** (partitioned by `date/store`).
- Stateless, containerized, auto-scales to zero — ideal Cloud Run fit.

**2. Batch Processing (Spark on Dataproc)**
- A nightly **Dataproc** job (Spark, Java/Scala) reads the day's raw files from GCS.
- Cleans, deduplicates, aggregates to daily sales per store/SKU/category, computes rolling metrics (7/30-day moving averages, YoY growth).
- Runs a demand-forecasting model (Spark MLlib — e.g., regression on lag features + seasonality) to produce next-week SKU-level forecasts.
- Writes curated results into **BigQuery**.

**3. Analytics Warehouse (BigQuery)**
- Stores fact tables (`daily_sales`, `sku_forecasts`) and dimensions.
- Serves aggregate queries; the Spring Boot API queries it via the BigQuery Java client for dashboards.

**4. Orchestration**
- **Cloud Scheduler → Cloud Workflows (or Composer/Airflow)** triggers the Dataproc job nightly, then a validation step, then swaps the BigQuery table.

## Data Flow

```
POS → Spring Boot (Cloud Run) → Pub/Sub → GCS (raw)
                                              ↓
                              Dataproc/Spark (nightly ETL + forecast)
                                              ↓
                                          BigQuery (curated)
                                              ↓
                              Spring Boot API → Dashboard
```

## Why this hits every tech cleanly
- **Java + Spring Boot** — the ingestion/query microservice.
- **Cloud Run** — serverless hosting of that service.
- **Google Cloud** — GCS, Pub/Sub, Cloud Scheduler glue.
- **Spark + Dataproc** — the heavy distributed ETL + ML batch layer.
- **BigQuery** — serving layer for analytics.

## Portfolio scoping (medium level, achievable)
- Seed synthetic POS data (a generator script) instead of real feeds.
- One Spark job, 2-3 BigQuery tables, a simple forecast (even linear regression is fine).
- Add a lightweight React dashboard hitting your Spring Boot endpoints to make it demo-able.
- Ephemeral Dataproc clusters (spin up per job) to keep costs near zero.

Stretch goals if you want to show depth: streaming path with **Dataflow** instead of nightly batch, dbt on BigQuery, and CI/CD via Cloud Build.
