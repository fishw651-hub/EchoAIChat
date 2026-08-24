package services

import (
	"errors"
	"fmt"
	"sort"
	"strconv"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/google/uuid"
)

var ErrReservationFinalized = errors.New("配额预留已完成")

var featureQuotaLocks = utils.NewStripedLock()

// ReserveFeatureQuota atomically marks one real_reply unit as pending.
func ReserveFeatureQuota(userID uint, quotaType string) (*models.FeatureQuotaReservation, error) {
	if userID == 0 || quotaType != "real_reply" {
		return nil, fmt.Errorf("不支持的功能配额")
	}
	unlock := featureQuotaLocks.LockUint(userID)
	defer unlock()

	user, err := FindUserByID(userID)
	if err != nil || user == nil || user.Status != 1 {
		return nil, fmt.Errorf("用户不可用")
	}
	active := ActiveSubscriptionsForUser(userID)
	sort.Slice(active, func(i, j int) bool { return active[i].ExpiresAt < active[j].ExpiresAt })
	choice := uint(0)
	limit := 0
	unlimited := false
	if len(active) > 0 {
		for _, sub := range active {
			plan, _ := FindSubscriptionPlanByID(sub.PlanID)
			if plan == nil {
				continue
			}
			if plan.RealReplyDailyQuota == -1 {
				choice, unlimited = sub.ID, true
				break
			}
			if plan.RealReplyDailyQuota > 0 && sub.RealReplyUsedToday < plan.RealReplyDailyQuota {
				choice, limit = sub.ID, plan.RealReplyDailyQuota
				break
			}
		}
	} else {
		limit = defaultRealReplyQuota()
	}
	if choice == 0 && !unlimited && limit == 0 {
		return nil, &FeatureQuotaExceededError{}
	}

	reservation := &models.FeatureQuotaReservation{
		ReservationID:  uuid.NewString(),
		UserID:         userID,
		QuotaType:      quotaType,
		SubscriptionID: choice,
		Status:         "pending",
		CreatedAt:      time.Now().UTC(),
	}
	err = database.Get().WithTx(nil, func(tx *database.Tx) error {
		var current models.User
		found, err := tx.FindByID("User", userID, &current)
		if err != nil || !found || current.Status != 1 {
			return fmt.Errorf("用户不可用")
		}
		if current.QuotaResetDate != utils.TodayCN() {
			current.RealReplyUsedToday = 0
			current.QuotaResetDate = utils.TodayCN()
		}
		if choice == 0 {
			if !unlimited && current.RealReplyUsedToday >= limit {
				return &FeatureQuotaExceededError{}
			}
			current.RealReplyUsedToday++
		} else {
			var sub models.UserSubscription
			found, err = tx.FindByID("UserSubscription", choice, &sub)
			if err != nil || !found {
				return fmt.Errorf("订阅不存在")
			}
			if sub.QuotaResetDate != utils.TodayCN() {
				sub.RealReplyUsedToday = 0
				sub.QuotaResetDate = utils.TodayCN()
			}
			if !unlimited && sub.RealReplyUsedToday >= limit {
				return &FeatureQuotaExceededError{}
			}
			sub.RealReplyUsedToday++
			if err := tx.Replace("UserSubscription", sub.ID, &sub); err != nil {
				return err
			}
			current.RealReplyUsedToday++
		}
		if err := tx.Replace("User", current.ID, &current); err != nil {
			return err
		}
		return tx.Insert("FeatureQuotaReservation", reservation)
	})
	if err != nil {
		return nil, err
	}
	PublishQuotaChanged(userID)
	return reservation, nil
}

func CommitFeatureQuota(reservationID string) error {
	return finalizeFeatureQuota(reservationID, false)
}

func ReleaseFeatureQuota(reservationID string) error {
	return finalizeFeatureQuota(reservationID, true)
}

func finalizeFeatureQuota(reservationID string, release bool) error {
	var reservation models.FeatureQuotaReservation
	if !database.Get().Register("FeatureQuotaReservation").FindOne(
		database.FilterEq("ReservationID", reservationID), &reservation,
	) {
		return fmt.Errorf("配额预留不存在")
	}
	unlock := featureQuotaLocks.LockUint(reservation.UserID)
	defer unlock()
	err := database.Get().WithTx(nil, func(tx *database.Tx) error {
		found, err := tx.FindOne("FeatureQuotaReservation", database.FilterEq("ReservationID", reservationID), &reservation)
		if err != nil || !found {
			return fmt.Errorf("配额预留不存在")
		}
		if reservation.Status != "pending" {
			return ErrReservationFinalized
		}
		if release {
			var user models.User
			found, err = tx.FindByID("User", reservation.UserID, &user)
			if err != nil || !found {
				return fmt.Errorf("用户不存在")
			}
			if user.RealReplyUsedToday > 0 {
				user.RealReplyUsedToday--
			}
			if reservation.SubscriptionID != 0 {
				var sub models.UserSubscription
				if found, err = tx.FindByID("UserSubscription", reservation.SubscriptionID, &sub); err != nil || !found {
					return fmt.Errorf("订阅不存在")
				}
				if sub.RealReplyUsedToday > 0 {
					sub.RealReplyUsedToday--
				}
				if err := tx.Replace("UserSubscription", sub.ID, &sub); err != nil {
					return err
				}
			}
			if err := tx.Replace("User", user.ID, &user); err != nil {
				return err
			}
		}
		now := time.Now().UTC()
		reservation.Status = "released"
		if !release {
			reservation.Status = "committed"
		}
		reservation.FinalizedAt = &now
		return tx.Replace("FeatureQuotaReservation", reservation.ID, &reservation)
	})
	if err == nil {
		PublishQuotaChanged(reservation.UserID)
	}
	return err
}

type FeatureQuotaExceededError struct{}

func (FeatureQuotaExceededError) Error() string { return "今日真实回复配额已用完" }

func defaultRealReplyQuota() int {
	if config, err := FindSystemConfig("default_real_reply_daily_quota"); err == nil && config != nil {
		if value, err := strconv.Atoi(config.Value); err == nil && value >= 0 {
			return value
		}
	}
	return 30
}
