<#
.SYNOPSIS
  Run the ETL/forecast job locally against real GCS + BigQuery, via a real
  spark-submit (not a hand-rolled `java` command — Spark's driver-side
  DataSource/FileSystem lookups for --jars only resolve reliably through
  spark-submit's own classloader setup).

.PREREQUISITES
  1. A local Spark distribution matching Dataproc's version, e.g.:
       Invoke-WebRequest https://archive.apache.org/dist/spark/spark-3.5.1/spark-3.5.1-bin-hadoop3.tgz -OutFile spark.tgz
       tar xzf spark.tgz
     Point $SparkHome below at the extracted folder.
  2. The BigQuery connector jar (get the latest 2.12 build from
     gs://spark-lib/bigquery/) and the GCS connector
     (com.google.cloud.bigdataoss:gcs-connector:hadoop3-2.2.21:shaded,
     already in the local Maven repo as a `provided` dependency).
  3. A service-account key for etl-job-sa with access to the landing
     bucket + BigQuery dataset (see infra/scripts/01_create_service_accounts.sh).
     Create a short-lived one for testing and delete it when done:
       gcloud iam service-accounts keys create key.json --iam-account=etl-job-sa@<project>.iam.gserviceaccount.com
       gcloud iam service-accounts keys delete <key-id> --iam-account=etl-job-sa@<project>.iam.gserviceaccount.com

.EXAMPLE
  ./local-test.ps1 -ProcessDate 2026-07-25 -RawBasePath gs://retail-analytics-landing-gcp-learning-acnt/raw `
      -BqProjectId gcp-learning-acnt -BqDataset retail_analytics
#>
param(
    [Parameter(Mandatory = $true)][string]$ProcessDate,
    [Parameter(Mandatory = $true)][string]$RawBasePath,
    [Parameter(Mandatory = $true)][string]$BqProjectId,
    [Parameter(Mandatory = $true)][string]$BqDataset,
    [int]$HistoryDays = 90,
    [int]$HorizonDays = 7,
    [string]$SparkHome = "$PSScriptRoot\.secrets\spark-3.5.1-bin-hadoop3",
    [string]$SaKeyFile = "$PSScriptRoot\.secrets\etl-job-sa-key.json",
    [string]$BqConnectorJar = "$PSScriptRoot\.secrets\spark-bigquery-with-dependencies_2.12-0.45.0.jar",
    [string]$GcsConnectorJar = "$env:USERPROFILE\.m2\repository\com\google\cloud\bigdataoss\gcs-connector\hadoop3-2.2.21\gcs-connector-hadoop3-2.2.21-shaded.jar"
)

$env:SPARK_HOME = $SparkHome
$jobJar = "$PSScriptRoot\target\etl-spark-job-0.1.0.jar"

& "$SparkHome\bin\spark-submit.cmd" `
    --master "local[2]" `
    --jars "$BqConnectorJar,$GcsConnectorJar" `
    --driver-class-path "$BqConnectorJar;$GcsConnectorJar" `
    --conf "spark.hadoop.google.cloud.auth.service.account.json.keyfile=$SaKeyFile" `
    --class com.retailanalytics.etl.EtlForecastJob `
    $jobJar $ProcessDate $RawBasePath $BqProjectId $BqDataset $HistoryDays $HorizonDays
