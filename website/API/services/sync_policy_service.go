package services

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"aichat-api/database"
	"aichat-api/models"
)

const maxSelectedSyncAgents = 500

var (
	ErrSyncPolicyConflict = errors.New("同步策略已在其他设备更新")
	ErrInvalidSyncPolicy  = errors.New("无效的同步策略")
)

type SyncPolicyService struct {
	mu sync.Mutex
}

func NewSyncPolicyService() *SyncPolicyService {
	return &SyncPolicyService{}
}

var DefaultSyncPolicyService = NewSyncPolicyService()

func (s *SyncPolicyService) Get(userID uint) (models.SyncPolicy, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.getLocked(userID)
}

func (s *SyncPolicyService) Update(userID uint, update models.SyncPolicyUpdate) (models.SyncPolicy, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	current, err := s.getLocked(userID)
	if err != nil {
		return models.SyncPolicy{}, err
	}
	if update.ExpectedVersion != current.Version {
		return models.SyncPolicy{}, ErrSyncPolicyConflict
	}
	if update.ScopeMode != "all" && update.ScopeMode != "selected" {
		return models.SyncPolicy{}, fmt.Errorf("%w: scope_mode", ErrInvalidSyncPolicy)
	}

	selected := normalizeSelectedAgentIDs(update.SelectedAgentIDs)
	if len(selected) > maxSelectedSyncAgents {
		return models.SyncPolicy{}, fmt.Errorf("%w: selected_agent_ids 超过 %d", ErrInvalidSyncPolicy, maxSelectedSyncAgents)
	}
	if update.ScopeMode == "all" {
		selected = []string{}
	}

	now := time.Now().UTC()
	nextVersion := current.Version + 1
	updates := map[string]interface{}{
		"ScopeMode":        update.ScopeMode,
		"SelectedAgentIDs": selected,
		"RealtimeEnabled":  update.RealtimeEnabled,
		"FullSyncEnabled":  update.RealtimeEnabled,
		"PolicyVersion":    nextVersion,
		"UpdatedAt":        now,
	}
	table := database.Get().Register("SyncSetting")
	if err := table.UpdateWhere(database.FilterEq("UserID", userID), updates); err != nil {
		return models.SyncPolicy{}, fmt.Errorf("更新同步策略: %w", err)
	}
	if publisher := getEventPublisher(); publisher != nil {
		publisher.NotifySyncChange(userID, "sync_policy")
	}

	return models.SyncPolicy{
		ScopeMode:        update.ScopeMode,
		SelectedAgentIDs: append([]string(nil), selected...),
		RealtimeEnabled:  update.RealtimeEnabled,
		Version:          nextVersion,
		UpdatedAt:        now,
	}, nil
}

func (s *SyncPolicyService) getLocked(userID uint) (models.SyncPolicy, error) {
	table := database.Get().Register("SyncSetting")
	var setting models.SyncSetting
	if !table.FindOne(database.FilterEq("UserID", userID), &setting) {
		now := time.Now().UTC()
		setting = models.SyncSetting{
			UserID:           userID,
			ScopeMode:        "all",
			SelectedAgentIDs: []string{},
			PolicyVersion:    1,
			CreatedAt:        now,
			UpdatedAt:        now,
		}
		if err := table.Insert(&setting); err != nil {
			return models.SyncPolicy{}, fmt.Errorf("创建同步策略: %w", err)
		}
		return policyFromSetting(setting), nil
	}

	if setting.ScopeMode == "" || setting.PolicyVersion == 0 {
		setting.ScopeMode = "all"
		setting.SelectedAgentIDs = []string{}
		setting.RealtimeEnabled = setting.FullSyncEnabled
		setting.PolicyVersion = 1
		setting.UpdatedAt = time.Now().UTC()
		if err := table.UpdateWhere(database.FilterEq("ID", setting.ID), map[string]interface{}{
			"ScopeMode":        setting.ScopeMode,
			"SelectedAgentIDs": setting.SelectedAgentIDs,
			"RealtimeEnabled":  setting.RealtimeEnabled,
			"PolicyVersion":    setting.PolicyVersion,
			"UpdatedAt":        setting.UpdatedAt,
		}); err != nil {
			return models.SyncPolicy{}, fmt.Errorf("迁移同步策略: %w", err)
		}
	}

	setting.SelectedAgentIDs = normalizeSelectedAgentIDs(setting.SelectedAgentIDs)
	if setting.ScopeMode == "all" {
		setting.SelectedAgentIDs = []string{}
	}
	return policyFromSetting(setting), nil
}

func policyFromSetting(setting models.SyncSetting) models.SyncPolicy {
	return models.SyncPolicy{
		ScopeMode:        setting.ScopeMode,
		SelectedAgentIDs: append([]string(nil), setting.SelectedAgentIDs...),
		RealtimeEnabled:  setting.RealtimeEnabled,
		Version:          setting.PolicyVersion,
		UpdatedAt:        setting.UpdatedAt,
	}
}

func normalizeSelectedAgentIDs(agentIDs []string) []string {
	unique := make(map[string]struct{}, len(agentIDs))
	for _, agentID := range agentIDs {
		agentID = strings.TrimSpace(agentID)
		if agentID != "" {
			unique[agentID] = struct{}{}
		}
	}
	result := make([]string, 0, len(unique))
	for agentID := range unique {
		result = append(result, agentID)
	}
	sort.Strings(result)
	return result
}
