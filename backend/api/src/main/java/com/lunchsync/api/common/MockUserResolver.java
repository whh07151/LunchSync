package com.lunchsync.api.common;

import com.lunchsync.api.profile.UserProfileEntity;
import com.lunchsync.api.profile.UserProfileRepository;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

@Component
public class MockUserResolver {

    public static final String HEADER_NAME = "X-Mock-User-Id";

    private final UserProfileRepository userProfileRepository;

    public MockUserResolver(UserProfileRepository userProfileRepository) {
        this.userProfileRepository = userProfileRepository;
    }

    public Long resolveUserId(String headerValue) {
        if (StringUtils.hasText(headerValue)) {
            try {
                return Long.parseLong(headerValue);
            } catch (NumberFormatException ignored) {
                // fallback below
            }
        }
        return 1L;
    }

    public UserProfileEntity resolveOrCreate(String headerValue) {
        Long userId = resolveUserId(headerValue);
        return userProfileRepository.findById(userId)
                .orElseGet(() -> userProfileRepository.save(UserProfileEntity.placeholder(userId)));
    }
}
