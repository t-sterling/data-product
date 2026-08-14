package com.example.dataproducts.orders;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OrdersDataProductTest {
    @Test
    void reportsItsName() {
        assertEquals("orders", new OrdersDataProduct().name());
    }
}
