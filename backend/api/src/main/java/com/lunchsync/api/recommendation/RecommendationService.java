package com.lunchsync.api.recommendation;

import com.lunchsync.api.common.SessionStatus;
import com.lunchsync.api.session.LunchSessionEntity;
import com.lunchsync.api.session.LunchSessionRepository;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class RecommendationService {

    private final LunchSessionRepository lunchSessionRepository;

    public RecommendationService(LunchSessionRepository lunchSessionRepository) {
        this.lunchSessionRepository = lunchSessionRepository;
    }

    public RecommendationDto.RecommendationResponse generate(RecommendationDto.RecommendationRequest request) {
        LunchSessionEntity session = lunchSessionRepository.findById(request.sessionId())
                .orElseThrow(() -> new EntityNotFoundException("Session not found"));
        session.setStatus(SessionStatus.RECOMMENDING);
        lunchSessionRepository.save(session);

        List<RecommendationDto.RestaurantRecommendation> data = List.of(
                new RecommendationDto.RestaurantRecommendation(101L, "Seoul Kitchen", "korean", 14000, 650,
                        "Matches group preference for Korean food and stays within budget."),
                new RecommendationDto.RestaurantRecommendation(102L, "Tokyo Bento", "japanese", 13000, 900,
                        "Good lunch set value, close enough for target lunch time."),
                new RecommendationDto.RestaurantRecommendation(103L, "Green Bowl", "healthy", 12000, 500,
                        "Closest option with lighter menu and fast service.")
        );

        session.setStatus(SessionStatus.VOTING);
        lunchSessionRepository.save(session);
        return new RecommendationDto.RecommendationResponse(session.getId(), data);
    }
}
