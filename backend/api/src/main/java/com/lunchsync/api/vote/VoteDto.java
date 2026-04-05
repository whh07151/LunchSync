package com.lunchsync.api.vote;

import jakarta.validation.constraints.NotNull;

public class VoteDto {

    public record VoteRequest(@NotNull Long sessionId, @NotNull Long userId, @NotNull Long restaurantId) {
    }

    public record VoteResponse(Long voteId, String status) {
    }
}
