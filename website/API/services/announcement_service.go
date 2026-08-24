package services

import (
	"errors"
	"strings"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

// 公告频率与目标用户的合法取值
const (
	AnnouncementFrequencyOnce   = "once"   // 仅一次（看过即不再弹）
	AnnouncementFrequencyDaily  = "daily"  // 每天一次
	AnnouncementFrequencyAlways = "always" // 每次启动

	AnnouncementAudienceAll        = "all"        // 全部用户
	AnnouncementAudienceSubscriber = "subscriber" // 仅订阅用户
	AnnouncementAudienceFree       = "free"       // 仅免费用户
)

// AnnouncementMaxContentBytes 公告内容（Markdown）最大字节数：50KB
const AnnouncementMaxContentBytes = 50 * 1024

func announcementTable() *database.Table {
	return database.Get().Register("Announcement")
}

// ValidateAnnouncement 校验公告字段并解析生效窗口。
// 规则：标题/内容非空、内容 ≤ 50KB、频率与目标用户白名单、
// StartAt/EndAt 必填且为 RFC3339、EndAt 必须晚于 StartAt。
func ValidateAnnouncement(title, content, frequency, audience, startAt, endAt string) (start, end time.Time, err error) {
	if strings.TrimSpace(title) == "" {
		return start, end, errors.New("标题不能为空")
	}
	if strings.TrimSpace(content) == "" {
		return start, end, errors.New("内容不能为空")
	}
	if len(content) > AnnouncementMaxContentBytes {
		return start, end, errors.New("内容超过 50KB 限制")
	}
	switch frequency {
	case AnnouncementFrequencyOnce, AnnouncementFrequencyDaily, AnnouncementFrequencyAlways:
	default:
		return start, end, errors.New("频率取值不合法（once/daily/always）")
	}
	switch audience {
	case AnnouncementAudienceAll, AnnouncementAudienceSubscriber, AnnouncementAudienceFree:
	default:
		return start, end, errors.New("目标用户取值不合法（all/subscriber/free）")
	}
	start, err = time.Parse(time.RFC3339, startAt)
	if err != nil {
		return start, end, errors.New("生效时间必填且须为 RFC3339 格式")
	}
	end, err = time.Parse(time.RFC3339, endAt)
	if err != nil {
		return start, end, errors.New("截止时间必填且须为 RFC3339 格式")
	}
	if !end.After(start) {
		return start, end, errors.New("截止时间必须晚于生效时间")
	}
	return start, end, nil
}

// CreateAnnouncement 创建公告（字段须先通过 ValidateAnnouncement 校验）
func CreateAnnouncement(a *models.Announcement) error {
	return announcementTable().Insert(a)
}

// UpdateAnnouncement 按 ID 全量更新公告业务字段
func UpdateAnnouncement(a *models.Announcement) error {
	return announcementTable().UpdateWhere(database.FilterEq("ID", a.ID), map[string]interface{}{
		"Title":     a.Title,
		"Content":   a.Content,
		"Frequency": a.Frequency,
		"Audience":  a.Audience,
		"StartAt":   a.StartAt,
		"EndAt":     a.EndAt,
		"Enabled":   a.Enabled,
	})
}

// DeleteAnnouncement 按 ID 删除公告
func DeleteAnnouncement(id uint) bool {
	return announcementTable().Delete(id)
}

// GetAnnouncement 按 ID 查询公告
func GetAnnouncement(id uint) (models.Announcement, bool) {
	var a models.Announcement
	if !announcementTable().FindByID(id, &a) {
		return models.Announcement{}, false
	}
	return a, true
}

// ListAnnouncements 全部公告（按 ID 倒序，新公告在前）
func ListAnnouncements() []models.Announcement {
	var all []models.Announcement
	announcementTable().FindAll(&all, nil, "ID desc", 0, 0)
	return all
}

// ListActiveAnnouncements 当前生效的公告：已启用且 now 落在 [StartAt, EndAt] 窗口内
// 时间字段无法解析的记录视为不生效（跳过）
func ListActiveAnnouncements(now time.Time) []models.Announcement {
	result := make([]models.Announcement, 0)
	for _, a := range ListAnnouncements() {
		if !a.Enabled {
			continue
		}
		start, err := time.Parse(time.RFC3339, a.StartAt)
		if err != nil {
			continue
		}
		end, err := time.Parse(time.RFC3339, a.EndAt)
		if err != nil {
			continue
		}
		if now.Before(start) || now.After(end) {
			continue
		}
		result = append(result, a)
	}
	return result
}
