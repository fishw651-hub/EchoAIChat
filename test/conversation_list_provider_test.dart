import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/models/agent.dart';
import 'package:aichat/models/group_chat.dart';
import 'package:aichat/providers/conversation_list_provider.dart';

void main() {
  group('buildConversationItems', () {
    test('空 agents 和 groups 返回空列表', () {
      final items = buildConversationItems(
        agents: const [],
        groups: const [],
        lastByAgent: const {},
        lastByGroup: const {},
      );
      expect(items, isEmpty);
    });

    test('无消息时回退到 createdAt 作为时间戳', () {
      final agent = Agent(name: 'A', persona: '', createdAt: 1000);
      final items = buildConversationItems(
        agents: [agent],
        groups: const [],
        lastByAgent: const {},
        lastByGroup: const {},
      );
      expect(items, hasLength(1));
      expect(items.single.isGroup, isFalse);
      expect(items.single.timestamp, 1000);
      expect(items.single.lastMessage, isEmpty);
    });

    test('按最新消息时间倒序混排智能体与群聊', () {
      final agentOld = Agent(name: 'A', persona: '', createdAt: 1000);
      final agentNew = Agent(name: 'B', persona: '', createdAt: 2000);
      final group = GroupChat(name: 'G', createdAt: 1500);
      final items = buildConversationItems(
        agents: [agentOld, agentNew],
        groups: [group],
        lastByAgent: {
          agentOld.id: {'timestamp': 5000},
        },
        lastByGroup: {
          group.id: {'timestamp': 3000},
        },
      );
      expect(items.map((i) => i.timestamp), [5000, 3000, 2000]);
      expect(items[0].agent?.id, agentOld.id);
      expect(items[1].isGroup, isTrue);
      expect(items[1].group?.id, group.id);
    });

    test('maxItems 在排序完成后截断', () {
      final agents = [
        Agent(name: 'A', persona: '', createdAt: 1000),
        Agent(name: 'B', persona: '', createdAt: 2000),
        Agent(name: 'C', persona: '', createdAt: 3000),
      ];
      final items = buildConversationItems(
        agents: agents,
        groups: const [],
        lastByAgent: const {},
        lastByGroup: const {},
        maxItems: 2,
      );
      expect(items, hasLength(2));
      expect(items[0].agent?.name, 'C');
      expect(items[1].agent?.name, 'B');
    });

    test('maxItems 大于条目数时不截断', () {
      final agent = Agent(name: 'A', persona: '', createdAt: 1000);
      final items = buildConversationItems(
        agents: [agent],
        groups: const [],
        lastByAgent: const {},
        lastByGroup: const {},
        maxItems: 5,
      );
      expect(items, hasLength(1));
    });

    test('timestamp 为 num 子类型时正常解析', () {
      final agent = Agent(name: 'A', persona: '', createdAt: 1000);
      final items = buildConversationItems(
        agents: [agent],
        groups: const [],
        lastByAgent: {
          agent.id: {'timestamp': 4200.0},
        },
        lastByGroup: const {},
      );
      expect(items.single.timestamp, 4200);
    });
  });

  group('last message timestamp helpers', () {
    test('无消息时返回 0', () {
      const state = ConversationLastMessageState();
      expect(lastAgentMessageTimestamp(state, 'a1'), 0);
      expect(lastGroupMessageTimestamp(state, 'g1'), 0);
    });

    test('从聚合 map 取时间戳', () {
      const state = ConversationLastMessageState(
        lastByAgent: {
          'a1': {'timestamp': 123},
        },
        lastByGroup: {
          'g1': {'timestamp': 456},
        },
      );
      expect(lastAgentMessageTimestamp(state, 'a1'), 123);
      expect(lastGroupMessageTimestamp(state, 'g1'), 456);
    });
  });
}
