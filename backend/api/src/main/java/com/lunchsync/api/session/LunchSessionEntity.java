package com.lunchsync.api.session;

import com.lunchsync.api.common.SessionStatus;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "lunch_sessions")
public class LunchSessionEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private Long hostUserId;
    private String title;
    private Integer radiusMeters;
    private Integer budget;
    private String targetTime;

    @Enumerated(EnumType.STRING)
    private SessionStatus status;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getHostUserId() { return hostUserId; }
    public void setHostUserId(Long hostUserId) { this.hostUserId = hostUserId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public Integer getRadiusMeters() { return radiusMeters; }
    public void setRadiusMeters(Integer radiusMeters) { this.radiusMeters = radiusMeters; }
    public Integer getBudget() { return budget; }
    public void setBudget(Integer budget) { this.budget = budget; }
    public String getTargetTime() { return targetTime; }
    public void setTargetTime(String targetTime) { this.targetTime = targetTime; }
    public SessionStatus getStatus() { return status; }
    public void setStatus(SessionStatus status) { this.status = status; }
}
