package com.retailanalytics.ingestion.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "retail.gcp")
public record GcpProperties(
        String projectId,
        String landingBucket,
        String pubsubTopic,
        String bigqueryDataset
) {
}
