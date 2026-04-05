package com.lunchsync.api.profile;

import org.springframework.data.jpa.repository.JpaRepository;

public interface UserProfileRepository extends JpaRepository<UserProfileEntity, Long> {
}
