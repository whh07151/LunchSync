package com.lunchsync.api.session;

import com.lunchsync.api.common.SessionStatus;
import com.lunchsync.api.decision.RestaurantDecisionEntity;
import com.lunchsync.api.decision.RestaurantDecisionRepository;
import com.lunchsync.api.profile.UserProfileEntity;
import com.lunchsync.api.profile.UserProfileRepository;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.List;

@Service
public class SessionService {

    private final LunchSessionRepository lunchSessionRepository;
    private final SessionMemberRepository sessionMemberRepository;
    private final UserProfileRepository userProfileRepository;
    private final RestaurantDecisionRepository restaurantDecisionRepository;

    public SessionService(
            LunchSessionRepository lunchSessionRepository,
            SessionMemberRepository sessionMemberRepository,
            UserProfileRepository userProfileRepository,
            RestaurantDecisionRepository restaurantDecisionRepository
    ) {
        this.lunchSessionRepository = lunchSessionRepository;
        this.sessionMemberRepository = sessionMemberRepository;
        this.userProfileRepository = userProfileRepository;
        this.restaurantDecisionRepository = restaurantDecisionRepository;
    }

    public SessionDto.CreateSessionResponse create(SessionDto.CreateSessionRequest request) {
        ensureUserExists(request.hostUserId());
        LunchSessionEntity entity = new LunchSessionEntity();
        entity.setHostUserId(request.hostUserId());
        entity.setTitle(request.title());
        entity.setRadiusMeters(request.radiusMeters());
        entity.setBudget(request.budget());
        entity.setTargetTime(request.targetTime());
        entity.setStatus(SessionStatus.CREATED);

        LunchSessionEntity saved = lunchSessionRepository.save(entity);
        for (Long memberUserId : request.memberUserIds()) {
            ensureUserExists(memberUserId);
            SessionMemberEntity member = new SessionMemberEntity();
            member.setSessionId(saved.getId());
            member.setUserId(memberUserId);
            sessionMemberRepository.save(member);
        }

        return new SessionDto.CreateSessionResponse(saved.getId(), saved.getStatus().name());
    }

    public SessionDto.SessionDetailResponse get(Long sessionId) {
        LunchSessionEntity session = lunchSessionRepository.findById(sessionId)
                .orElseThrow(() -> new EntityNotFoundException("Session not found"));
        List<SessionDto.SessionMemberResponse> members = sessionMemberRepository.findBySessionId(sessionId)
                .stream()
                .map(m -> new SessionDto.SessionMemberResponse(m.getUserId()))
                .toList();

        RestaurantDecisionEntity latestDecision = restaurantDecisionRepository.findBySessionId(sessionId).stream()
                .max(Comparator.comparing(RestaurantDecisionEntity::getId))
                .orElse(null);

        SessionDto.ConfirmedRestaurant confirmedRestaurant = latestDecision == null
                ? null
                : new SessionDto.ConfirmedRestaurant(latestDecision.getRestaurantId(), latestDecision.getRestaurantName());

        return new SessionDto.SessionDetailResponse(
                session.getId(),
                session.getHostUserId(),
                session.getTitle(),
                session.getRadiusMeters(),
                session.getBudget(),
                session.getTargetTime(),
                session.getStatus().name(),
                members,
                confirmedRestaurant
        );
    }

    private void ensureUserExists(Long userId) {
        userProfileRepository.findById(userId)
                .orElseGet(() -> userProfileRepository.save(UserProfileEntity.placeholder(userId)));
    }
}
