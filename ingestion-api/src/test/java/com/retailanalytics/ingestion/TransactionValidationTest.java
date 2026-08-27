package com.retailanalytics.ingestion;

import com.retailanalytics.ingestion.model.Transaction;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TransactionValidationTest {

    private final Validator validator;

    TransactionValidationTest() {
        ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
        this.validator = factory.getValidator();
    }

    @Test
    void validTransactionHasNoViolations() {
        Transaction transaction = new Transaction(
                "txn-1", "STORE_0001", "SKU_0001", "Beverages", 2, 3.5, Instant.now());
        Set<ConstraintViolation<Transaction>> violations = validator.validate(transaction);
        assertTrue(violations.isEmpty());
    }

    @Test
    void nonPositiveQuantityIsRejected() {
        Transaction transaction = new Transaction(
                "txn-2", "STORE_0001", "SKU_0001", "Beverages", 0, 3.5, Instant.now());
        Set<ConstraintViolation<Transaction>> violations = validator.validate(transaction);
        assertEquals(1, violations.size());
    }
}
