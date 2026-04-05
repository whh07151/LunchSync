package com.lunchsync.api.invite;

import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class InviteService {

    private final InviteRepository inviteRepository;

    public InviteService(InviteRepository inviteRepository) {
        this.inviteRepository = inviteRepository;
    }

    public InviteDto.CreateInviteResponse create(InviteDto.CreateInviteRequest request) {
        InviteEntity entity = new InviteEntity();
        entity.setHostUserId(request.hostUserId());
        entity.setTargetName(request.targetName());
        entity.setInviteCode("INVITE-" + UUID.randomUUID().toString().substring(0, 6).toUpperCase());
        entity.setStatus("CREATED");

        InviteEntity saved = inviteRepository.save(entity);
        return new InviteDto.CreateInviteResponse(saved.getId(), saved.getInviteCode(), saved.getStatus());
    }
}
