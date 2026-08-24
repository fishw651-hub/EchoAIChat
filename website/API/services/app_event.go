package services

import (
	"fmt"
	"time"

	"aichat-api/hub"
)

// PublishNetworkReviewStatus 发送上传者审核状态变化，并在内容可见性改变时刷新公共市场。
func PublishNetworkReviewStatus(
	uploaderID uint,
	resourceType string,
	resourceID uint,
	status string,
	reason string,
	version int,
	previousStatus string,
	reviewedAt time.Time,
) {
	publisher := getEventPublisher()
	if publisher == nil {
		return
	}
	timestamp := reviewedAt.Unix()
	if timestamp <= 0 {
		timestamp = time.Now().Unix()
	}
	eventID := fmt.Sprintf("%s:%d:%d:%s:%d", resourceType, resourceID, version, status, timestamp)
	publisher.NotifyUserAppEvent(uploaderID, hub.AppEvent{
		Scope:        hub.AppEventScopeMyUploads,
		ResourceType: resourceType,
		ResourceID:   resourceID,
		Status:       status,
		Reason:       reason,
		Version:      version,
		EventID:      eventID,
		Timestamp:    timestamp,
	})

	// 只有 approved 内容存在于公共市场；pending/rejected/taken_down 的变化
	// 也需要刷新市场以移除或重新拉取条目，但不携带上传者理由。
	if previousStatus == "approved" || status == "approved" || status == "taken_down" {
		publisher.NotifyGlobalAppEvent(hub.AppEvent{
			Scope: func() string {
				if resourceType == "group" {
					return hub.AppEventScopeNetworkGroups
				}
				return hub.AppEventScopeNetworkAgents
			}(),
			ResourceType: resourceType,
			ResourceID:   resourceID,
			Status:       status,
			Version:      version,
			EventID:      eventID,
			Timestamp:    timestamp,
		})
	}
}

func PublishQuotaChanged(userID uint) {
	publisher := getEventPublisher()
	if publisher == nil {
		return
	}
	now := time.Now().UnixNano()
	publisher.NotifyUserAppEvent(userID, hub.AppEvent{
		Scope:        hub.AppEventScopeQuota,
		ResourceType: "quota",
		EventID:      fmt.Sprintf("quota:%d:%d", userID, now),
		Timestamp:    now / int64(time.Second),
	})
}

func PublishSubscriptionChanged(userID uint) {
	publisher := getEventPublisher()
	if publisher == nil {
		return
	}
	now := time.Now().UnixNano()
	publisher.NotifyUserAppEvent(userID, hub.AppEvent{
		Scope:        hub.AppEventScopeSubscription,
		ResourceType: "subscription",
		EventID:      fmt.Sprintf("subscription:%d:%d", userID, now),
		Timestamp:    now / int64(time.Second),
	})
}
