package com.lunchsync.api.decision;

import jakarta.validation.constraints.NotNull;

public class DecisionDto {

    public record DecisionRequest(@NotNull Long sessionId, @NotNull Long restaurantId) {
    }

    public record DecisionResponse(Long sessionId, Long restaurantId, String restaurantName, String status) {
    }
}
