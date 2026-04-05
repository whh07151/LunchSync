package com.lunchsync.api.decision;

import com.lunchsync.api.common.SessionStatus;
import com.lunchsync.api.session.LunchSessionEntity;
import com.lunchsync.api.session.LunchSessionRepository;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
public class DecisionService {

    private static final Map<Long, String> NAMES = Map.of(
            101L, "Seoul Kitchen",
            102L, "Tokyo Bento",
            103L, "Green Bowl"
    );

    private final RestaurantDecisionRepository restaurantDecisionRepository;
    private final LunchSessionRepository lunchSessionRepository;

    public DecisionService(RestaurantDecisionRepository restaurantDecisionRepository, LunchSessionRepository lunchSessionRepository) {
        this.restaurantDecisionRepository = restaurantDecisionRepository;
        this.lunchSessionRepository = lunchSessionRepository;
    }

    public DecisionDto.DecisionResponse confirm(DecisionDto.DecisionRequest request) {
        LunchSessionEntity session = lunchSessionRepository.findById(request.sessionId())
                .orElseThrow(() -> new EntityNotFoundException("Session not found"));

        RestaurantDecisionEntity entity = new RestaurantDecisionEntity();
        entity.setSessionId(request.sessionId());
        entity.setRestaurantId(request.restaurantId());
        entity.setRestaurantName(NAMES.getOrDefault(request.restaurantId(), "Restaurant-" + request.restaurantId()));
        entity.setStatus("CONFIRMED");
        RestaurantDecisionEntity saved = restaurantDecisionRepository.save(entity);

        session.setStatus(SessionStatus.RESTAURANT_CONFIRMED);
        lunchSessionRepository.save(session);

        return new DecisionDto.DecisionResponse(
                saved.getSessionId(),
                saved.getRestaurantId(),
                saved.getRestaurantName(),
                saved.getStatus()
        );
    }
}
