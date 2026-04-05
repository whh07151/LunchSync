package com.lunchsync.api.vote;

import org.springframework.data.jpa.repository.JpaRepository;

public interface VoteRepository extends JpaRepository<VoteEntity, Long> {
}
