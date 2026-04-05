package com.lunchsync.api.session;

import org.springframework.data.jpa.repository.JpaRepository;

public interface LunchSessionRepository extends JpaRepository<LunchSessionEntity, Long> {
}
