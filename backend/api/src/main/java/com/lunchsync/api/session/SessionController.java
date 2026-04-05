package com.lunchsync.api.session;

import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/sessions")
public class SessionController {

    private final SessionService sessionService;

    public SessionController(SessionService sessionService) {
        this.sessionService = sessionService;
    }

    @PostMapping
    public SessionDto.CreateSessionResponse create(@Valid @RequestBody SessionDto.CreateSessionRequest request) {
        return sessionService.create(request);
    }

    @GetMapping("/{sessionId}")
    public SessionDto.SessionDetailResponse get(@PathVariable Long sessionId) {
        return sessionService.get(sessionId);
    }
}
