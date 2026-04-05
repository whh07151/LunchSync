package com.lunchsync.api.profile;

import com.lunchsync.api.common.MockUserResolver;
import org.springframework.stereotype.Service;

import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class ProfileService {

    private final MockUserResolver mockUserResolver;
    private final UserProfileRepository userProfileRepository;

    public ProfileService(MockUserResolver mockUserResolver, UserProfileRepository userProfileRepository) {
        this.mockUserResolver = mockUserResolver;
        this.userProfileRepository = userProfileRepository;
    }

    public ProfileDto.ProfileResponse getMe(String headerUserId) {
        UserProfileEntity user = mockUserResolver.resolveOrCreate(headerUserId);
        return toResponse(user);
    }

    public ProfileDto.ProfileResponse updateMe(String headerUserId, ProfileDto.UpdateProfileRequest request) {
        UserProfileEntity user = mockUserResolver.resolveOrCreate(headerUserId);
        user.setDisplayName(request.displayName());
        user.setAffiliation(request.affiliation());
        user.setDefaultRadiusMeters(request.defaultRadiusMeters());
        user.setDefaultBudget(request.defaultBudget());
        user.setLunchTime(request.lunchTime());
        user.setPreferences(joinList(request.preferences()));
        user.setAllergies(joinList(request.allergies()));

        UserProfileEntity saved = userProfileRepository.save(user);
        return toResponse(saved);
    }

    private ProfileDto.ProfileResponse toResponse(UserProfileEntity user) {
        return new ProfileDto.ProfileResponse(
                user.getId(),
                user.getDisplayName(),
                user.getEmail(),
                user.getAffiliation(),
                user.getDefaultRadiusMeters(),
                user.getDefaultBudget(),
                user.getLunchTime(),
                splitList(user.getPreferences()),
                splitList(user.getAllergies())
        );
    }

    private String joinList(List<String> values) {
        if (values == null || values.isEmpty()) {
            return "";
        }
        return String.join(",", values);
    }

    private List<String> splitList(String value) {
        if (value == null || value.isBlank()) {
            return List.of();
        }
        return Arrays.stream(value.split(",")).map(String::trim).filter(s -> !s.isEmpty()).collect(Collectors.toList());
    }
}
