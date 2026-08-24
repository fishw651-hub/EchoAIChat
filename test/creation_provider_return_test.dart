import 'package:aichat/models/agent.dart';
import 'package:aichat/models/group_chat.dart';
import 'package:aichat/models/group_member.dart';
import 'package:aichat/providers/agent_provider.dart';
import 'package:aichat/providers/group_provider.dart';
import 'package:aichat/services/database_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('creation-provider-return');
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('group_members');
    await db.delete('group_chats');
    await db.delete('agents');
  });

  test('createAgent returns the created agent', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(agentProvider.notifier);

    final Agent created = await notifier.createAgent(
      name: 'A',
      persona: 'P',
      openingLine: 'Hello',
    );

    expect(created.id, isNotEmpty);
    expect(created.name, 'A');
  });

  test('createGroup returns the created group with opening line', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final GroupChat created = await container
        .read(groupProvider.notifier)
        .createGroup(
          name: 'G',
          openingLine: 'Welcome',
          members: <GroupMember>[],
        );

    expect(created.id, isNotEmpty);
    expect(created.openingLine, 'Welcome');
  });
}
