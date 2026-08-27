package com.retailanalytics.ingestion.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.api.core.ApiFuture;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import com.retailanalytics.ingestion.config.GcpProperties;
import com.retailanalytics.ingestion.model.Transaction;
import jakarta.annotation.PreDestroy;
import org.springframework.stereotype.Service;

import java.io.IOException;

@Service
public class PubSubPublisherService {

    private final ObjectMapper objectMapper;
    private final Publisher publisher;

    public PubSubPublisherService(GcpProperties gcpProperties, ObjectMapper objectMapper) throws IOException {
        this.objectMapper = objectMapper;
        TopicName topicName = TopicName.of(gcpProperties.projectId(), gcpProperties.pubsubTopic());
        this.publisher = Publisher.newBuilder(topicName).build();
    }

    public String publish(Transaction transaction) throws Exception {
        byte[] payload = objectMapper.writeValueAsBytes(transaction);
        PubsubMessage message = PubsubMessage.newBuilder()
                .setData(ByteString.copyFrom(payload))
                .build();
        ApiFuture<String> future = publisher.publish(message);
        return future.get();
    }

    @PreDestroy
    public void shutdown() throws InterruptedException {
        publisher.shutdown();
        publisher.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS);
    }
}
