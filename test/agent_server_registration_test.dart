import 'package:aichat/models/agent.dart';
import 'package:aichat/providers/agent_provider.dart';
import 'package:aichat/services/database_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('agent-server-registration');
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    AgentNotifier.onAgentSaved = null;
    final db = await DatabaseService.database;
    await db.delete('agents');
  });

  tearDown(() {
    AgentNotifier.onAgentSaved = null;
  });

  test('新建和编辑智能体后触发服务端幂等登记', () async {
    final saved = <Agent>[];
    AgentNotifier.onAgentSaved = (agent) async {
      saved.add(agent);
    };
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(agentProvider.notifier);

    final created = await notifier.createAgent(
      name: 'A',
      persona: 'persona',
      realInfoEnabled: true,
    );
    final updated = created.copyWith(name: 'B');
    await notifier.updateAgent(updated);

    expect(saved.map((agent) => agent.name), ['A', 'B']);
    expect(saved.every((agent) => agent.id == created.id), isTrue);
  });
}
