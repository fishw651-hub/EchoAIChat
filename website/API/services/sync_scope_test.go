package services

import "testing"

func TestSelectedSyncScopeKeepsOnlyPrivateAgentClosure(t *testing.T) {
	scope := NewSelectedSyncScope([]string{"agent-a"})
	items := []map[string]interface{}{
		{"client_id": "m1", "agent_id": "agent-a", "group_id": ""},
		{"client_id": "m2", "agent_id": "agent-b", "group_id": ""},
		{"client_id": "m3", "agent_id": "agent-a", "group_id": "group-1"},
	}

	filtered := FilterSyncItems(scope, "long_term_memories", items)
	if len(filtered) != 1 || filtered[0]["client_id"] != "m1" {
		t.Fatalf("filtered = %#v, want only m1", filtered)
	}
}

func TestSelectedSyncScopeRejectsGlobalAndGroupTables(t *testing.T) {
	scope := NewSelectedSyncScope([]string{"agent-a"})
	for _, table := range []string{"group_chats", "group_messages", "user_profiles", "providers"} {
		if got := FilterSyncItems(scope, table, []map[string]interface{}{{"client_id": "x"}}); len(got) != 0 {
			t.Fatalf("table %s returned %#v, want empty", table, got)
		}
	}
}

func TestAllSyncScopeIncludesFutureAgentsAndGlobalTables(t *testing.T) {
	scope := NewAllSyncScope()
	items := []map[string]interface{}{{"client_id": "new-agent"}}
	if got := FilterSyncItems(scope, "agents", items); len(got) != 1 {
		t.Fatalf("agents = %#v, want new agent", got)
	}
	if got := FilterSyncItems(scope, "providers", items); len(got) != 1 {
		t.Fatalf("providers = %#v, want global table in all mode", got)
	}
}

func TestSelectedSyncScopeFiltersTombstonesByAgent(t *testing.T) {
	scope := NewSelectedSyncScope([]string{"agent-a"})
	tombstones := []map[string]interface{}{
		{"table_name": "agents", "client_id": "agent-a"},
		{"table_name": "agents", "client_id": "agent-b"},
		{"table_name": "chat_messages", "client_id": "c1", "agent_id": "agent-a"},
		{"table_name": "chat_messages", "client_id": "c2", "agent_id": "agent-b"},
	}

	filtered := FilterSyncTombstones(scope, tombstones)
	if len(filtered) != 2 {
		t.Fatalf("filtered tombstones = %#v, want 2", filtered)
	}
}
