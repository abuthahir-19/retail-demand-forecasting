package com.retailanalytics.ingestion.controller;

import com.retailanalytics.ingestion.model.Transaction;
import com.retailanalytics.ingestion.service.GcsLandingService;
import com.retailanalytics.ingestion.service.PubSubPublisherService;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/transactions")
public class TransactionController {

    private static final Logger log = LoggerFactory.getLogger(TransactionController.class);

    private final PubSubPublisherService publisherService;
    private final GcsLandingService landingService;

    public TransactionController(PubSubPublisherService publisherService, GcsLandingService landingService) {
        this.publisherService = publisherService;
        this.landingService = landingService;
    }

    @PostMapping
    public ResponseEntity<Map<String, String>> ingest(@Valid @RequestBody Transaction transaction) throws Exception {
        landingService.land(transaction);
        String messageId = publisherService.publish(transaction);
        log.info("Ingested transaction {} for store {} (pubsub messageId={})",
                transaction.transactionId(), transaction.storeId(), messageId);
        return ResponseEntity.accepted().body(Map.of(
                "transactionId", transaction.transactionId(),
                "pubsubMessageId", messageId
        ));
    }
}
