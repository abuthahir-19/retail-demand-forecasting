-- Retail Analytics warehouse schema.
-- Dataset is created by 04_create_bigquery.sh before this runs.

CREATE TABLE IF NOT EXISTS retail_analytics.dim_store (
  store_id    STRING NOT NULL,
  store_name  STRING,
  region      STRING,
  city        STRING
);

CREATE TABLE IF NOT EXISTS retail_analytics.dim_sku (
  sku          STRING NOT NULL,
  product_name STRING,
  category     STRING,
  unit_cost    NUMERIC
);

-- One row per (date, store, sku). Partitioned by date so the nightly job
-- only touches (and can idempotently delete+reinsert) a single partition.
CREATE TABLE IF NOT EXISTS retail_analytics.daily_sales (
  date            DATE NOT NULL,
  store_id        STRING NOT NULL,
  sku             STRING NOT NULL,
  category        STRING,
  total_qty       INT64,
  total_revenue   NUMERIC,
  txn_count       INT64,
  moving_avg_7d    FLOAT64,
  moving_avg_30d   FLOAT64,
  yoy_growth_pct   FLOAT64,
  etl_run_ts      TIMESTAMP
)
PARTITION BY date
CLUSTER BY store_id, sku;

-- One row per (forecast_date, store, sku) per model run. The API reads the
-- latest model_run_ts for a given forecast_date/store/sku.
CREATE TABLE IF NOT EXISTS retail_analytics.sku_forecasts (
  forecast_date    DATE NOT NULL,
  store_id         STRING NOT NULL,
  sku              STRING NOT NULL,
  forecasted_qty   FLOAT64,
  model_run_ts     TIMESTAMP NOT NULL
)
PARTITION BY forecast_date
CLUSTER BY store_id, sku;
