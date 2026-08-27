package com.retailanalytics.ingestion.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import com.retailanalytics.ingestion.config.GcpProperties;
import com.retailanalytics.ingestion.model.Transaction;
import org.springframework.stereotype.Service;

import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;

@Service
public class GcsLandingService {

    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ISO_LOCAL_DATE;

    private final Storage storage;
    private final ObjectMapper objectMapper;
    private final String bucket;

    public GcsLandingService(GcpProperties gcpProperties, ObjectMapper objectMapper) {
        this.storage = StorageOptions.newBuilder().setProjectId(gcpProperties.projectId()).build().getService();
        this.objectMapper = objectMapper;
        this.bucket = gcpProperties.landingBucket();
    }

    public void land(Transaction transaction) throws Exception {
        String date = transaction.timestamp().atZone(ZoneOffset.UTC).format(DATE_FORMAT);
        String objectName = "raw/dt=%s/store=%s/%s.json".formatted(
                date, transaction.storeId(), transaction.transactionId());

        BlobId blobId = BlobId.of(bucket, objectName);
        BlobInfo blobInfo = BlobInfo.newBuilder(blobId).setContentType("application/json").build();
        storage.create(blobInfo, objectMapper.writeValueAsBytes(transaction));
    }
}
