package com.lunchsync.api.invite;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "invites")
public class InviteEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private Long hostUserId;
    private String targetName;
    private String inviteCode;
    private String status;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getHostUserId() { return hostUserId; }
    public void setHostUserId(Long hostUserId) { this.hostUserId = hostUserId; }
    public String getTargetName() { return targetName; }
    public void setTargetName(String targetName) { this.targetName = targetName; }
    public String getInviteCode() { return inviteCode; }
    public void setInviteCode(String inviteCode) { this.inviteCode = inviteCode; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
}
