package services

import (
	"errors"
	"fmt"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/google/uuid"
)

var ErrProactiveClaimFinalized = errors.New("主动关心 claim 已完成")
var ErrProactiveDailyLimit = errors.New("主动关心今日次数已用完")

var proactiveClaimLocks = utils.NewStripedLock()

func FindProactiveCareClaim(userID uint, clientAgentID, claimToken string) (*models.ProactiveCareClaim, error) {
	if userID == 0 || clientAgentID == "" || claimToken == "" {
		return nil, ErrAgentNotOwned
	}
	var claim models.ProactiveCareClaim
	found, err := database.Get().Register("ProactiveCareClaim").FindOneE(database.FilterAnd(
		database.FilterAnd(database.FilterEq("UserID", userID), database.FilterEq("ClientAgentID", clientAgentID)),
		database.FilterEq("ClaimToken", claimToken),
	), &claim)
	if err != nil {
		return nil, err
	}
	if !found || claim.Status != "pending" {
		return nil, ErrProactiveClaimFinalized
	}
	return &claim, nil
}

func ClaimProactiveCare(userID uint, clientAgentID string) (*models.ProactiveCareClaim, error) {
	agent, err := RequireOwnedAgent(userID, clientAgentID)
	if err != nil || agent == nil || !agent.RealInfoEnabled || !agent.ProactiveCareEnabled {
		return nil, ErrAgentNotOwned
	}
	limit := agent.ProactiveCareDailyLimit
	if limit <= 0 {
		limit = 1
	}
	unlock := proactiveClaimLocks.Lock(fmt.Sprintf("%d:%s", userID, clientAgentID))
	defer unlock()

	var claims []models.ProactiveCareClaim
	database.Get().Register("ProactiveCareClaim").FindAll(&claims, database.FilterAnd(
		database.FilterAnd(database.FilterEq("UserID", userID), database.FilterEq("ClientAgentID", clientAgentID)),
		database.FilterDate("CreatedAt", utils.TodayCN()),
	), "CreatedAt asc", 0, 0)
	active := 0
	for _, claim := range claims {
		if claim.Status == "pending" || claim.Status == "committed" {
			active++
		}
	}
	if active >= limit {
		return nil, ErrProactiveDailyLimit
	}
	feature, err := ReserveFeatureQuota(userID, "real_reply")
	if err != nil {
		return nil, err
	}
	claim := &models.ProactiveCareClaim{
		ClaimToken:           uuid.NewString(),
		UserID:               userID,
		ClientAgentID:        clientAgentID,
		FeatureReservationID: feature.ReservationID,
		Status:               "pending",
		CreatedAt:            time.Now().UTC(),
	}
	if err := database.Get().Register("ProactiveCareClaim").Insert(claim); err != nil {
		_ = ReleaseFeatureQuota(feature.ReservationID)
		return nil, err
	}
	return claim, nil
}

func CommitProactiveCare(claimToken string) error {
	return finalizeProactiveCare(claimToken, false)
}

func ReleaseProactiveCare(claimToken string) error {
	return finalizeProactiveCare(claimToken, true)
}

func finalizeProactiveCare(claimToken string, release bool) error {
	var claim models.ProactiveCareClaim
	if !database.Get().Register("ProactiveCareClaim").FindOne(database.FilterEq("ClaimToken", claimToken), &claim) {
		return fmt.Errorf("主动关心 claim 不存在")
	}
	unlock := proactiveClaimLocks.Lock(fmt.Sprintf("%d:%s", claim.UserID, claim.ClientAgentID))
	defer unlock()
	err := database.Get().WithTx(nil, func(tx *database.Tx) error {
		found, err := tx.FindOne("ProactiveCareClaim", database.FilterEq("ClaimToken", claimToken), &claim)
		if err != nil || !found {
			return fmt.Errorf("主动关心 claim 不存在")
		}
		if claim.Status != "pending" {
			return ErrProactiveClaimFinalized
		}
		return nil
	})
	if err != nil {
		return err
	}
	if release {
		if err := ReleaseFeatureQuota(claim.FeatureReservationID); err != nil {
			return err
		}
	} else if err := CommitFeatureQuota(claim.FeatureReservationID); err != nil {
		return err
	}
	now := time.Now().UTC()
	claim.Status = "committed"
	if release {
		claim.Status = "released"
	}
	claim.FinalizedAt = &now
	return database.Get().Register("ProactiveCareClaim").UpdateWhere(
		database.FilterEq("ID", claim.ID),
		map[string]interface{}{"Status": claim.Status, "FinalizedAt": claim.FinalizedAt},
	)
}
