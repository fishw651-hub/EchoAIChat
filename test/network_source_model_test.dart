import 'package:aichat/models/agent.dart';
import 'package:aichat/models/group_chat.dart';
import 'package:aichat/services/network_copy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agent preserves network ownership metadata', () {
    final agent = Agent(
      name: 'A',
      persona: 'P',
      networkId: 7,
      networkUploaderId: 3,
      networkSource: NetworkCopySource.owner,
      networkVersion: 2,
    );

    final restored = Agent.fromMap(agent.toMap());

    expect(restored.networkId, 7);
    expect(restored.networkUploaderId, 3);
    expect(restored.networkSource, NetworkCopySource.owner);
    expect(restored.networkVersion, 2);
  });

  test('group preserves opening speaker, opening line and downloaded source', () {
    final group = GroupChat(
      name: 'G',
      openingLine: '欢迎',
      openingSpeakerAgentId: 'speaker-1',
      networkId: 9,
      networkUploaderId: 4,
      networkSource: NetworkCopySource.downloaded,
      networkVersion: 1,
    );

    final restored = GroupChat.fromMap(group.toMap());

    expect(restored.openingLine, '欢迎');
    expect(restored.openingSpeakerAgentId, 'speaker-1');
    expect(restored.networkId, 9);
    expect(restored.networkUploaderId, 4);
    expect(restored.networkSource, NetworkCopySource.downloaded);
    expect(restored.networkVersion, 1);
  });

  test('copyWith can clear network ownership metadata', () {
    final agent = Agent(
      name: 'A',
      persona: 'P',
      networkId: 7,
      networkUploaderId: 3,
      networkSource: NetworkCopySource.owner,
      networkVersion: 2,
    );

    final local = agent.copyWith(
      clearNetworkId: true,
      clearNetworkUploaderId: true,
      networkSource: NetworkCopySource.none,
      clearNetworkVersion: true,
    );

    expect(local.networkId, isNull);
    expect(local.networkUploaderId, isNull);
    expect(local.networkSource, NetworkCopySource.none);
    expect(local.networkVersion, isNull);
  });
}
