package services

import "sort"

type SyncScope struct {
	Mode     string   `json:"mode"`
	AgentIDs []string `json:"agent_ids"`
	agents   map[string]struct{}
}

var selectedSyncTables = map[string]struct{}{
	"agents": {}, "chat_messages": {}, "short_term_messages": {},
	"long_term_memories": {}, "base_memories": {}, "planned_messages": {},
}

func NewAllSyncScope() SyncScope {
	return SyncScope{Mode: "all", AgentIDs: []string{}, agents: map[string]struct{}{}}
}

func NewSelectedSyncScope(agentIDs []string) SyncScope {
	normalized := normalizeSelectedAgentIDs(agentIDs)
	agents := make(map[string]struct{}, len(normalized))
	for _, agentID := range normalized {
		agents[agentID] = struct{}{}
	}
	return SyncScope{Mode: "selected", AgentIDs: normalized, agents: agents}
}

func (s SyncScope) AllowsAgent(agentID string) bool {
	if s.Mode == "all" {
		return true
	}
	if s.agents == nil {
		s.agents = make(map[string]struct{}, len(s.AgentIDs))
		for _, selectedID := range s.AgentIDs {
			s.agents[selectedID] = struct{}{}
		}
	}
	_, ok := s.agents[agentID]
	return ok
}

func (s SyncScope) AllowsTable(table string) bool {
	if s.Mode == "all" {
		return true
	}
	_, ok := selectedSyncTables[table]
	return ok
}

func FilterSyncItems(scope SyncScope, table string, items []map[string]interface{}) []map[string]interface{} {
	if !scope.AllowsTable(table) {
		return []map[string]interface{}{}
	}
	if scope.Mode == "all" {
		return cloneSyncItems(items)
	}

	filtered := make([]map[string]interface{}, 0, len(items))
	for _, item := range items {
		if syncItemInScope(scope, table, item) {
			filtered = append(filtered, cloneSyncItem(item))
		}
	}
	return filtered
}

func FilterSyncTombstones(scope SyncScope, tombstones []map[string]interface{}) []map[string]interface{} {
	if scope.Mode == "all" {
		return cloneSyncItems(tombstones)
	}
	filtered := make([]map[string]interface{}, 0, len(tombstones))
	for _, tombstone := range tombstones {
		table := syncString(tombstone, "table_name", "TableName")
		if !scope.AllowsTable(table) {
			continue
		}
		var agentID string
		if table == "agents" {
			agentID = syncString(tombstone, "client_id", "ClientID")
		} else {
			agentID = syncString(tombstone, "agent_id", "AgentID")
		}
		if scope.AllowsAgent(agentID) {
			filtered = append(filtered, cloneSyncItem(tombstone))
		}
	}
	return filtered
}

func syncItemInScope(scope SyncScope, table string, item map[string]interface{}) bool {
	if table == "agents" {
		return scope.AllowsAgent(syncString(item, "client_id", "ClientID", "id", "ID"))
	}
	if !scope.AllowsAgent(syncString(item, "agent_id", "AgentID")) {
		return false
	}
	if table == "long_term_memories" || table == "base_memories" || table == "planned_messages" {
		return syncString(item, "group_id", "GroupID") == ""
	}
	return true
}

func syncString(item map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		value, ok := item[key]
		if !ok || value == nil {
			continue
		}
		if text, ok := value.(string); ok {
			return text
		}
	}
	return ""
}

func cloneSyncItems(items []map[string]interface{}) []map[string]interface{} {
	result := make([]map[string]interface{}, 0, len(items))
	for _, item := range items {
		result = append(result, cloneSyncItem(item))
	}
	return result
}

func cloneSyncItem(item map[string]interface{}) map[string]interface{} {
	copy := make(map[string]interface{}, len(item))
	for key, value := range item {
		copy[key] = value
	}
	return copy
}

func SortedScopeAgentIDs(scope SyncScope) []string {
	result := append([]string(nil), scope.AgentIDs...)
	sort.Strings(result)
	return result
}
