package com.lunchsync.api.recommendation;

import jakarta.validation.constraints.NotNull;

import java.util.List;

public class RecommendationDto {

    public record RecommendationRequest(@NotNull Long sessionId) {
    }

    public record RestaurantRecommendation(
            Long restaurantId,
            String restaurantName,
            String category,
            Integer estimatedPrice,
            Integer distanceMeters,
            String reasonSummary
    ) {
    }

    public record RecommendationResponse(Long sessionId, List<RestaurantRecommendation> recommendations) {
    }
}
