package com.retailanalytics.ingestion.controller;

import com.retailanalytics.ingestion.model.DailySalesPoint;
import com.retailanalytics.ingestion.model.ForecastPoint;
import com.retailanalytics.ingestion.service.BigQueryQueryService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Optional;

@RestController
public class ForecastController {

    private final BigQueryQueryService queryService;

    public ForecastController(BigQueryQueryService queryService) {
        this.queryService = queryService;
    }

    @GetMapping("/forecasts")
    public List<ForecastPoint> forecasts(
            @RequestParam String store,
            @RequestParam(required = false) String sku
    ) throws InterruptedException {
        return queryService.latestForecasts(store, Optional.ofNullable(sku));
    }

    @GetMapping("/sales/daily")
    public List<DailySalesPoint> dailySales(
            @RequestParam String store,
            @RequestParam(required = false) String sku,
            @RequestParam(defaultValue = "30") int days
    ) throws InterruptedException {
        return queryService.dailySales(store, Optional.ofNullable(sku), days);
    }
}
