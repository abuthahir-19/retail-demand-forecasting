package com.retailanalytics.etl.forecast;

import org.apache.spark.ml.Pipeline;
import org.apache.spark.ml.PipelineModel;
import org.apache.spark.ml.feature.StringIndexer;
import org.apache.spark.ml.feature.VectorAssembler;
import org.apache.spark.ml.regression.LinearRegression;
import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.SaveMode;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.expressions.Window;
import org.apache.spark.sql.expressions.WindowSpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.apache.spark.sql.functions.*;

/**
 * Trains a linear-regression model on lag features + day-of-week, then
 * scores it against the next {@code horizonDays} calendar dates.
 *
 * Simplification: all {@code horizonDays} forecast rows reuse the SAME
 * lag1/lag7 snapshot taken as of {@code processDate} (only day-of-week
 * varies across the horizon) rather than a recursive walk-forward forecast
 * that feeds each day's prediction into the next day's lag features. That
 * keeps the whole horizon a single vectorized transform instead of a
 * per-day loop with forecast-on-forecast error compounding — an accepted
 * tradeoff for this MVP.
 */
public final class ForecastPipeline {

    private static final Logger log = LoggerFactory.getLogger(ForecastPipeline.class);

    private ForecastPipeline() {
    }

    public static void run(SparkSession spark, String bqProjectId, String bqDataset,
                            LocalDate processDate, int historyDays, int horizonDays) {
        String dailySalesTable = bqProjectId + ":" + bqDataset + ".daily_sales";
        String forecastsTable = bqProjectId + ":" + bqDataset + ".sku_forecasts";

        Dataset<Row> history = spark.read().format("bigquery").option("table", dailySalesTable).load()
                .select("date", "store_id", "sku", "total_qty")
                .filter(col("date").geq(lit(processDate.minusDays(historyDays).toString()))
                        .and(col("date").leq(lit(processDate.toString()))));

        WindowSpec byStoreSkuOrderedByDate = Window.partitionBy("store_id", "sku").orderBy("date");
        Dataset<Row> withLags = history
                .withColumn("day_of_week", dayofweek(col("date")))
                .withColumn("lag1", lag(col("total_qty"), 1).over(byStoreSkuOrderedByDate))
                .withColumn("lag7", lag(col("total_qty"), 7).over(byStoreSkuOrderedByDate));

        Dataset<Row> trainDf = withLags.filter(col("lag1").isNotNull().and(col("lag7").isNotNull())).cache();
        if (trainDf.isEmpty()) {
            log.warn("No rows with 7+ days of prior history yet as of {} (still early in daily_sales backfill) "
                    + "- skipping forecast for this run.", processDate);
            return;
        }

        StringIndexer storeIndexer = new StringIndexer()
                .setInputCol("store_id").setOutputCol("storeIdx").setHandleInvalid("keep");
        StringIndexer skuIndexer = new StringIndexer()
                .setInputCol("sku").setOutputCol("skuIdx").setHandleInvalid("keep");
        VectorAssembler assembler = new VectorAssembler()
                .setInputCols(new String[]{"storeIdx", "skuIdx", "day_of_week", "lag1", "lag7"})
                .setOutputCol("features");
        LinearRegression regression = new LinearRegression()
                .setFeaturesCol("features").setLabelCol("total_qty").setPredictionCol("prediction");

        PipelineModel model = new Pipeline()
                .setStages(new org.apache.spark.ml.PipelineStage[]{storeIndexer, skuIndexer, assembler, regression})
                .fit(trainDf);

        // Positional (row-number-based), not calendar-exact-date, matching
        // how lag1/lag7 are computed for trainDf above: most SKUs don't
        // sell on every single day, so requiring sales on exactly
        // processDate AND exactly processDate-6 left this empty for
        // almost every store/sku in practice, even with plenty of
        // history. "Its most recent known day" and "7 days before that
        // in its own sequence" is the sparse-data-friendly equivalent.
        WindowSpec byStoreSkuOrderedByDateDesc = Window.partitionBy("store_id", "sku").orderBy(col("date").desc());
        Dataset<Row> ranked = history.withColumn("rn", row_number().over(byStoreSkuOrderedByDateDesc));
        Dataset<Row> snapshot = ranked
                .filter(col("rn").leq(7))
                .groupBy("store_id", "sku")
                .agg(
                        max(when(col("rn").equalTo(1), col("total_qty"))).as("lag1"),
                        max(when(col("rn").equalTo(7), col("total_qty"))).as("lag7")
                )
                .filter(col("lag1").isNotNull().and(col("lag7").isNotNull()));

        List<Row> forecastDateRows = new ArrayList<>();
        for (int i = 1; i <= horizonDays; i++) {
            forecastDateRows.add(org.apache.spark.sql.RowFactory.create(processDate.plusDays(i).toString()));
        }
        Dataset<Row> forecastDates = spark.createDataFrame(forecastDateRows,
                new org.apache.spark.sql.types.StructType()
                        .add("forecast_date", org.apache.spark.sql.types.DataTypes.StringType));

        Dataset<Row> toScore = snapshot.crossJoin(forecastDates)
                .withColumn("date", col("forecast_date").cast("date"))
                .withColumn("day_of_week", dayofweek(col("date")));

        Dataset<Row> scored = model.transform(toScore);

        // LinearRegression has no non-negativity constraint, so low-demand
        // store/sku pairs can score below zero; clamp since demand can't
        // be negative.
        Dataset<Row> forecastOutput = scored
                .select(
                        col("forecast_date").cast("date").as("forecast_date"),
                        col("store_id"),
                        col("sku"),
                        greatest(col("prediction"), lit(0.0)).as("forecasted_qty")
                )
                .withColumn("model_run_ts", current_timestamp());

        forecastOutput.write().format("bigquery")
                .option("table", forecastsTable)
                .option("writeMethod", "direct")
                .mode(SaveMode.Append)
                .save();
    }
}
