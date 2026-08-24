import 'package:aichat/models/sync_policy.dart';
import 'package:aichat/services/sync_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncScope', () {
    test('all mode includes future agents and all legacy tables', () {
      final scope = SyncScope.accountPolicy(const SyncPolicy.all(version: 1));

      expect(scope.allowsTable('providers'), isTrue);
      expect(scope.allowsAgent('future-agent'), isTrue);
      expect(scope.tables, hasLength(13));
    });

    test('selected mode keeps only the private six-table closure', () {
      final scope = SyncScope.accountPolicy(
        const SyncPolicy.selected(agentIds: {'agent-a'}, version: 2),
      );

      expect(scope.tables, agentSyncClosureTables);
      expect(
        scope.filterRows('agents', [
          {'client_id': 'agent-a'},
          {'client_id': 'agent-b'},
        ]),
        [
          {'client_id': 'agent-a'},
        ],
      );
      expect(
        scope.filterRows('long_term_memories', [
          {'client_id': 'm1', 'agent_id': 'agent-a', 'group_id': null},
          {'client_id': 'm2', 'agent_id': 'agent-b', 'group_id': null},
          {'client_id': 'm3', 'agent_id': 'agent-a', 'group_id': 'group-1'},
        ]),
        [
          {'client_id': 'm1', 'agent_id': 'agent-a', 'group_id': null},
        ],
      );
    });

    test('one-shot scope does not mutate account policy', () {
      const policy = SyncPolicy.selected(
        agentIds: {'agent-a', 'agent-b'},
        version: 3,
        realtimeEnabled: true,
      );

      final oneShot = SyncScope.oneShot({'agent-c'});

      expect(oneShot.agentIds, {'agent-c'});
      expect(policy.selectedAgentIds, {'agent-a', 'agent-b'});
      expect(policy.realtimeEnabled, isTrue);
    });

    test('selected tombstones require an in-scope agent', () {
      final scope = SyncScope.oneShot({'agent-a'});
      final filtered = scope.filterTombstones([
        {'table_name': 'agents', 'client_id': 'agent-a'},
        {'table_name': 'agents', 'client_id': 'agent-b'},
        {
          'table_name': 'chat_messages',
          'client_id': 'message-a',
          'agent_id': 'agent-a',
        },
        {
          'table_name': 'chat_messages',
          'client_id': 'message-b',
          'agent_id': 'agent-b',
        },
      ]);

      expect(filtered.map((item) => item['client_id']), [
        'agent-a',
        'message-a',
      ]);
    });
  });
}
