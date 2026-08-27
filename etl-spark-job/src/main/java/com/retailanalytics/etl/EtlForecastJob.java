package com.retailanalytics.etl;

import com.retailanalytics.etl.forecast.ForecastPipeline;
import com.retailanalytics.etl.transform.AggregationStep;
import org.apache.spark.sql.SparkSession;

import java.time.LocalDate;

/**
 * Entry point for the nightly ETL + forecast job.
 *
 * Args: processDate(yyyy-MM-dd) rawBasePath(gs://.../raw) bqProjectId bqDataset [historyDays] [horizonDays]
 *
 * On Dataproc, --master is supplied by spark-submit (yarn). For local runs
 * pass -Dspark.master=local[*] on the java/mvn command line.
 */
public final class EtlForecastJob {

    public static void main(String[] args) {
        if (args.length < 4) {
            System.err.println("Usage: EtlForecastJob <processDate:yyyy-MM-dd> <rawBasePath> <bqProjectId> <bqDataset> [historyDays=90] [horizonDays=7]");
            System.exit(1);
        }
        LocalDate processDate = LocalDate.parse(args[0]);
        String rawBasePath = args[1];
        String bqProjectId = args[2];
        String bqDataset = args[3];
        int historyDays = args.length > 4 ? Integer.parseInt(args[4]) : 90;
        int horizonDays = args.length > 5 ? Integer.parseInt(args[5]) : 7;

        SparkSession.Builder builder = SparkSession.builder().appName("retail-etl-forecast-job");
        String masterOverride = System.getProperty("spark.master");
        if (masterOverride != null) {
            builder = builder.master(masterOverride);
        }
        SparkSession spark = builder.getOrCreate();

        try {
            AggregationStep.run(spark, rawBasePath, processDate, bqProjectId, bqDataset);
            ForecastPipeline.run(spark, bqProjectId, bqDataset, processDate, historyDays, horizonDays);
        } finally {
            spark.stop();
        }
    }
}
