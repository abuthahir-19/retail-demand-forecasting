package com.retailanalytics.ingestion.model;

public record DailySalesPoint(
        String date,
        String storeId,
        String sku,
        String category,
        long totalQty,
        double totalRevenue,
        long txnCount,
        Double movingAvg7d,
        Double movingAvg30d,
        Double yoyGrowthPct
) {
}
