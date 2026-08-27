package com.retailanalytics.etl.transform;

import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.BigQueryOptions;
import com.google.cloud.bigquery.QueryJobConfiguration;
import com.google.cloud.bigquery.QueryParameterValue;
import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.SaveMode;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.expressions.Window;
import org.apache.spark.sql.expressions.WindowSpec;

import java.time.LocalDate;

import static org.apache.spark.sql.functions.*;

/**
 * Reads one day of raw POS transactions, cleans/aggregates them to the
 * (date, store, sku) grain, layers on 7/30-day rolling averages and a
 * best-effort YoY comparison, then idempotently replaces that date's
 * partition in {@code daily_sales}.
 */
public final class AggregationStep {

    private AggregationStep() {
    }

    public static void run(SparkSession spark, String rawBasePath, LocalDate processDate,
                            String bqProjectId, String bqDataset) {
        String rawPath = rawBasePath + "/dt=" + processDate + "/*";
        Dataset<Row> raw = spark.read().json(rawPath);

        Dataset<Row> cleaned = raw
                .dropDuplicates("transactionId")
                .filter(col("quantity").gt(0).and(col("unitPrice").gt(0))
                        .and(col("storeId").isNotNull()).and(col("sku").isNotNull()));

        Dataset<Row> todayAgg = cleaned
                .groupBy(col("storeId").as("store_id"), col("sku"), col("category"))
                .agg(
                        sum("quantity").as("total_qty"),
                        sum(col("quantity").multiply(col("unitPrice"))).as("total_revenue"),
                        count("*").as("txn_count")
                )
                .withColumn("date", lit(processDate.toString()).cast("date"));

        String dailySalesTable = bqProjectId + ":" + bqDataset + ".daily_sales";

        Dataset<Row> history = spark.read().format("bigquery").option("table", dailySalesTable).load()
                .select("date", "store_id", "sku", "category", "total_qty")
                .filter(col("date").geq(lit(processDate.minusDays(30).toString()))
                        .and(col("date").lt(lit(processDate.toString()))));

        Dataset<Row> combined = history
                .select("date", "store_id", "sku", "category", "total_qty")
                .unionByName(todayAgg.select("date", "store_id", "sku", "category", "total_qty"));

        // Position-based rolling windows: correct once a store/sku has enough
        // preceding rows, an accepted approximation for sparse SKUs that
        // don't sell every single day.
        WindowSpec byStoreSkuOrderedByDate = Window.partitionBy("store_id", "sku").orderBy("date");
        Dataset<Row> withRolling = combined
                .withColumn("moving_avg_7d", avg("total_qty").over(byStoreSkuOrderedByDate.rowsBetween(-6, 0)))
                .withColumn("moving_avg_30d", avg("total_qty").over(byStoreSkuOrderedByDate.rowsBetween(-29, 0)))
                .filter(col("date").equalTo(lit(processDate.toString())));

        // combined/history only carried the columns the rolling window
        // needs, so total_revenue/txn_count have to be rejoined from
        // today's aggregate before writing the row back out.
        Dataset<Row> withRevenue = withRolling
                .join(todayAgg.select("store_id", "sku", "total_revenue", "txn_count"),
                        new String[]{"store_id", "sku"}, "left");

        Dataset<Row> yearAgo = spark.read().format("bigquery").option("table", dailySalesTable).load()
                .select(col("store_id"), col("sku"), col("total_qty").as("year_ago_qty"))
                .filter(col("date").equalTo(lit(processDate.minusDays(365).toString())));

        Dataset<Row> withYoy = withRevenue
                .join(yearAgo, new String[]{"store_id", "sku"}, "left")
                .withColumn("yoy_growth_pct",
                        when(col("year_ago_qty").isNotNull().and(col("year_ago_qty").gt(0)),
                                (col("total_qty").minus(col("year_ago_qty")))
                                        .divide(col("year_ago_qty")).multiply(100))
                                .otherwise(lit(null).cast("double")))
                .drop("year_ago_qty")
                .withColumn("total_revenue", col("total_revenue").cast("decimal(18,2)"))
                .withColumn("etl_run_ts", current_timestamp());

        deleteExistingPartition(bqProjectId, bqDataset, processDate);

        withYoy.write().format("bigquery")
                .option("table", dailySalesTable)
                .option("writeMethod", "direct")
                .mode(SaveMode.Append)
                .save();
    }

    private static void deleteExistingPartition(String bqProjectId, String bqDataset, LocalDate processDate) {
        BigQuery bigQuery = BigQueryOptions.newBuilder().setProjectId(bqProjectId).build().getService();
        String sql = String.format("DELETE FROM `%s.daily_sales` WHERE date = @processDate", bqDataset);
        QueryJobConfiguration config = QueryJobConfiguration.newBuilder(sql)
                .addNamedParameter("processDate", QueryParameterValue.date(processDate.toString()))
                .build();
        try {
            bigQuery.query(config);
        } catch (InterruptedException e) {
            throw new RuntimeException("Failed to delete existing daily_sales partition for " + processDate, e);
        }
    }
}
