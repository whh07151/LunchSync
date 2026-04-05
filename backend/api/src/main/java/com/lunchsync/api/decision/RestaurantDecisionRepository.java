package com.lunchsync.api.decision;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface RestaurantDecisionRepository extends JpaRepository<RestaurantDecisionEntity, Long> {
    List<RestaurantDecisionEntity> findBySessionId(Long sessionId);
}
