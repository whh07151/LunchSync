package com.lunchsync.api.invite;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public class InviteDto {

    public record CreateInviteRequest(@NotNull Long hostUserId, @NotBlank String targetName) {
    }

    public record CreateInviteResponse(Long inviteId, String inviteCode, String status) {
    }
}
