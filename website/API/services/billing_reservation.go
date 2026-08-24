package services

import (
	"aichat-api/utils"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/google/uuid"
)

const (
	// MaxChatMessagesBytes 聊天请求 messages 内容字节数硬上限，超出拒绝（映射 HTTP 400）。
	// 防止超大上下文请求只通过 16K 的预留检查后白嫖上游 API。
	MaxChatMessagesBytes = 512 * 1024
	// chatBytesPerToken 按字节粗略估算 token 的除数（英文约 4 字节/token；
	// 中文 UTF-8 约 3 字节/字、1~1.5 token/字，估算偏低，作为预留下限可接受）。
	chatBytesPerToken = 4
	// minReserveInputTokens 输入 token 预留下限：消息很小时仍按 16K 输入预留。
	minReserveInputTokens = 16_384
	// imagePartTokenBytes 多模态消息中单个图片部分按固定字节计入估算
	// （图片 token 消耗约 1~2K；base64 原文不计入，避免误伤多图请求）。
	imagePartTokenBytes = 4 * 1024
)

// RequestTooLargeError 表示聊天请求 messages 超过服务端硬上限，调用方应映射为 HTTP 400。
type RequestTooLargeError struct {
	Bytes int
}

func (e *RequestTooLargeError) Error() string {
	return fmt.Sprintf("请求内容过大（%d 字节），超过上限 %d 字节", e.Bytes, MaxChatMessagesBytes)
}

// chatMessagesBytes 估算 messages 的内容字节数：字符串 content 直接计长，
// 数组型（多模态）content 逐部分统计，图片部分按固定字节计。
func chatMessagesBytes(messages []ChatMessage) int {
	total := 0
	for _, m := range messages {
		switch content := m.Content.(type) {
		case nil:
		case string:
			total += len(content)
		default:
			total += contentPartsBytes(content)
		}
	}
	return total
}

func contentPartsBytes(content interface{}) int {
	parts, ok := content.([]interface{})
	if !ok {
		if b, err := json.Marshal(content); err == nil {
			return len(b)
		}
		return 0
	}
	total := 0
	for _, part := range parts {
		m, ok := part.(map[string]interface{})
		if !ok {
			if b, err := json.Marshal(part); err == nil {
				total += len(b)
			}
			continue
		}
		if typ, _ := m["type"].(string); typ == "image_url" {
			total += imagePartTokenBytes
			continue
		}
		if text, ok := m["text"].(string); ok {
			total += len(text)
			continue
		}
		if b, err := json.Marshal(part); err == nil {
			total += len(b)
		}
	}
	return total
}

type BillingReservation struct {
	ID           string
	ReservedCost float64
}

type billingReservationRecord struct {
	ID              uint
	ReservationID   string
	UserID          uint
	ReservedCost    float64
	PricingPeriod   string
	PriceMultiplier float64
	QuotaType       string
	Status          string
	CreatedAt       time.Time
	SettledAt       *time.Time
}

// reservationLocks 分片锁（固定 256 桶、内存有界）：同一用户哈希到同一桶，
// Reserve/Settle/Release 的检查-扣减区间仍按用户串行
var reservationLocks = utils.NewStripedLock()

func lockReservationUser(userID uint) func() {
	return reservationLocks.LockUint(userID)
}

func (s *BillingService) Reserve(userID uint, modelID string, messages []ChatMessage, maxTokens int, thinkingEnabled bool) (*BillingReservation, error) {
	if maxTokens <= 0 {
		maxTokens = 1024
	}
	if maxTokens > 8192 {
		maxTokens = 8192
	}

	messagesBytes := chatMessagesBytes(messages)
	if messagesBytes > MaxChatMessagesBytes {
		return nil, &RequestTooLargeError{Bytes: messagesBytes}
	}
	// 按消息实际大小估算输入 token（字节数/4 粗估），低于 16K 时仍按 16K 预留。
	// 固定 16K 预留会让 100K+ token 的上下文只通过 16K 的配额检查。
	inputTokens := messagesBytes / chatBytesPerToken
	if inputTokens < minReserveInputTokens {
		inputTokens = minReserveInputTokens
	}
	reservedCost, pricingPeriod, priceMultiplier, err := s.CalculateCostWithTimeOfUse(modelID, inputTokens, 0, inputTokens, maxTokens, thinkingEnabled, time.Now())
	if err != nil {
		return nil, err
	}
	if reservedCost <= 0 {
		return nil, fmt.Errorf("模型 %s 无法计算预留费用", modelID)
	}

	unlock := lockReservationUser(userID)
	defer unlock()

	// 订阅查询保持在事务外执行：数据库层写事务（WithTx）全程持有写锁，
	// 事务回调内只允许使用回调暴露的 tx 做读写，避免在持锁期间嵌套走全局句柄。
	subTotal := getSubscriptionQuotaTotal(userID)
	canUseSub := modelInUserSubscription(userID, modelID, thinkingEnabled)

	reservation := &BillingReservation{ID: uuid.NewString(), ReservedCost: reservedCost}
	err = database.Get().WithTx(nil, func(tx *database.Tx) error {
		var user models.User
		found, err := tx.FindByID("User", userID, &user)
		if err != nil {
			return err
		}
		if !found || user.Status != 1 {
			return fmt.Errorf("用户不可用")
		}

		today := utils.TodayCN()
		if user.QuotaResetDate != today {
			user.DailyQuotaUsed = 0
			user.SubscriptionQuotaUsed = 0
			user.QuotaResetDate = today
			if user.DailyAllowanceDate != today {
				user.DailyCheckInBonus = 0
			}
		}

		record := billingReservationRecord{
			ReservationID:   reservation.ID,
			UserID:          userID,
			ReservedCost:    reservedCost,
			PricingPeriod:   pricingPeriod,
			PriceMultiplier: priceMultiplier,
			Status:          "pending",
			CreatedAt:       time.Now().UTC(),
		}
		if subTotal > 0 {
			if !canUseSub || subTotal-user.SubscriptionQuotaUsed < reservedCost {
				return NewBillingError(reservedCost, subTotal-user.SubscriptionQuotaUsed)
			}
			user.SubscriptionQuotaUsed += reservedCost
			record.QuotaType = "subscription"
		} else {
			freeLeft := user.DailyCheckInBonus - user.DailyQuotaUsed
			if freeLeft < reservedCost {
				return NewBillingError(reservedCost, freeLeft)
			}
			user.DailyQuotaUsed += reservedCost
			record.QuotaType = "free"
		}
		if err := tx.Replace("User", userID, &user); err != nil {
			return err
		}
		return tx.Insert("BillingReservation", &record)
	})
	if err != nil {
		return nil, err
	}
	PublishQuotaChanged(userID)
	return reservation, nil
}

func (s *BillingService) Release(reservationID string) error {
	var reservation billingReservationRecord
	if !database.Get().Register("BillingReservation").FindOne(database.FilterEq("ReservationID", reservationID), &reservation) {
		return fmt.Errorf("计费预留不存在")
	}
	unlock := lockReservationUser(reservation.UserID)
	defer unlock()

	err := database.Get().WithTx(nil, func(tx *database.Tx) error {
		found, err := tx.FindOne("BillingReservation", database.FilterEq("ReservationID", reservationID), &reservation)
		if err != nil {
			return err
		}
		if !found || reservation.Status != "pending" {
			return nil
		}
		var user models.User
		found, err = tx.FindByID("User", reservation.UserID, &user)
		if err != nil || !found {
			return fmt.Errorf("预留用户不存在")
		}
		if reservation.QuotaType == "subscription" {
			user.SubscriptionQuotaUsed -= reservation.ReservedCost
			if user.SubscriptionQuotaUsed < 0 {
				user.SubscriptionQuotaUsed = 0
			}
		} else {
			user.DailyQuotaUsed -= reservation.ReservedCost
			if user.DailyQuotaUsed < 0 {
				user.DailyQuotaUsed = 0
			}
		}
		now := time.Now().UTC()
		reservation.Status = "released"
		reservation.SettledAt = &now
		if err := tx.Replace("User", user.ID, &user); err != nil {
			return err
		}
		return tx.Replace("BillingReservation", reservation.ID, &reservation)
	})
	if err == nil {
		PublishQuotaChanged(reservation.UserID)
	}
	return err
}

func (s *BillingService) Settle(reservationID, username, modelID string, promptTokens, cacheHit, cacheMiss, completionTokens int, thinkingEnabled bool) (float64, error) {
	var reservation billingReservationRecord
	if !database.Get().Register("BillingReservation").FindOne(database.FilterEq("ReservationID", reservationID), &reservation) {
		return 0, fmt.Errorf("计费预留不存在")
	}
	baseCost, err := s.CalculateCost(modelID, promptTokens, cacheHit, cacheMiss, completionTokens, thinkingEnabled)
	if err != nil {
		return 0, err
	}
	priceMultiplier := reservation.PriceMultiplier
	if !isPositiveFinite(priceMultiplier) {
		priceMultiplier = 1
	}
	cost := applyPriceMultiplier(baseCost, priceMultiplier)

	// 订阅配额总额需在事务外查询：写事务全程持有写锁，回调内只应使用 tx 句柄。
	subTotal := 0.0
	if reservation.QuotaType == "subscription" {
		subTotal = getSubscriptionQuotaTotal(reservation.UserID)
	}

	unlock := lockReservationUser(reservation.UserID)
	defer unlock()

	err = database.Get().WithTx(nil, func(tx *database.Tx) error {
		found, err := tx.FindOne("BillingReservation", database.FilterEq("ReservationID", reservationID), &reservation)
		if err != nil {
			return err
		}
		if !found || reservation.Status != "pending" {
			return fmt.Errorf("计费预留状态无效")
		}
		var user models.User
		found, err = tx.FindByID("User", reservation.UserID, &user)
		if err != nil || !found {
			return fmt.Errorf("预留用户不存在")
		}
		delta := cost - reservation.ReservedCost
		if reservation.QuotaType == "subscription" {
			user.SubscriptionQuotaUsed += delta
			if user.SubscriptionQuotaUsed < 0 {
				user.SubscriptionQuotaUsed = 0
			}
			// 实际费用超过预留时 delta 为正且不再校验当日配额，
			// 这里封顶到订阅总额（剩余扣到 0 为止）并告警，避免 used 计数变成无意义的大数。
			if subTotal > 0 && user.SubscriptionQuotaUsed > subTotal {
				log.Printf("[billing] 结算超出订阅配额: userID=%d reservation=%s cost=%.6f reserved=%.6f 超额=%.6f（已按订阅总额 %.6f 封顶）",
					reservation.UserID, reservationID, cost, reservation.ReservedCost, user.SubscriptionQuotaUsed-subTotal, subTotal)
				user.SubscriptionQuotaUsed = subTotal
			}
		} else {
			user.DailyQuotaUsed += delta
			if user.DailyQuotaUsed < 0 {
				user.DailyQuotaUsed = 0
			}
			if user.DailyCheckInBonus > 0 && user.DailyQuotaUsed > user.DailyCheckInBonus {
				log.Printf("[billing] 结算超出免费配额: userID=%d reservation=%s cost=%.6f reserved=%.6f 超额=%.6f（已按签到额度 %.6f 封顶）",
					reservation.UserID, reservationID, cost, reservation.ReservedCost, user.DailyQuotaUsed-user.DailyCheckInBonus, user.DailyCheckInBonus)
				user.DailyQuotaUsed = user.DailyCheckInBonus
			}
		}
		now := time.Now().UTC()
		reservation.Status = "settled"
		reservation.SettledAt = &now
		if err := tx.Replace("User", user.ID, &user); err != nil {
			return err
		}
		if err := tx.Replace("BillingReservation", reservation.ID, &reservation); err != nil {
			return err
		}
		record := models.UsageRecord{
			UserID: reservation.UserID, Username: username, Model: modelID,
			PromptTokens: promptTokens, PromptCacheHit: cacheHit, PromptCacheMiss: cacheMiss,
			CompletionTokens: completionTokens, Cost: cost,
			PricingPeriod: reservation.PricingPeriod, PriceMultiplier: priceMultiplier,
		}
		return tx.Insert("UsageRecord", &record)
	})
	if err == nil {
		PublishQuotaChanged(reservation.UserID)
	}
	return cost, err
}
