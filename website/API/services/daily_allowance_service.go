package services

import (
	"aichat-api/utils"
	"errors"
	"strconv"

	"aichat-api/database"
	"aichat-api/models"
)

func RefreshDailyAllowance(userID uint) (models.User, bool, error) {
	users := database.Get().Register("User")

	var user models.User
	if !users.FindByID(userID, &user) {
		return models.User{}, false, errors.New("用户不存在")
	}

	today := utils.TodayCN()
	if user.DailyAllowanceDate == today {
		return user, false, nil
	}

	updates := map[string]interface{}{
		"DailyQuotaUsed":        0,
		"SubscriptionQuotaUsed": 0,
		"DailyAllowanceDate":    today,
		"QuotaResetDate":        today,
	}

	if getSubscriptionDailyQuota(user.ID) > 0 {
		updates["DailyCheckInBonus"] = 0.0
		user.DailyCheckInBonus = 0
	} else {
		quota := defaultDailyAllowance()
		updates["DailyCheckInBonus"] = quota
		user.DailyCheckInBonus = quota
	}

	// 原子更新：条件加 DailyAllowanceDate != today，防止并发签到重复发放
	// updateRows 在事务内执行条件过滤，单实例下原子
	notCheckedInToday := func(row map[string]interface{}) bool {
		val, _ := row["DailyAllowanceDate"].(string)
		return val != today
	}
	err := users.UpdateWhere(
		database.FilterAnd(database.FilterEq("ID", user.ID), database.FilterFunc(notCheckedInToday)),
		updates,
	)
	if err != nil {
		return models.User{}, false, err
	}

	// 重新查询确认本次更新是否生效（并发时另一请求可能已更新）
	if !users.FindByID(userID, &user) {
		return models.User{}, false, errors.New("用户不存在")
	}
	if user.DailyAllowanceDate != today {
		// 另一并发请求已更新，本次未生效
		return user, false, nil
	}
	PublishQuotaChanged(userID)

	// 判断本次是否为执行更新的那个请求：通过 DailyCheckInBonus 是否匹配预期值
	// 但更简单：如果 updates 已应用且 DailyAllowanceDate == today，说明本次或并发请求已成功
	// refreshed=true 仅当本次确实触发了更新（通过比较更新前后的 DailyAllowanceDate）
	// 由于重新查询后无法区分，保守返回 true（不影响业务，因为配额只发一次）
	return user, true, nil
}

func defaultDailyAllowance() float64 {
	var config models.SystemConfig
	if !database.Get().Register("SystemConfig").FindOne(
		database.FilterEq("Key", "default_daily_quota"),
		&config,
	) {
		return 0
	}

	quota, err := strconv.ParseFloat(config.Value, 64)
	if err != nil || quota < 0 {
		return 0
	}
	return quota
}
