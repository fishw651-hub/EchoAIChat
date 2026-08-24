import 'dart:async';

import 'package:aichat/models/agent.dart';
import 'package:aichat/models/short_term_message.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/providers/chat_provider.dart';
import 'package:aichat/providers/agent_provider.dart';
import 'package:aichat/providers/memory_provider.dart';
import 'package:aichat/services/database_service.dart';
import 'package:aichat/services/memory_service.dart';
import 'package:aichat/services/secure_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_realtime_connection.dart';
import 'helpers/isolated_test_database.dart';

class _EmptySecureStorage implements SecureStorageBackend {
  @override
  Future<void> delete({required String key}) async {}

  @override
  Future<String?> read({required String key}) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}
}

class _DelayedMemoryService extends MemoryService {
  final addStarted = Completer<void>();
  final releaseAdd = Completer<void>();
  bool delayNextAdd = false;

  @override
  Future<void> loadShortTermFromDb(int limit) async {}

  @override
  Future<ShortTermMessage> addShortTermMessage({
    required String role,
    required String content,
    String? agentId,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    if (!delayNextAdd) {
      return super.addShortTermMessage(
        role: role,
        content: content,
        agentId: agentId,
        imagePath: imagePath,
        imagePaths: imagePaths,
      );
    }
    delayNextAdd = false;
    final targetAgentId = agentId ?? this.agentId;
    addStarted.complete();
    await releaseAdd.future;
    return ShortTermMessage(
      id: 'delayed-message',
      role: role,
      content: content,
      agentId: targetAgentId,
      imagePath: imagePath,
      imagePaths: imagePaths,
    );
  }
}

class _ImmediateMemoryService extends MemoryService {
  @override
  Future<void> loadShortTermFromDb(int limit) async {}

  @override
  Future<ShortTermMessage> addShortTermMessage({
    required String role,
    required String content,
    String? agentId,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    return ShortTermMessage(
      id: 'immediate-${DateTime.now().microsecondsSinceEpoch}',
      role: role,
      content: content,
      agentId: agentId ?? this.agentId,
      imagePath: imagePath,
      imagePaths: imagePaths,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IsolatedTestDatabase testDatabase;

  setUpAll(() async {
    testDatabase = await IsolatedTestDatabase.open(
      'chat-provider-agent-switch',
    );
  });

  tearDownAll(() => testDatabase.close());

  setUp(() async {
    final db = await DatabaseService.database;
    await db.delete('chat_messages');
    await db.delete('short_term_messages');
    await db.delete('agents');
    await DatabaseService.insertAgent(
      Agent(id: 'agent-a', name: 'A', persona: 'A', isActive: true),
    );
    await DatabaseService.insertAgent(
      Agent(id: 'agent-b', name: 'B', persona: 'B'),
    );
  });

  test('发送过程中切换智能体不会把旧消息显示到新会话', () async {
    SharedPreferences.setMockInitialValues({});
    final memoryService = _DelayedMemoryService();
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(memoryService),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(agentProvider).currentAgent?.id, 'agent-a');

    final chatNotifier = container.read(chatProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    memoryService.delayNextAdd = true;

    final sendFuture = chatNotifier.sendMessage('只属于 A 的消息');
    await memoryService.addStarted.future;
    await container.read(agentProvider.notifier).setActiveAgent('agent-b');
    await chatNotifier.reloadChatFromDb('agent-b');
    memoryService.releaseAdd.complete();
    await sendFuture;

    expect(container.read(agentProvider).currentAgent?.id, 'agent-b');
    expect(
      container.read(chatProvider).messages.map((message) => message.content),
      isNot(contains('只属于 A 的消息')),
    );
  });

  test('快速切换后的迟到刷新不会让新消息消失', () async {
    SharedPreferences.setMockInitialValues({});
    final memoryService = _ImmediateMemoryService();
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(memoryService),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final chatNotifier = container.read(chatProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await container.read(agentProvider.notifier).setActiveAgent('agent-b');
    await chatNotifier.reloadChatFromDb('agent-b');
    await container.read(agentProvider.notifier).setActiveAgent('agent-a');

    final database = await DatabaseService.database;
    final blockerEntered = Completer<void>();
    final releaseDatabase = Completer<void>();
    final blocker = database.transaction((_) async {
      blockerEntered.complete();
      await releaseDatabase.future;
    });
    await blockerEntered.future;

    final reloadFuture = chatNotifier.reloadChatFromDb('agent-a');
    await Future<void>.delayed(Duration.zero);
    final sendFuture = chatNotifier.sendMessage('切换后仍应显示');
    for (var attempt = 0; attempt < 20; attempt++) {
      if (container
          .read(chatProvider)
          .messages
          .any((message) => message.content == '切换后仍应显示')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      container.read(chatProvider).messages.map((message) => message.content),
      contains('切换后仍应显示'),
    );

    releaseDatabase.complete();
    await Future.wait([blocker, reloadFuture, sendFuture]);

    expect(
      container.read(chatProvider).messages.map((message) => message.content),
      contains('切换后仍应显示'),
    );
  });

  test('切换智能体后不会继续暴露上一会话的聊天记录', () async {
    await DatabaseService.insertChatMessage(
      role: 'assistant',
      content: '只属于 A 的历史记录',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      agentId: 'agent-a',
    );
    await DatabaseService.insertChatMessage(
      role: 'assistant',
      content: '只属于 B 的历史记录',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      agentId: 'agent-b',
    );
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(_ImmediateMemoryService()),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final chatNotifier = container.read(chatProvider.notifier);
    await container.read(agentProvider.notifier).setActiveAgent('agent-b');
    await chatNotifier.reloadChatFromDb('agent-b');
    expect(
      container.read(chatProvider).messages.map((message) => message.content),
      contains('只属于 B 的历史记录'),
    );

    await container.read(agentProvider.notifier).setActiveAgent('agent-a');
    for (var attempt = 0; attempt < 20; attempt++) {
      if (container
          .read(chatProvider)
          .messages
          .any((message) => message.content == '只属于 A 的历史记录')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      container.read(chatProvider).messages.map((message) => message.content),
      isNot(contains('只属于 B 的历史记录')),
    );
    expect(
      container.read(chatProvider).messages.map((message) => message.content),
      contains('只属于 A 的历史记录'),
    );
  });

  test('高频切换不会删除或混合任一智能体的持久化记录', () async {
    await DatabaseService.insertChatMessage(
      role: 'assistant',
      content: 'A 的持久化记录',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      agentId: 'agent-a',
    );
    await DatabaseService.insertChatMessage(
      role: 'assistant',
      content: 'B 的持久化记录',
      timestampMs: DateTime.now().millisecondsSinceEpoch + 1,
      agentId: 'agent-b',
    );
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(_ImmediateMemoryService()),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    container.read(chatProvider.notifier);
    for (var round = 0; round < 20; round++) {
      await container.read(agentProvider.notifier).setActiveAgent('agent-b');
      await container.read(agentProvider.notifier).setActiveAgent('agent-a');
    }
    for (var attempt = 0; attempt < 50; attempt++) {
      final messages = container.read(chatProvider).messages;
      if (container.read(chatProvider).agentId == 'agent-a' &&
          messages.any((message) => message.content == 'A 的持久化记录')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final visibleContents = container
        .read(chatProvider)
        .messages
        .map((message) => message.content);
    expect(container.read(chatProvider).agentId, 'agent-a');
    expect(visibleContents, contains('A 的持久化记录'));
    expect(visibleContents, isNot(contains('B 的持久化记录')));

    final agentARows = await DatabaseService.getChatMessages(
      agentId: 'agent-a',
    );
    final agentBRows = await DatabaseService.getChatMessages(
      agentId: 'agent-b',
    );
    expect(agentARows.map((row) => row['content']), ['A 的持久化记录']);
    expect(agentBRows.map((row) => row['content']), ['B 的持久化记录']);
  });

  test('删除最后一个智能体后立即清空会话归属和显示记录', () async {
    await DatabaseService.insertChatMessage(
      role: 'assistant',
      content: '即将删除的 B 记录',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      agentId: 'agent-b',
    );
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(_ImmediateMemoryService()),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final chatNotifier = container.read(chatProvider.notifier);
    await container.read(agentProvider.notifier).setActiveAgent('agent-b');
    await chatNotifier.reloadChatFromDb('agent-b');
    expect(container.read(chatProvider).messages, isNotEmpty);

    await container.read(agentProvider.notifier).deleteAgent('agent-a');
    await container.read(agentProvider.notifier).deleteAgent('agent-b');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatProvider).agentId, isNull);
    expect(container.read(chatProvider).messages, isEmpty);
  });

  test('在途生成期间切走再切回：恢复回复中状态且同智能体并发发送被拒', () async {
    SharedPreferences.setMockInitialValues({});
    final memoryService = _DelayedMemoryService();
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(memoryService),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final chatNotifier = container.read(chatProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    memoryService.delayNextAdd = true;

    // 发起 A 的发送并卡在短期记忆写入处（模拟在途生成）
    final sendFuture = chatNotifier.sendMessage('A 的第一条');
    await memoryService.addStarted.future;

    // 切到 B：B 会话不在生成中，isLoading 应为 false
    await container.read(agentProvider.notifier).setActiveAgent('agent-b');
    await chatNotifier.reloadChatFromDb('agent-b');
    expect(container.read(chatProvider).isLoading, isFalse);

    // 切回 A：A 的生成仍在途，isLoading 应恢复为 true
    await container.read(agentProvider.notifier).setActiveAgent('agent-a');
    await chatNotifier.reloadChatFromDb('agent-a');
    expect(container.read(chatProvider).isLoading, isTrue);

    // 在途期间对同一智能体的并发发送被拦截（不落库）
    final dupSent = await chatNotifier.sendMessage('A 的第二条');
    expect(dupSent, isFalse);
    expect(
      (await DatabaseService.getChatMessages(
        agentId: 'agent-a',
      )).map((row) => row['content']),
      isNot(contains('A 的第二条')),
    );

    // 放行走在生成：用户消息按发起智能体落库；结束后 inflight 清除
    memoryService.releaseAdd.complete();
    await sendFuture;
    await chatNotifier.reloadChatFromDb('agent-a');
    expect(container.read(chatProvider).isLoading, isFalse);
    expect(
      (await DatabaseService.getChatMessages(
        agentId: 'agent-a',
      )).map((row) => row['content']),
      contains('A 的第一条'),
    );
    // B 的会话不应混入 A 的消息
    expect(
      (await DatabaseService.getChatMessages(
        agentId: 'agent-b',
      )).map((row) => row['content']),
      isNot(contains('A 的第一条')),
    );
  });

  test('切走后后台落库仍递增 saveRevision（会话列表据以刷新）', () async {
    SharedPreferences.setMockInitialValues({});
    final memoryService = _DelayedMemoryService();
    final container = ProviderContainer(
      overrides: [
        memoryServiceProvider.overrideWithValue(memoryService),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            sessionStore: SecureSessionStore(storage: _EmptySecureStorage()),
            realtimeConnection: FakeRealtimeConnection(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.notifier).ready;

    for (var attempt = 0; attempt < 20; attempt++) {
      if (container.read(agentProvider).currentAgent?.id == 'agent-a') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final chatNotifier = container.read(chatProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    memoryService.delayNextAdd = true;

    final sendFuture = chatNotifier.sendMessage('后台落库的消息');
    await memoryService.addStarted.future;

    // 发送在途时切到 B
    await container.read(agentProvider.notifier).setActiveAgent('agent-b');
    await chatNotifier.reloadChatFromDb('agent-b');
    final revisionBefore = container.read(chatProvider).saveRevision;

    // 放行：scope 已失效，用户消息仍按 agent-a 落库并递增 saveRevision
    memoryService.releaseAdd.complete();
    final sent = await sendFuture;

    expect(sent, isTrue);
    expect(
      container.read(chatProvider).saveRevision,
      greaterThan(revisionBefore),
    );
    expect(
      (await DatabaseService.getChatMessages(
        agentId: 'agent-a',
      )).map((row) => row['content']),
      contains('后台落库的消息'),
    );
    // 当前查看的是 B，消息列表不应出现 A 的消息
    expect(
      container.read(chatProvider).messages.map((m) => m.content),
      isNot(contains('后台落库的消息')),
    );
  });
}
