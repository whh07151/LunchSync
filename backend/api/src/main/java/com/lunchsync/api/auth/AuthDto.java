package com.lunchsync.api.auth;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public class AuthDto {

    public record MockLoginRequest(@NotBlank String displayName, @Email @NotBlank String email) {
    }

    public record MockLoginResponse(Long userId, String displayName, String accessToken) {
    }
}
