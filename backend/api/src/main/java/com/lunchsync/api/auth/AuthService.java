package com.lunchsync.api.auth;

import com.lunchsync.api.profile.UserProfileEntity;
import com.lunchsync.api.profile.UserProfileRepository;
import org.springframework.stereotype.Service;

@Service
public class AuthService {

    private final UserProfileRepository userProfileRepository;

    public AuthService(UserProfileRepository userProfileRepository) {
        this.userProfileRepository = userProfileRepository;
    }

    public AuthDto.MockLoginResponse mockLogin(AuthDto.MockLoginRequest request) {
        UserProfileEntity user = userProfileRepository.findAll().stream()
                .filter(entity -> request.email().equalsIgnoreCase(entity.getEmail()))
                .findFirst()
                .orElseGet(UserProfileEntity::new);

        if (user.getId() == null) {
            long nextId = userProfileRepository.count() + 1;
            user.setId(nextId);
        }
        user.setDisplayName(request.displayName());
        user.setEmail(request.email());
        UserProfileEntity saved = userProfileRepository.save(user);

        return new AuthDto.MockLoginResponse(
                saved.getId(),
                saved.getDisplayName(),
                "mock-token-user-" + saved.getId()
        );
    }
}
