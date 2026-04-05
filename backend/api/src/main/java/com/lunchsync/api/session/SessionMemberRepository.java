package com.lunchsync.api.session;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface SessionMemberRepository extends JpaRepository<SessionMemberEntity, Long> {
    List<SessionMemberEntity> findBySessionId(Long sessionId);
}
