package com.lunchsync.api.profile;

import com.lunchsync.api.common.MockUserResolver;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/profile/me")
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    @GetMapping
    public ProfileDto.ProfileResponse me(
            @RequestHeader(value = MockUserResolver.HEADER_NAME, required = false) String mockUserId
    ) {
        return profileService.getMe(mockUserId);
    }

    @PutMapping
    public ProfileDto.ProfileResponse update(
            @RequestHeader(value = MockUserResolver.HEADER_NAME, required = false) String mockUserId,
            @Valid @org.springframework.web.bind.annotation.RequestBody ProfileDto.UpdateProfileRequest request
    ) {
        return profileService.updateMe(mockUserId, request);
    }
}
