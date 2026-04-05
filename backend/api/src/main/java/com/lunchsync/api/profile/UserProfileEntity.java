package com.lunchsync.api.profile;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;

@Entity
@Table(name = "user_profiles")
public class UserProfileEntity {

    @Id
    private Long id;

    @Column(nullable = false)
    private String displayName;

    @Column(nullable = false)
    private String email;

    private String affiliation;

    private Integer defaultRadiusMeters;

    private Integer defaultBudget;

    private String lunchTime;

    @Lob
    private String preferences;

    @Lob
    private String allergies;

    public static UserProfileEntity placeholder(Long id) {
        UserProfileEntity entity = new UserProfileEntity();
        entity.id = id;
        entity.displayName = "guest-" + id;
        entity.email = "guest" + id + "@example.com";
        entity.defaultRadiusMeters = 1000;
        entity.defaultBudget = 12000;
        entity.lunchTime = "12:00";
        entity.preferences = "";
        entity.allergies = "";
        return entity;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getAffiliation() { return affiliation; }
    public void setAffiliation(String affiliation) { this.affiliation = affiliation; }
    public Integer getDefaultRadiusMeters() { return defaultRadiusMeters; }
    public void setDefaultRadiusMeters(Integer defaultRadiusMeters) { this.defaultRadiusMeters = defaultRadiusMeters; }
    public Integer getDefaultBudget() { return defaultBudget; }
    public void setDefaultBudget(Integer defaultBudget) { this.defaultBudget = defaultBudget; }
    public String getLunchTime() { return lunchTime; }
    public void setLunchTime(String lunchTime) { this.lunchTime = lunchTime; }
    public String getPreferences() { return preferences; }
    public void setPreferences(String preferences) { this.preferences = preferences; }
    public String getAllergies() { return allergies; }
    public void setAllergies(String allergies) { this.allergies = allergies; }
}
