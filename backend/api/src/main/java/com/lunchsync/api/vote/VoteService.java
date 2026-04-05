package com.lunchsync.api.vote;

import com.lunchsync.api.profile.UserProfileEntity;
import com.lunchsync.api.profile.UserProfileRepository;
import com.lunchsync.api.session.LunchSessionRepository;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class VoteService {

    private final VoteRepository voteRepository;
    private final LunchSessionRepository lunchSessionRepository;
    private final UserProfileRepository userProfileRepository;

    public VoteService(VoteRepository voteRepository, LunchSessionRepository lunchSessionRepository, UserProfileRepository userProfileRepository) {
        this.voteRepository = voteRepository;
        this.lunchSessionRepository = lunchSessionRepository;
        this.userProfileRepository = userProfileRepository;
    }

    public VoteDto.VoteResponse vote(VoteDto.VoteRequest request) {
        lunchSessionRepository.findById(request.sessionId())
                .orElseThrow(() -> new EntityNotFoundException("Session not found"));
        userProfileRepository.findById(request.userId())
                .orElseGet(() -> userProfileRepository.save(UserProfileEntity.placeholder(request.userId())));

        VoteEntity entity = new VoteEntity();
        entity.setSessionId(request.sessionId());
        entity.setUserId(request.userId());
        entity.setRestaurantId(request.restaurantId());
        VoteEntity saved = voteRepository.save(entity);

        return new VoteDto.VoteResponse(saved.getId(), "RECORDED");
    }
}
