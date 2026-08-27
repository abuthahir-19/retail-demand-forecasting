package com.retailanalytics.ingestion.service;

import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.BigQueryOptions;
import com.google.cloud.bigquery.FieldValueList;
import com.google.cloud.bigquery.QueryJobConfiguration;
import com.google.cloud.bigquery.QueryParameterValue;
import com.google.cloud.bigquery.TableResult;
import com.retailanalytics.ingestion.config.GcpProperties;
import com.retailanalytics.ingestion.model.DailySalesPoint;
import com.retailanalytics.ingestion.model.ForecastPoint;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Service
public class BigQueryQueryService {

    private final BigQuery bigQuery;
    private final String dataset;

    public BigQueryQueryService(GcpProperties gcpProperties) {
        this.bigQuery = BigQueryOptions.newBuilder().setProjectId(gcpProperties.projectId()).build().getService();
        this.dataset = gcpProperties.bigqueryDataset();
    }

    public List<ForecastPoint> latestForecasts(String storeId, Optional<String> sku) throws InterruptedException {
        String skuFilter = sku.isPresent() ? "AND sku = @sku" : "";
        String sql = """
                WITH ranked AS (
                  SELECT forecast_date, store_id, sku, forecasted_qty, model_run_ts,
                         ROW_NUMBER() OVER (PARTITION BY forecast_date, store_id, sku ORDER BY model_run_ts DESC) AS rn
                  FROM `%s.sku_forecasts`
                  WHERE store_id = @storeId %s
                )
                SELECT forecast_date, store_id, sku, forecasted_qty, model_run_ts
                FROM ranked
                WHERE rn = 1
                ORDER BY forecast_date
                """.formatted(dataset, skuFilter);

        QueryJobConfiguration.Builder configBuilder = QueryJobConfiguration.newBuilder(sql)
                .addNamedParameter("storeId", QueryParameterValue.string(storeId));
        sku.ifPresent(s -> configBuilder.addNamedParameter("sku", QueryParameterValue.string(s)));

        TableResult result = bigQuery.query(configBuilder.build());
        List<ForecastPoint> points = new ArrayList<>();
        for (FieldValueList row : result.iterateAll()) {
            points.add(new ForecastPoint(
                    row.get("forecast_date").getStringValue(),
                    row.get("store_id").getStringValue(),
                    row.get("sku").getStringValue(),
                    row.get("forecasted_qty").getDoubleValue(),
                    row.get("model_run_ts").getStringValue()
            ));
        }
        return points;
    }

    public List<DailySalesPoint> dailySales(String storeId, Optional<String> sku, int days) throws InterruptedException {
        String skuFilter = sku.isPresent() ? "AND sku = @sku" : "";
        String sql = """
                SELECT date, store_id, sku, category, total_qty, total_revenue, txn_count,
                       moving_avg_7d, moving_avg_30d, yoy_growth_pct
                FROM `%s.daily_sales`
                WHERE store_id = @storeId %s
                  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY)
                ORDER BY date DESC
                """.formatted(dataset, skuFilter);

        QueryJobConfiguration.Builder configBuilder = QueryJobConfiguration.newBuilder(sql)
                .addNamedParameter("storeId", QueryParameterValue.string(storeId))
                .addNamedParameter("days", QueryParameterValue.int64(days));
        sku.ifPresent(s -> configBuilder.addNamedParameter("sku", QueryParameterValue.string(s)));

        TableResult result = bigQuery.query(configBuilder.build());
        List<DailySalesPoint> points = new ArrayList<>();
        for (FieldValueList row : result.iterateAll()) {
            points.add(new DailySalesPoint(
                    row.get("date").getStringValue(),
                    row.get("store_id").getStringValue(),
                    row.get("sku").getStringValue(),
                    row.get("category").isNull() ? null : row.get("category").getStringValue(),
                    row.get("total_qty").getLongValue(),
                    row.get("total_revenue").getDoubleValue(),
                    row.get("txn_count").getLongValue(),
                    row.get("moving_avg_7d").isNull() ? null : row.get("moving_avg_7d").getDoubleValue(),
                    row.get("moving_avg_30d").isNull() ? null : row.get("moving_avg_30d").getDoubleValue(),
                    row.get("yoy_growth_pct").isNull() ? null : row.get("yoy_growth_pct").getDoubleValue()
            ));
        }
        return points;
    }
}
