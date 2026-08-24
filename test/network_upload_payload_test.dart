import 'package:aichat/models/agent.dart';
import 'package:aichat/models/group_chat.dart';
import 'package:aichat/services/network_copy_policy.dart';
import 'package:aichat/services/network_upload_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agent payload carries original source and opening line', () async {
    final agent = Agent(name: 'A', persona: 'P', openingLine: 'Hello');

    final payload = await buildAgentNetworkPayload(agent, const ['healing']);

    expect(payload['opening_line'], 'Hello');
    expect(payload['source_kind'], NetworkCopySource.none);
    expect(payload['tags'], ['healing']);
  });

  test('downloaded copy payload throws before HTTP', () async {
    final downloaded = Agent(
      name: 'A',
      persona: 'P',
      openingLine: 'Hello',
      networkSource: NetworkCopySource.downloaded,
    );

    expect(
      () => buildAgentNetworkPayload(downloaded, const []),
      throwsStateError,
    );
  });

  test('group payload requires and includes opening line', () {
    final group = GroupChat(
      name: 'G',
      groupPersona: 'P',
      openingLine: 'Welcome',
    );

    final payload = buildGroupNetworkPayload(
      group,
      const <Map<String, dynamic>>[],
      const ['roleplay'],
    );

    expect(payload['opening_line'], 'Welcome');
    expect(payload['opening_speaker_index'], -1);
    expect(payload['source_kind'], NetworkCopySource.none);
    expect(payload['tags'], ['roleplay']);
  });

  test('group payload converts the local opening speaker into a member index', () {
    final group = GroupChat(
      name: 'G',
      groupPersona: 'P',
      openingLine: 'Welcome',
      openingSpeakerAgentId: 'agent-b',
    );

    final payload = buildGroupNetworkPayload(group, const [
      {'agent_id': 'agent-a', 'name': 'A'},
      {'agent_id': 'agent-b', 'name': 'B'},
    ], const []);

    expect(payload['opening_speaker_index'], 1);
    expect((payload['members'] as List).first, isNot(contains('agent_id')));
  });

  test('blank opening line is rejected before HTTP', () async {
    final agent = Agent(name: 'A', persona: 'P', openingLine: '  ');
    final group = GroupChat(name: 'G', groupPersona: 'P');

    expect(
      () => buildAgentNetworkPayload(agent, const []),
      throwsArgumentError,
    );
    expect(
      () => buildGroupNetworkPayload(group, const [], const []),
      throwsArgumentError,
    );
  });

  test('upload response binds local agent ownership', () {
    final agent = Agent(name: 'A', persona: 'P', openingLine: 'Hello');

    final bound = bindAgentNetworkOwner(agent, const {
      'id': 31,
      'uploader_id': 7,
      'version': 2,
    });

    expect(bound.networkId, 31);
    expect(bound.networkUploaderId, 7);
    expect(bound.networkSource, NetworkCopySource.owner);
    expect(bound.networkVersion, 2);
  });

  test('upload response binds local group ownership', () {
    final group = GroupChat(
      name: 'G',
      groupPersona: 'P',
      openingLine: 'Welcome',
    );

    final bound = bindGroupNetworkOwner(group, const {
      'id': 41,
      'uploader_id': 8,
      'version': 3,
    });

    expect(bound.networkId, 41);
    expect(bound.networkUploaderId, 8);
    expect(bound.networkSource, NetworkCopySource.owner);
    expect(bound.networkVersion, 3);
  });
}
