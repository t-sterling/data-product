package com.example.dataproducts.customers;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class CustomersDataProductTest {
    @Test
    void reportsItsName() {
        assertEquals("customers", new CustomersDataProduct().name());
    }
}
