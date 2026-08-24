import 'package:aichat/services/agent_export_service.dart';
import 'package:aichat/services/database_service.dart';
import 'package:aichat/services/group_export_service.dart';
import 'package:aichat/services/network_copy_policy.dart';
import 'package:aichat/models/agent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/isolated_test_database.dart';

void main() {
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open('network-download-source');
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('group_members');
    await db.delete('group_chats');
    await db.delete('agents');
  });

  test('downloaded agent records immutable market provenance', () async {
    await DatabaseService.insertAgent(Agent(name: 'A', persona: 'P'));

    final agent = await AgentExportService.deserializeDownloaded({
      'version': 4,
      'agent': {
        'id': 12,
        'uploader_id': 8,
        'name': 'A',
        'persona': 'P',
        'opening_line': 'Hi',
      },
    });

    expect(agent.networkId, 12);
    expect(agent.networkUploaderId, 8);
    expect(agent.networkSource, NetworkCopySource.downloaded);
    expect(agent.networkVersion, 4);
    expect(agent.realInfoEnabled, isFalse);
    expect(agent.proactiveCareEnabled, isFalse);
    expect((await DatabaseService.getAgents()).length, 2);
  });

  test('finds the existing downloaded agent by network ID', () async {
    final downloaded = await AgentExportService.deserializeDownloaded({
      'agent': {'id': 12, 'name': 'A', 'persona': 'P', 'opening_line': 'Hi'},
    });

    final existing = await AgentExportService.findDownloadedAgent(12);

    expect(existing?.id, downloaded.id);
  });

  test(
    'repairs an incomplete downloaded agent from the full market payload',
    () async {
      final damaged = Agent(
        name: 'A',
        persona: '',
        networkId: 12,
        networkUploaderId: 8,
        networkSource: NetworkCopySource.downloaded,
        networkVersion: 1,
      );
      await DatabaseService.insertAgent(damaged);
      expect(AgentExportService.hasCompleteDownloadedContent(damaged), isFalse);

      final repaired = await AgentExportService.deserializeDownloaded({
        'version': 2,
        'agent': {
          'id': 12,
          'uploader_id': 8,
          'name': 'A',
          'description': 'Developer description',
          'persona': 'Developer persona',
          'opening_line': 'Developer opening',
          'worldview': 'Developer worldview',
        },
      });

      expect(repaired.id, damaged.id);
      expect(repaired.persona, 'Developer persona');
      expect(repaired.openingLine, 'Developer opening');
      expect(repaired.worldview, 'Developer worldview');
      expect(repaired.description, 'Developer description');
      expect(repaired.networkVersion, 2);
      expect(AgentExportService.hasCompleteDownloadedContent(repaired), isTrue);

      final persisted = await AgentExportService.findDownloadedAgent(12);
      expect(persisted?.persona, 'Developer persona');
      expect(persisted?.openingLine, 'Developer opening');
      expect((await DatabaseService.getAgents()).length, 1);
    },
  );

  test('rejects a download response with missing protected content', () async {
    await expectLater(
      AgentExportService.deserializeDownloaded({
        'version': 1,
        'agent': {
          'id': 99,
          'name': 'Broken',
          'persona': '',
          'opening_line': '',
        },
      }),
      throwsA(isA<FormatException>()),
    );

    expect(await AgentExportService.findDownloadedAgent(99), isNull);
  });

  test(
    'downloaded group returns persisted group with market provenance',
    () async {
      final group = await GroupExportService().importDownloadedGroup({
        'version': 3,
        'group': {
          'id': 21,
          'uploader_id': 9,
          'name': 'G',
          'group_persona': 'P',
          'opening_line': 'Welcome',
        },
        'members': <Map<String, dynamic>>[],
      });

      final persisted = await DatabaseService.getGroupChat(group.id);
      expect(persisted, isNotNull);
      expect(group.openingLine, 'Welcome');
      expect(group.networkId, 21);
      expect(group.networkUploaderId, 9);
      expect(group.networkSource, NetworkCopySource.downloaded);
      expect(group.networkVersion, 3);
    },
  );
}
