package com.lunchsync.api.profile;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

public class ProfileDto {

    public record ProfileResponse(
            Long userId,
            String displayName,
            String email,
            String affiliation,
            Integer defaultRadiusMeters,
            Integer defaultBudget,
            String lunchTime,
            List<String> preferences,
            List<String> allergies
    ) {
    }

    public record UpdateProfileRequest(
            @NotBlank String displayName,
            String affiliation,
            @Min(100) Integer defaultRadiusMeters,
            @Min(1000) Integer defaultBudget,
            String lunchTime,
            List<String> preferences,
            List<String> allergies
    ) {
    }
}
