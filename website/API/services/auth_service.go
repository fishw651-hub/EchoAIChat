package services

import (
	"errors"
	"time"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"golang.org/x/crypto/bcrypt"
)

type AuthService struct{}

// 哨兵错误：service 层无 gin.Context，无法直接翻译，改为导出的哨兵变量，
// handler 通过 errors.Is 判定后用 utils.T() 翻译为当前请求语言。
var (
	ErrAuthUserTaken            = errors.New("err.auth.register_taken")
	ErrAuthBcryptFailed         = errors.New("err.auth.bcrypt_failed")
	ErrAuthRegisterFailed       = errors.New("err.auth.register_failed")
	ErrAuthWrongCredentials     = errors.New("err.auth.wrong_credentials")
	ErrAuthAccountBanned        = errors.New("err.auth.account_banned")
	ErrAuthGenerateTokenFailed  = errors.New("err.auth.generate_token_short")
	ErrAuthUserNotFound         = errors.New("err.auth.user_not_found_short")
	ErrAuthOldPasswordWrong     = errors.New("err.auth.old_password_wrong")
)

func (s *AuthService) Register(username, email, password string) (*models.User, error) {
	db := database.Get()
	users := db.Register("User")

	var existing models.User
	if users.FindOne(database.FilterEq("Username", username), &existing) {
		return nil, ErrAuthUserTaken
	}
	if email != "" && users.FindOne(database.FilterEq("Email", email), &existing) {
		return nil, ErrAuthUserTaken
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), 12)
	if err != nil {
		return nil, ErrAuthBcryptFailed
	}

	// 新人奖励：一次性给到账户余额（从 SystemConfig 读取，默认 1.00）
	user := models.User{
		Username:       username,
		Email:          email,
		PasswordHash:   string(hash),
		Nickname:       username,
		Role:           "user",
		Status:         1,
		Balance:        0,
		QuotaResetDate: utils.TodayCN(),
	}

	if err := users.Insert(&user); err != nil {
		return nil, ErrAuthRegisterFailed
	}

	return &user, nil
}

// / 新人奖励金额（一次性给到账户余额，非每日配额）
func (s *AuthService) Login(username, password, ip string) (*models.User, string, error) {
	db := database.Get()
	users := db.Register("User")

	var user models.User
	if !users.FindOne(database.FilterEq("Username", username), &user) {
		return nil, "", ErrAuthWrongCredentials
	}

	if user.Status != 1 {
		return nil, "", ErrAuthAccountBanned
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, "", ErrAuthWrongCredentials
	}

	token, err := utils.GenerateToken(user.ID, user.Role, user.TokenVersion)
	if err != nil {
		return nil, "", ErrAuthGenerateTokenFailed
	}

	now := time.Now()
	users.UpdateWhere(database.FilterEq("ID", user.ID), map[string]interface{}{
		"LastLoginAt": now.Format(time.RFC3339),
		"LastLoginIP": ip,
	})

	return &user, token, nil
}

func (s *AuthService) ChangePassword(userID uint, oldPassword, newPassword string) error {
	users := database.Get().Register("User")

	var user models.User
	if !users.FindByID(userID, &user) {
		return ErrAuthUserNotFound
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(oldPassword)); err != nil {
		return ErrAuthOldPasswordWrong
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), 12)
	if err != nil {
		return ErrAuthBcryptFailed
	}

	users.UpdateWhere(database.FilterEq("ID", userID), map[string]interface{}{
		"PasswordHash": string(hash),
		// 递增令牌版本：改密后所有已签发 token 立即失效，把攻击者踢出去
		"TokenVersion": user.TokenVersion + 1,
	})
	return nil
}

func GetUserByID(userID uint) (*models.User, error) {
	var user models.User
	if !database.Get().Register("User").FindByID(userID, &user) {
		return nil, ErrAuthUserNotFound
	}
	return &user, nil
}

func GetUserBalanceTiers(user *models.User) (freeLeft, subLeft, balance float64) {
	db := database.Get()
	today := utils.TodayCN()
	users := db.Register("User")

	if user.QuotaResetDate != today {
		updates := map[string]interface{}{
			"DailyQuotaUsed":        0,
			"SubscriptionQuotaUsed": 0,
			"QuotaResetDate":        today,
		}
		user.DailyQuotaUsed = 0
		user.SubscriptionQuotaUsed = 0
		user.QuotaResetDate = today
		if user.DailyAllowanceDate != today {
			updates["DailyCheckInBonus"] = 0.0
			user.DailyCheckInBonus = 0
		}
		users.UpdateWhere(database.FilterEq("ID", user.ID), updates)
	}

	subTotal := getSubscriptionDailyQuota(user.ID)

	subLeft = subTotal - user.SubscriptionQuotaUsed
	if subLeft < 0 {
		subLeft = 0
	}
	if subTotal > 0 {
		freeLeft = 0
	} else {
		freeLeft = user.DailyCheckInBonus - user.DailyQuotaUsed
		if freeLeft < 0 {
			freeLeft = 0
		}
	}
	balance = 0

	return
}

func GetUserBalanceTiersReadonly(user *models.User, isNewDay bool) (freeTotal, freeLeft, subTotal, subLeft, balance float64) {
	subTotal = getSubscriptionDailyQuota(user.ID)
	freeTotal, freeLeft, subLeft, balance = balanceTiersReadonly(user, isNewDay, subTotal)
	return
}

// SubscriptionDailyQuotaMap 一次性加载全部订阅并按用户聚合当日配额，
// 供 ListUsers 等批量场景使用（逐用户调 getSubscriptionDailyQuota 是 N+1 全表扫）
func SubscriptionDailyQuotaMap() map[uint]float64 {
	today := utils.TodayCN()
	var subs []models.UserSubscription
	database.Get().Register("UserSubscription").FindAll(&subs, nil, "", 0, 0)
	result := make(map[uint]float64)
	for _, sub := range subs {
		if sub.Status == 1 && sub.ExpiresAt >= today {
			result[sub.UserID] += sub.DailyQuota
		}
	}
	return result
}

// GetUserBalanceTiersReadonlyWithQuota 批量版只读分层余额：subTotal 由调用方
// 从 SubscriptionDailyQuotaMap 预聚合结果提供，避免循环内全表扫订阅表
func GetUserBalanceTiersReadonlyWithQuota(user *models.User, isNewDay bool, subTotal float64) (freeTotal, freeLeft, subLeft, balance float64) {
	return balanceTiersReadonly(user, isNewDay, subTotal)
}

func balanceTiersReadonly(user *models.User, isNewDay bool, subTotal float64) (freeTotal, freeLeft, subLeft, balance float64) {
	used := user.DailyQuotaUsed
	bonus := user.DailyCheckInBonus
	subUsed := user.SubscriptionQuotaUsed
	if isNewDay {
		used = 0
		bonus = 0
		subUsed = 0
	}

	subLeft = subTotal - subUsed
	if subLeft < 0 {
		subLeft = 0
	}
	if subTotal > 0 {
		freeTotal = 0
		freeLeft = 0
	} else {
		freeTotal = bonus
		freeLeft = bonus - used
		if freeLeft < 0 {
			freeLeft = 0
		}
	}
	balance = 0

	return
}

func GetUserDailyQuota(user *models.User) float64 {
	db := database.Get()
	today := utils.TodayCN()
	users := db.Register("User")

	if user.QuotaResetDate != today {
		updates := map[string]interface{}{
			"DailyQuotaUsed":        0,
			"SubscriptionQuotaUsed": 0,
			"QuotaResetDate":        today,
		}
		user.DailyQuotaUsed = 0
		user.SubscriptionQuotaUsed = 0
		user.QuotaResetDate = today
		if user.DailyAllowanceDate != today {
			updates["DailyCheckInBonus"] = 0.0
			user.DailyCheckInBonus = 0
		}
		users.UpdateWhere(database.FilterEq("ID", user.ID), updates)
	}

	subTotal := getSubscriptionDailyQuota(user.ID)
	var r float64
	if subTotal > 0 {
		r = subTotal - user.SubscriptionQuotaUsed
	} else {
		r = user.DailyCheckInBonus - user.DailyQuotaUsed
	}
	if r < 0 {
		r = 0
	}
	return r
}

func getSubscriptionDailyQuota(userID uint) float64 {
	sum := 0.0
	for _, sub := range ActiveSubscriptionsForUser(userID) {
		sum += sub.DailyQuota
	}
	return sum
}
