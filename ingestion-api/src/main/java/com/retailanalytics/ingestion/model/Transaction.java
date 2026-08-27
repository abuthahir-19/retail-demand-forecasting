package com.retailanalytics.ingestion.model;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

import java.time.Instant;

public record Transaction(
        @NotBlank String transactionId,
        @NotBlank String storeId,
        @NotBlank String sku,
        String category,
        @Positive int quantity,
        @Positive double unitPrice,
        @JsonFormat(shape = JsonFormat.Shape.STRING) Instant timestamp
) {
}
