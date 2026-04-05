package com.lunchsync.api.session;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.util.List;

public class SessionDto {

    public record CreateSessionRequest(
            @NotNull Long hostUserId,
            @NotBlank String title,
            @Min(100) Integer radiusMeters,
            @Min(1000) Integer budget,
            @NotBlank String targetTime,
            @NotEmpty List<Long> memberUserIds
    ) {
    }

    public record CreateSessionResponse(Long sessionId, String status) {
    }

    public record SessionMemberResponse(Long userId) {
    }

    public record SessionDetailResponse(
            Long sessionId,
            Long hostUserId,
            String title,
            Integer radiusMeters,
            Integer budget,
            String targetTime,
            String status,
            List<SessionMemberResponse> members,
            ConfirmedRestaurant confirmedRestaurant
    ) {
    }

    public record ConfirmedRestaurant(Long restaurantId, String restaurantName) {
    }
}
