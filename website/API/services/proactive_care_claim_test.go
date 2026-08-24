package services

import (
	"errors"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
)

func TestProactiveCareClaimEnforcesDailyLimitAndRelease(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() { _ = database.Get().Close() })
	user := models.User{Username: "proactive", Status: 1}
	if err := database.Get().Register("User").Insert(&user); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	agent := models.UserAgent{
		UserID: user.ID, ClientID: "agent-1", Name: "A",
		RealInfoEnabled: true, ProactiveCareEnabled: true,
		ProactiveCareDailyLimit: 1,
	}
	if err := database.Get().Register("UserAgent").Insert(&agent); err != nil {
		t.Fatalf("insert agent: %v", err)
	}

	claim, err := ClaimProactiveCare(user.ID, agent.ClientID)
	if err != nil {
		t.Fatalf("claim: %v", err)
	}
	if _, err := ClaimProactiveCare(user.ID, agent.ClientID); !errors.Is(err, ErrProactiveDailyLimit) {
		t.Fatalf("second claim = %v, want daily limit", err)
	}
	if err := ReleaseProactiveCare(claim.ClaimToken); err != nil {
		t.Fatalf("release: %v", err)
	}
	if _, err := ClaimProactiveCare(user.ID, agent.ClientID); err != nil {
		t.Fatalf("claim after release: %v", err)
	}
}
