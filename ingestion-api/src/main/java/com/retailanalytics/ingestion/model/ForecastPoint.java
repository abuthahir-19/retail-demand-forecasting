package com.retailanalytics.ingestion.model;

public record ForecastPoint(
        String forecastDate,
        String storeId,
        String sku,
        double forecastedQty,
        String modelRunTs
) {
}
