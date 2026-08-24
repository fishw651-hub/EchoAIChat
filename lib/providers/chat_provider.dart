import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/server_config.dart';
import '../services/api_service.dart';
import '../services/chat_image_service.dart';
import '../services/chat_prompt_builder.dart';
import '../services/chat_stream_assembler.dart';
import '../services/memory_scheduler.dart';
import '../services/memory_service.dart';
import '../services/memory_analysis_coordinator.dart';
import '../services/tool_executor.dart';
import '../services/notification_service.dart';
import '../services/plan_service.dart';
import '../services/database_service.dart';
import '../models/agent.dart';
import '../models/chat_message.dart';
import '../models/short_term_message.dart';
import '../services/chat_runtime_policy.dart';
import '../services/model_list_service.dart';
import '../services/sticker_message_codec.dart';
import '../services/sticker_service.dart';
import '../services/vision_message_builder.dart';
import '../services/image_paths_codec.dart';
import '../services/quota_service.dart';
import '../models/sticker.dart';
import 'memory_provider.dart';
import 'settings_provider.dart';
import 'agent_provider.dart';
import 'auth_provider.dart';
import 'user_profile_provider.dart';

// defaultSystemPersona 已移至 chat_prompt_builder.dart，此处再导出保持既有导入方不变
export '../services/chat_prompt_builder.dart' show defaultSystemPersona;

/// 从 API 消息 map 提取纯文本内容。content 可能是 String 或
/// OpenAI 数组型 content（含 image_url，原生视觉路径）——数组型取 text 部分。
String _contentTextOf(Map<String, dynamic>? message) {
  final content = message?['content'];
  if (content is String) return content;
  if (content is List) {
    for (final part in content) {
      if (part is Map && part['type'] == 'text') {
        return part['text'] as String? ?? '';
      }
    }
    return '[非文本内容]';
  }
  return '';
}

class ChatConversationScope {
  const ChatConversationScope(this.agentId);

  final String agentId;

  bool isCurrent(String? activeAgentId) => agentId == activeAgentId;
}

typedef ScopedMemoryServiceFactory =
    MemoryService Function({
      required String agentId,
      required Iterable<ShortTermMessage> shortTermMessages,
      required int maxShortTermRounds,
    });

class ChatState {
  final String? agentId;
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final List<Map<String, dynamic>> debugMessages;
  final QuotaType? quotaExceeded;

  /// 聊天消息落库计数（含非当前查看智能体的后台落库）。
  /// 会话列表等关注"最新消息"的 UI 监听它以刷新——后台续输出完成时
  /// state.messages 不会变（属于其他智能体），只有这个计数会变。
  final int saveRevision;

  /// 是否还有更早的历史消息未加载（聊天页向上翻页加载）
  final bool hasMoreMessages;

  const ChatState({
    this.agentId,
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.debugMessages = const [],
    this.quotaExceeded,
    this.saveRevision = 0,
    this.hasMoreMessages = false,
  });

  ChatState copyWith({
    String? agentId,
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    List<Map<String, dynamic>>? debugMessages,
    QuotaType? quotaExceeded,
    bool clearQuotaExceeded = false,
    int? saveRevision,
    bool? hasMoreMessages,
  }) {
    return ChatState(
      agentId: agentId ?? this.agentId,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      debugMessages: debugMessages ?? this.debugMessages,
      quotaExceeded: clearQuotaExceeded
          ? null
          : (quotaExceeded ?? this.quotaExceeded),
      saveRevision: saveRevision ?? this.saveRevision,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
    );
  }

  DateTime? get lastUserMessageTime {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) return messages[i].timestamp;
    }
    return null;
  }

  DateTime? get lastAiMessageTime {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isAssistant) return messages[i].timestamp;
    }
    return null;
  }
}

void _log(String msg) {
  debugPrint('║ $msg');
}

void _logH1(String title) {
  debugPrint('');
  debugPrint('╔══════════════════════════════════════════');
  debugPrint('║  $title');
  debugPrint('╚══════════════════════════════════════════');
}

void _logH2(String title) {
  debugPrint('┌──────────────────────────────────────────');
  debugPrint('│  $title');
  debugPrint('└──────────────────────────────────────────');
}

class ChatNotifier extends StateNotifier<ChatState> {
  final MemoryService _memoryService;
  final MemoryAnalysisCoordinator _memoryAnalysisCoordinator;
  final ToolExecutor _toolExecutor;
  final Duration _memoryTimeout;
  final ScopedMemoryServiceFactory _scopedMemoryServiceFactory;
  final Ref _ref;
  String? _lastUserContent;
  int _chatLoadRevision = 0;

  /// 有生成任务在途的智能体 id 集合。生成绑定发起时的 agentId，
  /// 用户切走后流继续跑完并落库（见 sendMessage/_runToolLoop 的 scope 处理）；
  /// 切回该智能体时据此恢复 isLoading（输入守卫生效、可见"回复中"），
  /// 并阻止对同一智能体的并发发送。
  final Set<String> _inflightAgentIds = {};

  /// 系统提示词构建（纯组串逻辑，超时降级），委托给可测的 ChatPromptBuilder
  final ChatPromptBuilder _promptBuilder;

  /// 图片 base64 读取 / 视觉描述调用，委托给可测的 ChatImageService
  final ChatImageService _imageService;

  /// 记忆 AI 触发计数、并发保护与编排，委托给 MemoryAiScheduler
  late final MemoryAiScheduler _memoryAiScheduler;

  ChatNotifier(
    this._ref,
    this._memoryService,
    this._memoryAnalysisCoordinator,
    this._toolExecutor,
    this._memoryTimeout,
    this._scopedMemoryServiceFactory,
  ) : _promptBuilder = ChatPromptBuilder(memoryTimeout: _memoryTimeout),
      _imageService = ChatImageService(),
      super(const ChatState()) {
    // planService / profileService 以闭包惰性读取：调度时刻取最新 provider 值，
    // 与原实现中每次 _scheduleMemoryAnalysis 里 _ref.read 的行为一致
    _memoryAiScheduler = MemoryAiScheduler(
      coordinator: _memoryAnalysisCoordinator,
      planService: () => _ref.read(planServiceProvider),
      profileService: () => _ref.read(userProfileServiceProvider),
    );
    _init();
  }

  Future<void> _init() async {
    final settings = _ref.read(settingsProvider);
    _memoryService.maxShortTermRounds = settings.maxShortTermRounds;
    await reloadChatFromDb(_agentId);
  }

  /// 聊天历史分页大小：只加载最近一页，更早的向上滚动时按需加载，
  /// 避免数千条历史在进聊天页时全量 IO + 全量常驻内存
  static const int _chatPageSize = 100;

  /// 把 DB 行组装成 ChatMessage（贴纸快照批量预取，避免逐条 N+1 查询）
  Future<List<ChatMessage>> _buildChatMessages(
    List<Map<String, dynamic>> rows,
  ) async {
    final snapshots = await DatabaseService.getStickerMessageSnapshots(
      rows.map((r) => r['id'] as int).toList(),
    );
    final messages = <ChatMessage>[];
    for (final row in rows) {
      final dbId = row['id'] as int;
      final snapshot = snapshots[dbId];
      // 多图读取兼容：优先 image_paths（JSON 数组），为空回退 image_path 单图列
      final imagePaths = ImagePathsCodec.resolve(
        imagePathsRaw: row['image_paths'] as String?,
        imagePath: row['image_path'] as String?,
      );
      messages.add(
        ChatMessage(
          dbId: dbId,
          role: row['role'] as String,
          content: row['content'] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            row['timestamp'] as int,
          ),
          shortMemId: row['short_mem_id'] as String?,
          imagePath: row['image_path'] as String?,
          imagePaths: imagePaths.isEmpty ? null : imagePaths,
          stickerId: snapshot?['sticker_id'] as String?,
          stickerDescription: snapshot?['description_snapshot'] as String?,
          stickerPath: snapshot?['image_path_snapshot'] as String?,
        ),
      );
    }
    return messages;
  }

  Future<void> _loadChatMessagesFromDb({
    required String agentId,
    required int loadRevision,
  }) async {
    final targetAgentId = agentId;
    final totalCount = await DatabaseService.getChatMessageCount(targetAgentId);
    final rows = await DatabaseService.getChatMessages(
      agentId: targetAgentId,
      limit: _chatPageSize,
    );
    final messages = await _buildChatMessages(rows);
    // 加载期间容器可能已销毁（测试 tearDown / 快速退出），此后任何
    // _ref/state 访问都会抛 StateError —— 整个合并与落状态段都在保护内
    try {
      if (_agentId != targetAgentId ||
          state.agentId != targetAgentId ||
          loadRevision != _chatLoadRevision) {
        _log('Discarded stale chat load for agent $targetAgentId');
        return;
      }
      final mergedMessages = List<ChatMessage>.from(messages);
      for (final currentMessage in state.messages) {
        final alreadyLoaded = mergedMessages.any((loadedMessage) {
          if (currentMessage.dbId != null && loadedMessage.dbId != null) {
            return currentMessage.dbId == loadedMessage.dbId;
          }
          return currentMessage.shortMemId != null &&
              currentMessage.shortMemId == loadedMessage.shortMemId;
        });
        if (!alreadyLoaded) {
          mergedMessages.add(currentMessage);
        }
      }
      // 分页后内存里可能混有更早页（dbId 更小）与未落库消息（本地打字占位），
      // 按 dbId 归序：未落库的排最后（它们总是最新产生的）
      mergedMessages.sort((a, b) {
        final aId = a.dbId;
        final bId = b.dbId;
        if (aId != null && bId != null) return aId.compareTo(bId);
        if (aId == null && bId == null) {
          return a.timestamp.compareTo(b.timestamp);
        }
        return aId == null ? 1 : -1;
      });
      state = state.copyWith(
        messages: mergedMessages,
        hasMoreMessages: totalCount > messages.length,
      );
      _log(
        'Loaded ${messages.length}/$totalCount chat messages for agent $targetAgentId '
        '(merged ${mergedMessages.length})',
      );
    } on StateError {
      return;
    }
  }

  bool _loadingEarlier = false;

  /// 向上翻页：加载更早的一页历史消息并前插。无更多或正在加载时为空操作。
  Future<void> loadEarlierMessages() async {
    final targetAgentId = _agentId;
    if (targetAgentId == null || !state.hasMoreMessages || _loadingEarlier) {
      return;
    }
    _loadingEarlier = true;
    try {
      // 以当前已加载的最早一条 dbId 为游标
      int? oldestId;
      for (final m in state.messages) {
        if (m.dbId != null && (oldestId == null || m.dbId! < oldestId)) {
          oldestId = m.dbId;
        }
      }
      if (oldestId == null) return;
      final rows = await DatabaseService.getChatMessages(
        agentId: targetAgentId,
        limit: _chatPageSize,
        beforeId: oldestId,
      );
      if (rows.isEmpty) {
        state = state.copyWith(hasMoreMessages: false);
        return;
      }
      // 加载期间会话可能已切换，丢弃过期结果
      if (_agentId != targetAgentId || state.agentId != targetAgentId) return;
      final earlier = await _buildChatMessages(rows);
      final existingIds = state.messages
          .where((m) => m.dbId != null)
          .map((m) => m.dbId!)
          .toSet();
      final prepend = earlier
          .where((m) => !existingIds.contains(m.dbId))
          .toList();
      state = state.copyWith(
        messages: [...prepend, ...state.messages],
        hasMoreMessages: rows.length >= _chatPageSize,
      );
      _log(
        'Prepended ${prepend.length} earlier messages for agent $targetAgentId',
      );
    } finally {
      _loadingEarlier = false;
    }
  }

  Future<void> reloadChatFromDb([String? agentId]) async {
    final effectiveId = agentId ?? _agentId;
    if (effectiveId == null) {
      _chatLoadRevision++;
      _memoryService.setAgentId(null);
      _ref.read(planServiceProvider).setAgentId(null);
      state = const ChatState();
      return;
    }
    if (_agentId != effectiveId) return;
    final loadRevision = ++_chatLoadRevision;
    final isSameConversation = state.agentId == effectiveId;
    state = state.copyWith(
      agentId: effectiveId,
      messages: isSameConversation ? state.messages : const [],
      // 该智能体有后台生成在途时保持"回复中"状态（发送守卫随之生效）
      isLoading: _inflightAgentIds.contains(effectiveId),
      error: null,
    );
    _memoryService.setAgentId(effectiveId);
    _ref.read(planServiceProvider).setAgentId(effectiveId);
    await _memoryService.loadShortTermFromDb(
      _ref.read(settingsProvider).maxShortTermRounds,
    );
    if (_agentId != effectiveId || loadRevision != _chatLoadRevision) return;
    await _loadChatMessagesFromDb(
      agentId: effectiveId,
      loadRevision: loadRevision,
    );
    // await 之后容器可能已销毁（测试 tearDown / 快速退出），
    // _agentId/state 访问会抛 StateError，直接丢弃
    try {
      if (_agentId != effectiveId ||
          state.agentId != effectiveId ||
          loadRevision != _chatLoadRevision) {
        return;
      }
    } on StateError {
      return;
    }
    if (state.messages.isEmpty) {
      final agent = _ref
          .read(agentProvider)
          .agents
          .where((a) => a.id == effectiveId)
          .firstOrNull;
      if (agent?.openingLine != null && agent!.openingLine!.isNotEmpty) {
        _log('Sending opening line for agent ${agent.name}');
        final shortMsg = await _memoryService.addShortTermMessage(
          role: 'assistant',
          content: agent.openingLine!,
          agentId: effectiveId,
        );
        if (_agentId != effectiveId) return;
        final aiMsg = ChatMessage(
          role: 'assistant',
          content: agent.openingLine!,
          shortMemId: shortMsg.id,
        );
        state = state.copyWith(messages: [...state.messages, aiMsg]);
        await _saveChatMessageToDb(aiMsg, agentId: effectiveId);
      }
    }
  }

  /// 清空当前智能体的聊天记录
  Future<void> clearCurrentAgentChatMessages() async {
    await DatabaseService.clearChatMessages(agentId: _agentId);
    state = state.copyWith(messages: []);
  }

  Future<void> _saveChatMessageToDb(ChatMessage msg, {String? agentId}) async {
    final targetAgentId = agentId ?? _agentId;
    if (targetAgentId == null) {
      _log('SKIP _saveChatMessageToDb: no agent');
      return;
    }
    _log('DB: saving chat msg (agent=$targetAgentId, role=${msg.role})');
    final dbId = await DatabaseService.insertChatMessage(
      role: msg.role,
      content: msg.content,
      timestampMs: msg.timestamp.millisecondsSinceEpoch,
      shortMemId: msg.shortMemId,
      agentId: targetAgentId,
      imagePath: msg.imagePath,
      imagePaths: msg.imagePaths,
    );
    if (msg.stickerDescription != null && msg.stickerPath != null) {
      await DatabaseService.insertStickerMessageSnapshot(
        chatMessageId: dbId,
        stickerId: msg.stickerId,
        description: msg.stickerDescription!,
        imagePath: msg.stickerPath!,
        createdAt: msg.timestamp.millisecondsSinceEpoch,
      );
    }
    // 落库计数 +1：非当前智能体的后台落库不改 messages，靠它通知会话列表刷新
    state = state.copyWith(saveRevision: state.saveRevision + 1);
    if (_agentId != targetAgentId || state.agentId != targetAgentId) return;
    state = state.copyWith(
      messages: state.messages.map((m) {
        // 用 shortMemId（稳定标识，copyWith 会保留）+ 引用相等定位待更新消息，
        // 避免无自定义 == 时纯引用比较在消息被 copyWith 替换后失效。
        if (identical(m, msg) ||
            (msg.shortMemId != null && m.shortMemId == msg.shortMemId)) {
          return ChatMessage(
            dbId: dbId,
            role: m.role,
            content: m.content,
            timestamp: m.timestamp,
            toolLogs: m.toolLogs,
            shortMemId: m.shortMemId,
            imagePath: m.imagePath,
            imagePaths: m.imagePaths,
            stickerId: m.stickerId,
            stickerDescription: m.stickerDescription,
            stickerPath: m.stickerPath,
          );
        }
        return m;
      }).toList(),
    );
  }

  MemoryService get memoryService => _memoryService;
  ToolExecutor get toolExecutor => _toolExecutor;
  String? get _agentId => _ref.read(agentProvider).currentAgent?.id;
  String? get rollbackContent => _lastUserContent;

  Map<String, int> _extractTokenUsage(Map<String, dynamic>? responseBody) {
    if (responseBody == null) return {};
    final usage = responseBody['usage'] as Map<String, dynamic>?;
    if (usage == null) return {};
    final prompt = usage['prompt_tokens'] as int?;
    final completion = usage['completion_tokens'] as int?;
    final map = <String, int>{};
    if (prompt != null) map['prompt_tokens'] = prompt;
    if (completion != null) map['completion_tokens'] = completion;
    return map;
  }

  void _recordTokenUsage(
    Map<String, dynamic>? responseBody, {
    String? agentId,
  }) {
    if (responseBody == null) return;
    final usage = responseBody['usage'] as Map<String, dynamic>?;
    if (usage == null) return;
    final prompt = usage['prompt_tokens'] as int?;
    final completion = usage['completion_tokens'] as int?;
    if (prompt == null || completion == null) return;
    final model = responseBody['model'] as String?;
    DatabaseService.insertTokenUsage(
      promptTokens: prompt,
      completionTokens: completion,
      model: model,
      // 后台续输出完成时归属发起智能体，而非当前查看的智能体
      agentId: agentId ?? _agentId,
    );
    _ref.read(settingsProvider.notifier).addTokenUsage(prompt, completion);
  }

  Future<void> _syncMemoryProviders() async {
    try {
      _ref.read(longTermProvider.notifier).loadMemories();
      _ref.read(baseProvider.notifier).loadMemories();
      _log('Memory providers reloaded from DB');
    } catch (e) {
      _log('ERROR syncing memory providers: $e');
    }
  }

  // ═══════════════════════════════════════════
  // 核心：工具调用处理循环
  // ═══════════════════════════════════════════

  /// 私聊无工具循环：AI 直接返回文本回复，记忆管理由 Memory AI 独占
  ///
  /// 完整补全返回后由客户端本地生成渐进事件：chat 工具的 arguments 分片经
  /// [extractStreamingMessage] 提取文本并通过 [onStreamText] 上抛。
  ///
  /// 续输出：用户切换到其他智能体后本地事件消费**不中断**——累积缓冲是纯局部状态，
  /// 仅 [onStreamText]（UI 上抛）在 scope 失效时停止；最终结果由调用方按
  /// scope.agentId 落库，回到该智能体即可看到完整回复。
  Future<_ToolLoopResult> _runToolLoop({
    required ApiService apiService,
    required List<Map<String, dynamic>> apiMessages,
    required DateTime startTime,
    ChatConversationScope? scope,
    List<Map<String, dynamic>> tools = const [],
    Map<String, Sticker> stickers = const {},
    void Function(String partialText)? onStreamText,
  }) async {
    _logH2('API REQUEST (non-stream + local typing)');
    _log('>> calling API  |  msgs:${apiMessages.length}');
    _log(
      'system prompt: ${_contentTextOf(apiMessages.firstOrNull).length} chars',
    );
    final lastContent = _contentTextOf(apiMessages.lastOrNull);
    final cut = lastContent.length < 100 ? lastContent.length : 100;
    _log('last user msg: ${lastContent.substring(0, cut)}');

    final assembler = ToolCallDeltaAssembler();
    final plainContent = StringBuffer();
    Map<String, dynamic>? usage;
    String? usageModel;

    try {
      await for (final event in apiService.chatCompletionStream(
        messages: apiMessages,
        tools: tools,
      )) {
        // 切走仅关闭 UI 上抛，本地事件继续消费到结束（结果仍按发起智能体落库）
        final uiActive = scope == null || scope.isCurrent(_agentId);
        switch (event.type) {
          case ChatStreamEventType.content:
            final delta = event.contentDelta ?? '';
            if (delta.isNotEmpty) {
              plainContent.write(delta);
              if (uiActive) onStreamText?.call(plainContent.toString());
            }
          case ChatStreamEventType.toolCall:
            assembler.add(
              ToolCallDelta(
                index: event.toolCallIndex ?? 0,
                id: event.toolCallId,
                name: event.toolCallName,
                argumentsDelta: event.argumentsDelta,
              ),
            );
            final call = assembler.callAt(event.toolCallIndex ?? 0);
            if (uiActive && call != null && call.name == 'chat') {
              onStreamText?.call(extractStreamingMessage(call.arguments));
            }
          case ChatStreamEventType.usage:
            usage = event.usage;
            usageModel = event.model;
          case ChatStreamEventType.finish:
          case ChatStreamEventType.cost:
          case ChatStreamEventType.done:
            break;
        }
      }
    } catch (e) {
      _log('Non-stream completion failed: $e');
      rethrow;
    }

    // 将本地渐进事件组装回完整 toolCalls 结构
    final toolCalls = <Map<String, dynamic>>[];
    for (final call in assembler.calls) {
      Map<String, dynamic> args;
      try {
        final decoded = jsonDecode(
          call.arguments.isEmpty ? '{}' : call.arguments,
        );
        args = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        // 事件消费异常导致 JSON 不完整：尽力提取已收到的 message 文本
        args = <String, dynamic>{};
        if (call.name == 'chat') {
          final partial = extractStreamingMessage(call.arguments);
          if (partial.isNotEmpty) args = {'message': partial};
        }
      }
      toolCalls.add({'id': call.id, 'name': call.name, 'arguments': args});
    }

    Map<String, dynamic>? tokenUsageBody;
    if (usage != null) {
      tokenUsageBody = {'usage': usage, 'model': ?usageModel};
    }
    return _finalizeToolResult(
      toolCalls: toolCalls,
      plainText: plainContent.toString(),
      stickers: stickers,
      tokenUsageBody: tokenUsageBody,
      scope: scope,
    );
  }

  /// 工具循环收尾：执行 plan 工具、解析 chat 工具（含表情）、记录 token。
  ///
  /// scope 失效（用户已切走）时，计划仍按发起智能体落库；界面日志则只
  /// 在当前会话仍可见时返回。文本结果照常返回，由调用方按发起智能体落库。
  Future<_ToolLoopResult> _finalizeToolResult({
    required List<Map<String, dynamic>> toolCalls,
    required String? plainText,
    required Map<String, Sticker> stickers,
    Map<String, dynamic>? tokenUsageBody,
    bool interrupted = false,
    ChatConversationScope? scope,
  }) async {
    final uiActive = scope == null || scope.isCurrent(_agentId);
    if (uiActive) _toolExecutor.clearLogs();
    final planCall = toolCalls.cast<Map<String, dynamic>?>().firstWhere(
      (call) => call?['name'] == 'plan',
      orElse: () => null,
    );
    if (planCall?['arguments'] is Map) {
      await _toolExecutor.execute(
        'plan',
        Map<String, dynamic>.from(planCall!['arguments'] as Map),
        agentId: scope?.agentId,
      );
    }
    final chatCall = toolCalls.cast<Map<String, dynamic>?>().firstWhere(
      (call) => call?['name'] == 'chat',
      orElse: () => null,
    );
    final arguments = chatCall?['arguments'] is Map
        ? Map<String, dynamic>.from(chatCall!['arguments'] as Map)
        : null;
    final parsedArguments = arguments == null
        ? null
        : StickerMessageCodec.parseChatArguments(arguments);
    final sticker = parsedArguments?.stickerId == null
        ? null
        : stickers[parsedArguments!.stickerId!];
    final textContent = parsedArguments == null
        ? (plainText ?? '')
        : StickerMessageCodec.composeContent(
            parsedArguments.message,
            sticker?.description,
          );
    _log('>>> FINAL: text (${textContent.length} chars)');
    _recordTokenUsage(tokenUsageBody, agentId: scope?.agentId);
    final tokens = _extractTokenUsage(tokenUsageBody);
    return _ToolLoopResult(
      chatMessage: textContent.isNotEmpty ? textContent : null,
      stickerId: sticker?.id,
      stickerDescription: sticker?.description,
      stickerPath: sticker?.imagePath,
      promptTokens: tokens['prompt_tokens'],
      completionTokens: tokens['completion_tokens'],
      toolLogs: uiActive
          ? List<ToolExecutionLog>.from(_toolExecutor.executionLogs)
          : const [],
      interrupted: interrupted,
    );
  }

  // ═══ 普通消息发送 ═══

  /// 注入一条计划消息（由 PlanService 到时间触发，作为智能体主动发出的消息）
  /// 此方法不会触发 AI 调用，仅作为智能体的"主动发言"显示并存储。
  /// agentId 为计划归属的智能体（调度时刻固定），缺省回退当前智能体。
  Future<void> deliverPlannedMessage(String content, {String? agentId}) async {
    if (content.trim().isEmpty) return;
    final targetAgentId = agentId ?? _agentId;
    if (targetAgentId == null) return;
    _logH1('PLANNED MESSAGE TRIGGERED');
    _log(content);

    final shortMsg = await _memoryService.addShortTermMessage(
      role: 'assistant',
      content: content,
      agentId: targetAgentId,
    );
    final aiMsg = ChatMessage(
      role: 'assistant',
      content: content,
      shortMemId: shortMsg.id,
    );
    if (_agentId == targetAgentId) {
      state = state.copyWith(messages: [...state.messages, aiMsg]);
    }
    await _saveChatMessageToDb(aiMsg, agentId: targetAgentId);
  }

  /// 发送用户消息（可携带文字、表情、单图 imagePath 或多图 imagePaths）。
  /// 返回 true = 消息流程完成（含范围失效但消息已落库的情形）；
  /// 返回 false = 发送失败（配额/网络/识别失败等），调用方可据此保留输入/暂存图。
  ///
  /// 续输出：发起后生成任务绑定发起时的 agentId，用户切走不中断——流继续
  /// 跑完并按发起智能体落库（见 _sendMessageInternal 的 scope 处理）。
  /// 同一智能体已有生成在途时直接返回 false（切走又切回期间由
  /// _inflightAgentIds 拦住并发发送；同会话内由 state.isLoading 拦截）。
  Future<bool> sendMessage(
    String content, {
    Sticker? sticker,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    final agentId = _agentId;
    if (agentId != null && !_inflightAgentIds.add(agentId)) return false;
    try {
      return await _sendMessageInternal(
        content,
        sticker: sticker,
        imagePath: imagePath,
        imagePaths: imagePaths,
      );
    } finally {
      _releaseInflightAgent(agentId);
    }
  }

  /// 生成任务结束时同步释放在途标记和当前会话的 loading 状态。
  /// 切换到其他智能体期间，reload 会为目标会话恢复 loading；若用户在
  /// finally 前切回发起会话，必须在这里补上对应的 false 状态。
  void _releaseInflightAgent(String? agentId) {
    if (agentId == null) return;
    _inflightAgentIds.remove(agentId);
    if (_agentId == agentId && state.agentId == agentId && state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> _sendMessageInternal(
    String content, {
    Sticker? sticker,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    // 多图归一：imagePaths 优先，单图 imagePath 归一为单元素列表
    final effectiveImagePaths = (imagePaths != null && imagePaths.isNotEmpty)
        ? imagePaths
        : (imagePath != null ? [imagePath] : null);
    final normalizedContent = StickerMessageCodec.composeContent(
      content,
      sticker?.description,
    );
    if (normalizedContent.isEmpty && effectiveImagePaths == null) return false;
    if (state.isLoading) return false;

    final requestAgentId = _agentId;
    if (requestAgentId == null) {
      state = state.copyWith(error: '请先选择智能体');
      return false;
    }
    final scope = ChatConversationScope(requestAgentId);
    final requestAgent = _ref
        .read(agentProvider)
        .agents
        .where((agent) => agent.id == requestAgentId)
        .firstOrNull;
    final requestShortTermSnapshot = _memoryService.shortTermMessages
        .where((message) => message.agentId == requestAgentId)
        .toList(growable: false);

    // 图片消息：短期记忆先存 [图片] 占位 + image_path/image_paths（绑定视觉路径
    // 稍后用描述替换占位；原生视觉路径构建上下文时按路径现读挂图，见下方
    // attachImagesToMessages）；UI 气泡展示用户原文（空则 [图片]）
    final userText = normalizedContent;
    final shortTermContent = effectiveImagePaths == null
        ? userText
        : VisionMessageBuilder.historyPlaceholder(userText);
    final displayContent = effectiveImagePaths != null && userText.isEmpty
        ? VisionMessageBuilder.imagePlaceholder
        : userText;

    _logH1('NEW USER MESSAGE');
    _log(shortTermContent);

    final shortMsg = await _memoryService.addShortTermMessage(
      role: 'user',
      content: shortTermContent,
      agentId: scope.agentId,
      imagePath: effectiveImagePaths?.first,
      imagePaths: effectiveImagePaths,
    );
    final requestMemoryService = _scopedMemoryServiceFactory(
      agentId: scope.agentId,
      shortTermMessages: [
        ...requestShortTermSnapshot.where(
          (message) => message.id != shortMsg.id,
        ),
        shortMsg,
      ],
      maxShortTermRounds: _memoryService.maxShortTermRounds,
    );
    final userMsg = ChatMessage(
      role: 'user',
      content: displayContent,
      shortMemId: shortMsg.id,
      imagePath: effectiveImagePaths?.first,
      imagePaths: effectiveImagePaths,
      stickerId: sticker?.id,
      stickerDescription: sticker?.description,
      stickerPath: sticker?.imagePath,
    );
    if (scope.isCurrent(_agentId)) {
      state = state.copyWith(
        messages: [...state.messages, userMsg],
        error: null,
      );
    }
    await _saveChatMessageToDb(userMsg, agentId: scope.agentId);

    // 启动早期 auth 尚未从存储恢复完成时，jwt/apiKey 会短暂为空——先等
    // 初始化结束（ready 幂等，完成后立即返回）再判登录态，避免误报
    // "请先登录"；配额预检的鉴权头同样在 _init 末尾注入，一并覆盖。
    await _ref.read(authProvider.notifier).ready;

    final auth = _ref.read(authProvider);
    const runtime = ChatRuntimePolicy.standard;
    final selectedModel = _ref.read(settingsProvider).selectedModel;
    final model = selectedModel.isEmpty
        ? ModelListService.defaultModel
        : selectedModel;
    final baseUrl = ServerConfig.baseUrl;
    var apiKey = auth.apiKey ?? '';

    _log('┌── PRE-FLIGHT CHECK ───────────────────');
    _log('│ Base URL: $baseUrl');
    _log(
      '│ API Key: ${apiKey.isEmpty ? "EMPTY" : "${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}"}',
    );
    _log('│ Model: ${model.isEmpty ? "EMPTY" : model}');
    _log('└───────────────────────────────────────');

    if (apiKey.isEmpty) {
      // 本地无 API Key：先试静默重登，成功则继续正常发送流程
      final restored = await _ref.read(authProvider.notifier).trySilentReAuth();
      if (restored) apiKey = _ref.read(authProvider).apiKey ?? '';
      if (apiKey.isEmpty) {
        final uiActive = scope.isCurrent(_agentId);
        if (uiActive) {
          state = state.copyWith(isLoading: false, error: '请先登录账户');
        }
        return !uiActive;
      }
      _log('│ API Key restored via silent re-auth');
    }
    if (scope.isCurrent(_agentId)) {
      state = state.copyWith(isLoading: true);
    }
    final startTime = DateTime.now();

    final streamPlaceholderKey =
        'stream-${scope.agentId}-${DateTime.now().microsecondsSinceEpoch}';

    try {
      await _prepareMemoryContext(requestMemoryService);

      // ═══ 图片消息：按所选模型视觉能力分流 ═══
      var streamPlaceholderInserted = false;
      // 所选模型的视觉能力：本次发图分流 + 历史短期消息挂图都要用
      final chatModelInfo = ModelListService.findById(
        _ref.read(modelListProvider).models,
        model,
      );
      if (effectiveImagePaths != null) {
        final boundVisionId = chatModelInfo?.visionModelId ?? '';
        if (chatModelInfo?.nativeVision != true && boundVisionId.isNotEmpty) {
          // 非原生 + 绑定视觉模型：逐张串行调用视觉模型生成详细描述后合并，
          // 任一张失败抛异常走下方 catch（整体发送失败并退配额，不静默吞）
          if (scope.isCurrent(_agentId)) {
            state = state.copyWith(
              messages: [
                ...state.messages,
                ChatMessage(
                  role: 'assistant',
                  content: '正在识别图片…',
                  isStreaming: true,
                  shortMemId: streamPlaceholderKey,
                ),
              ],
            );
            streamPlaceholderInserted = true;
          }
          final descriptions = await _imageService.describeImages(
            visionModelId: boundVisionId,
            apiKey: apiKey,
            baseUrl: baseUrl,
            userText: userText,
            imagePaths: effectiveImagePaths,
          );
          // 用包含图片内容的完整描述替换短期记忆中的 [图片] 占位，
          // 后续构建的 apiMessages 与历史上下文都会带上描述
          await requestMemoryService.updateShortTermContent(
            shortMsg.id,
            VisionMessageBuilder.composeMultiDescribedContent(
              userText: userText,
              descriptions: descriptions,
            ),
          );
          _log('Vision description applied (${descriptions.length} images)');
        }
      }

      final systemContent = await _buildSystemPrompt(
        memoryService: requestMemoryService,
        agent: requestAgent,
      );

      // 短期记忆上下文：原生视觉模型时给窗口内带图消息挂真实图片
      // （最多 maxAttachedImages 张最近图片；文件缺失降级 [图片] 文本占位）。
      // debugMsgs 用挂图前的纯文本版本，避免 base64 进调试日志。
      final shortTermMaps = requestMemoryService.getShortTermAsMessages();
      final apiMessages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemContent},
        ...await VisionMessageBuilder.attachImagesToMessages(
          shortTermMaps,
          nativeVision: chatModelInfo?.nativeVision == true,
          readImageBase64: _imageService.readImageBase64,
        ),
      ];

      final debugMsgs = [
        {'role': 'system', 'content': systemContent},
        for (final m in shortTermMaps)
          {'role': m['role'], 'content': m['content']},
      ];

      final apiService = ApiService.fromConfig(
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        thinkingMode: runtime.thinkingMode,
        temperature: runtime.temperature!,
        clientAgentId: scope.agentId,
        requestKind: 'chat',
      );

      apiMessages[0]['agent_id'] = scope.agentId;

      final availableStickerList = await StickerService.listActive();
      final availableStickers = {
        for (final sticker in availableStickerList) sticker.id: sticker,
      };
      final privateTools = ApiService.getPrivateToolDefinitions(
        stickers: availableStickerList
            .map(
              (sticker) => {
                'id': sticker.id,
                'description': sticker.description,
              },
            )
            .toList(growable: false),
      );

      // 记忆轮次计数、读取和分析都在主回复落库后后台执行，任何记忆
      // SharedPreferences/API/数据库延迟都不得占用聊天的 isLoading 生命周期。
      // 本地打字占位消息：发起 API 调用前先插入空消息，按渐进事件更新
      // （绑定视觉路径已在识别图片前插入过占位，不重复插入）
      if (!streamPlaceholderInserted && scope.isCurrent(_agentId)) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(
              role: 'assistant',
              content: '',
              isStreaming: true,
              shortMemId: streamPlaceholderKey,
            ),
          ],
        );
      }

      // 本地打字渲染节流（对齐群聊 50ms flush 模式）：未节流时每个本地分片
      // 都会复制消息列表并触发全屏 rebuild，长回复渲染开销随文本平方增长。
      Timer? streamThrottle;
      var latestPartial = '';
      void flushPartial() {
        streamThrottle?.cancel();
        streamThrottle = null;
        if (!scope.isCurrent(_agentId)) return;
        final msgs = List<ChatMessage>.from(state.messages);
        final idx = msgs.indexWhere(
          (m) => m.shortMemId == streamPlaceholderKey && m.isStreaming,
        );
        if (idx == -1) return; // 占位消息已被移除
        if (msgs[idx].content == latestPartial) return;
        msgs[idx] = msgs[idx].copyWith(content: latestPartial);
        state = state.copyWith(messages: msgs);
      }

      void onStreamText(String partial) {
        if (!scope.isCurrent(_agentId)) return;
        latestPartial = partial;
        streamThrottle ??= Timer(
          const Duration(milliseconds: 50),
          flushPartial,
        );
      }

      final result = await _runToolLoop(
        apiService: apiService,
        apiMessages: apiMessages,
        startTime: startTime,
        scope: scope,
        tools: privateTools,
        stickers: availableStickers,
        onStreamText: onStreamText,
      );

      // 结算前做最后一次 flush：50ms 窗口内的尾部 delta 不丢失。
      // 异常路径不占优清理：Timer 是一次性的，占位消息移除后 flush 自然变 no-op。
      flushPartial();

      if (result.chatMessage != null && result.chatMessage!.isNotEmpty) {
        _log('AI reply: ${result.chatMessage}');
        await _finalizeAiReply(
          result,
          debugMsgs,
          scope,
          placeholderKey: streamPlaceholderKey,
        );
        _scheduleMemoryAnalysis(
          agentId: scope.agentId,
          apiKey: apiKey,
          baseUrl: baseUrl,
          temperature: runtime.temperature!,
          persona: requestAgent?.persona ?? defaultSystemPersona,
          worldview: requestAgent?.worldview ?? '',
          enableProfile: requestAgent?.realInfoEnabled == true,
        );
        if (result.interrupted && scope.isCurrent(_agentId)) {
          state = state.copyWith(error: '连接中断，已保留部分回复');
        }
      } else if (scope.isCurrent(_agentId)) {
        _removeStreamPlaceholder(streamPlaceholderKey);
        state = state.copyWith(isLoading: false, error: '智能体本轮没有返回有效回复');
      }
    } on QuotaExceededException catch (e) {
      if (!scope.isCurrent(_agentId)) return true;
      _log('QuotaExceeded: ${e.type.apiValue} - $e');
      _removeStreamPlaceholder(streamPlaceholderKey);
      state = state.copyWith(isLoading: false, quotaExceeded: e.type);
      return false;
    } on ModelNotAllowedException catch (e) {
      if (!scope.isCurrent(_agentId)) return true;
      _removeStreamPlaceholder(streamPlaceholderKey);
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    } on ThinkingNotAllowedException catch (e) {
      if (!scope.isCurrent(_agentId)) return true;
      _removeStreamPlaceholder(streamPlaceholderKey);
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    } on ApiException catch (e) {
      _log('ApiException: $e');
      if (!scope.isCurrent(_agentId)) return true;
      _removeStreamPlaceholder(streamPlaceholderKey);
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    } catch (e) {
      _log('ERROR: $e');
      final errorStr = e.toString();
      final isContextOverflow =
          errorStr.contains('context_length') ||
          errorStr.contains('maximum context') ||
          errorStr.contains('token');
      if (!scope.isCurrent(_agentId) && !isContextOverflow) return true;
      if (scope.isCurrent(_agentId)) {
        _removeStreamPlaceholder(streamPlaceholderKey);
      }

      if (isContextOverflow) {
        try {
          await _compressMemoryContext(requestMemoryService);

          final systemContent2 = await _buildSystemPrompt(
            memoryService: requestMemoryService,
            agent: requestAgent,
          );
          // 上下文溢出重试：不再挂图（nativeVision: false 仅剥离图片键，
          // 图片消息保持 [图片] 文本占位，控制重试请求的体积）
          final apiMessages2 = <Map<String, dynamic>>[
            {'role': 'system', 'content': systemContent2},
            ...await VisionMessageBuilder.attachImagesToMessages(
              requestMemoryService.getShortTermAsMessages(),
              nativeVision: false,
            ),
          ];

          final retryModel = _ref.read(settingsProvider).selectedModel;
          final apiService2 = ApiService.fromConfig(
            model: retryModel.isEmpty
                ? ModelListService.defaultModel
                : retryModel,
            apiKey: _ref.read(authProvider).apiKey ?? '',
            baseUrl: ServerConfig.baseUrl,
            thinkingMode: ChatRuntimePolicy.standard.thinkingMode,
            temperature: ChatRuntimePolicy.standard.temperature!,
            clientAgentId: scope.agentId,
            requestKind: 'chat',
          );

          final result2 = await _runToolLoop(
            apiService: apiService2,
            apiMessages: apiMessages2,
            startTime: DateTime.now(),
            scope: scope,
          );

          if (result2.chatMessage != null && result2.chatMessage!.isNotEmpty) {
            await _finalizeAiReply(
              result2,
              const <Map<String, dynamic>>[],
              scope,
            );
            return true;
          }
        } on ApiException catch (retryError) {
          if (scope.isCurrent(_agentId)) {
            state = state.copyWith(
              isLoading: false,
              error: retryError.toString(),
            );
            return false;
          }
          return true;
        } catch (retryError) {
          if (scope.isCurrent(_agentId)) {
            state = state.copyWith(
              isLoading: false,
              error: '重试后仍失败: $retryError',
            );
            return false;
          }
          return true;
        }
      }
      if (scope.isCurrent(_agentId)) {
        state = state.copyWith(isLoading: false, error: '请求失败: $e');
        return false;
      }
      return true;
    }
    return true;
  }

  /// 清除配额超限标记（用户关闭弹窗后调用）
  void clearQuotaExceeded() {
    state = state.copyWith(clearQuotaExceeded: true);
  }

  /// AI 回复收尾：写短期记忆 + 落库。
  /// [placeholderKey] 非空时替换对应的本地打字占位消息，否则直接追加。
  Future<void> _finalizeAiReply(
    _ToolLoopResult result,
    List<Map<String, dynamic>> debugMsgs,
    ChatConversationScope scope, {
    String? placeholderKey,
  }) async {
    final fullContent = result.chatMessage!;
    final shortAi = await _memoryService.addShortTermMessage(
      role: 'assistant',
      content: fullContent,
      agentId: scope.agentId,
    );
    final toolLogs = result.toolLogs.isNotEmpty ? result.toolLogs : null;
    final finalMsg = ChatMessage(
      role: 'assistant',
      content: fullContent,
      toolLogs: toolLogs,
      shortMemId: shortAi.id,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      stickerId: result.stickerId,
      stickerDescription: result.stickerDescription,
      stickerPath: result.stickerPath,
    );
    if (!scope.isCurrent(_agentId)) {
      await _saveChatMessageToDb(finalMsg, agentId: scope.agentId);
      return;
    }
    final msgs = List<ChatMessage>.from(state.messages);
    final idx = placeholderKey == null
        ? -1
        : msgs.indexWhere(
            (m) => m.shortMemId == placeholderKey && m.isStreaming,
          );
    if (idx == -1) {
      msgs.add(finalMsg);
    } else {
      msgs[idx] = finalMsg;
    }
    state = state.copyWith(
      messages: msgs,
      isLoading: false,
      debugMessages: debugMsgs,
    );
    unawaited(_ref.read(authProvider.notifier).refreshUserProfile());

    // 保存最终消息到数据库
    await _saveChatMessageToDb(finalMsg, agentId: scope.agentId);
  }

  /// 移除本地打字占位消息（失败路径用）。
  void _removeStreamPlaceholder(String placeholderKey) {
    final msgs = state.messages
        .where((m) => !(m.shortMemId == placeholderKey && m.isStreaming))
        .toList();
    if (msgs.length != state.messages.length) {
      state = state.copyWith(messages: msgs);
    }
  }

  Future<void> handleEmptyResponse(
    ApiService apiService,
    List<Map<String, dynamic>> apiMessages,
    DateTime startTime,
    List<Map<String, dynamic>> debugMsgs,
    ChatConversationScope scope,
  ) async {
    _log('Empty response — retry 1/2...');
    await Future.delayed(const Duration(seconds: 1));
    if (!scope.isCurrent(_agentId)) return;

    try {
      final retry1 = await _runToolLoop(
        apiService: apiService,
        apiMessages: apiMessages,
        startTime: DateTime.now(),
        scope: scope,
      );
      if (!scope.isCurrent(_agentId)) return;
      if (retry1.chatMessage != null && retry1.chatMessage!.isNotEmpty) {
        _log('Retry 1 OK');
        await _finalizeAiReply(retry1, debugMsgs, scope);
        return;
      }

      _log('Retry 1 empty — checking API...');
      final online = await ApiService.testConnection(
        baseUrl: ServerConfig.baseUrl,
        apiKey: _ref.read(authProvider).apiKey ?? '',
      );
      if (!scope.isCurrent(_agentId)) return;
      final isOnline = online.startsWith('连接成功');

      if (isOnline) {
        _log('API online — retry 2/2...');
        final retry2 = await _runToolLoop(
          apiService: apiService,
          apiMessages: apiMessages,
          startTime: DateTime.now(),
          scope: scope,
        );
        if (!scope.isCurrent(_agentId)) return;
        if (retry2.chatMessage != null && retry2.chatMessage!.isNotEmpty) {
          _log('Retry 2 OK');
          await _finalizeAiReply(retry2, debugMsgs, scope);
          return;
        }
      }

      _rollbackLastUserMessage();
      state = state.copyWith(
        isLoading: false,
        error: isOnline ? '发送失败，请重试' : '网络连接失败',
      );
    } catch (e) {
      if (!scope.isCurrent(_agentId)) return;
      _rollbackLastUserMessage();
      state = state.copyWith(isLoading: false, error: '发送失败: $e');
    }
  }

  void _rollbackLastUserMessage() {
    final msgs = List<ChatMessage>.from(state.messages);
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isUser) {
        final removed = msgs.removeAt(i);
        _lastUserContent = removed.content;
        if (removed.shortMemId != null) {
          _memoryService.deleteShortTermMessage(removed.shortMemId!);
        }
        if (removed.dbId != null) {
          DatabaseService.deleteChatMessage(removed.dbId!);
        }
        state = state.copyWith(messages: msgs);
        return;
      }
    }
  }

  /// 重新生成。与 sendMessage 同样支持切走续跑：生成绑定发起时的智能体
  /// （scope），切走后流继续跑完并按发起智能体落库；同一智能体生成在途时
  /// 忽略重复触发。
  Future<void> regenerateMessage(int messageIndex) async {
    final agentId = _agentId;
    if (agentId == null) return;
    if (!_inflightAgentIds.add(agentId)) return;
    try {
      await _regenerateMessageInternal(
        messageIndex,
        ChatConversationScope(agentId),
      );
    } finally {
      _releaseInflightAgent(agentId);
    }
  }

  Future<void> _regenerateMessageInternal(
    int messageIndex,
    ChatConversationScope scope,
  ) async {
    if (state.isLoading) return;
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    final msg = state.messages[messageIndex];
    if (msg.isUser) return;

    _logH1('REGENERATE');

    final requestAgent = _ref
        .read(agentProvider)
        .agents
        .where((agent) => agent.id == scope.agentId)
        .firstOrNull;
    final requestMaxShortTermRounds = _memoryService.maxShortTermRounds;

    final newMessages = List<ChatMessage>.from(state.messages)
      ..removeAt(messageIndex);
    state = state.copyWith(messages: newMessages, isLoading: true);

    try {
      if (msg.dbId != null) {
        await DatabaseService.deleteChatMessage(msg.dbId!);
      }
      if (msg.shortMemId != null) {
        await _memoryService.deleteShortTermMessage(
          msg.shortMemId!,
          agentId: scope.agentId,
        );
      }
      final requestShortTermSnapshot =
          await DatabaseService.getShortTermMessages(agentId: scope.agentId);
      final requestMemoryService = _scopedMemoryServiceFactory(
        agentId: scope.agentId,
        shortTermMessages: requestShortTermSnapshot,
        maxShortTermRounds: requestMaxShortTermRounds,
      );

      var apiKey = _ref.read(authProvider).apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        // 本地无 API Key：先试静默重登，成功则继续
        final restored = await _ref
            .read(authProvider.notifier)
            .trySilentReAuth();
        if (restored) apiKey = _ref.read(authProvider).apiKey;
        if (apiKey == null || apiKey.isEmpty) {
          if (scope.isCurrent(_agentId)) {
            state = state.copyWith(isLoading: false, error: '请先登录账户');
          }
          return;
        }
      }

      final selectedModel = _ref.read(settingsProvider).selectedModel;
      final apiService = ApiService.fromConfig(
        model: selectedModel.isEmpty
            ? ModelListService.defaultModel
            : selectedModel,
        apiKey: apiKey,
        baseUrl: ServerConfig.baseUrl,
        thinkingMode: ChatRuntimePolicy.standard.thinkingMode,
        temperature: ChatRuntimePolicy.standard.temperature!,
        clientAgentId: requestAgent?.id ?? scope.agentId,
        requestKind: 'chat',
      );
      await _prepareMemoryContext(requestMemoryService);
      final systemContent = await _buildSystemPrompt(
        memoryService: requestMemoryService,
        agent: requestAgent,
      );
      // 原生视觉模型：给短期窗口内带图消息挂真实图片（重新生成也应看到图）
      final regenerateModelInfo = ModelListService.findById(
        _ref.read(modelListProvider).models,
        selectedModel.isEmpty ? ModelListService.defaultModel : selectedModel,
      );
      final apiMessages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemContent},
        ...await VisionMessageBuilder.attachImagesToMessages(
          requestMemoryService.getShortTermAsMessages(),
          nativeVision: regenerateModelInfo?.nativeVision == true,
          readImageBase64: _imageService.readImageBase64,
        ),
      ];
      apiMessages[0]['agent_id'] = scope.agentId;

      while (apiMessages.isNotEmpty && apiMessages.last['role'] != 'user') {
        apiMessages.removeLast();
      }

      final result = await _runToolLoop(
        apiService: apiService,
        apiMessages: apiMessages,
        startTime: DateTime.now(),
        scope: scope,
      );

      if (result.chatMessage != null && result.chatMessage!.isNotEmpty) {
        // 收尾复用统一下沉逻辑：当前会话追加并刷新 UI，切走仅按发起智能体落库
        await _finalizeAiReply(result, const <Map<String, dynamic>>[], scope);
      } else if (scope.isCurrent(_agentId)) {
        state = state.copyWith(isLoading: false, error: '重新生成失败');
      }
    } catch (e) {
      if (scope.isCurrent(_agentId)) {
        state = state.copyWith(isLoading: false, error: '重新生成失败: $e');
      }
    }
  }

  // ═══ 系统提示词构建 ═══

  /// 委托 [ChatPromptBuilder]：解析作用域默认值（缺省用全局 _memoryService /
  /// 当前智能体）后交给纯组串构建器，超时/异常由其内部降级为精简提示词。
  Future<String> _buildSystemPrompt({
    MemoryService? memoryService,
    Agent? agent,
  }) {
    final scopedMemoryService = memoryService ?? _memoryService;
    return _promptBuilder.build(
      readLongTerm: scopedMemoryService.getLongTermMemories,
      readBase: scopedMemoryService.getBaseMemories,
      agent: agent ?? _ref.read(agentProvider).currentAgent,
    );
  }

  Future<void> _prepareMemoryContext(MemoryService memoryService) async {
    try {
      final estimatedTokens = await memoryService
          .estimateContextTokens()
          .timeout(_memoryTimeout);
      if (estimatedTokens <= 7000) return;
      await _compressMemoryContext(memoryService);
    } catch (e) {
      _log('Prepare memory context failed; continuing without compression: $e');
    }
  }

  Future<void> _compressMemoryContext(MemoryService memoryService) async {
    Future<void> run(String label, Future<void> Function() operation) async {
      try {
        await operation().timeout(_memoryTimeout);
      } catch (e) {
        _log('Compress $label failed; continuing: $e');
      }
    }

    await Future.wait<void>([
      run('long-term memories', () async {
        await memoryService.compressLongTerm(10);
      }),
      run('base memories', () async {
        await memoryService.compressBaseMemories(3);
      }),
    ]);
    memoryService.compressShortTerm(5);
  }

  /// 委托 [MemoryAiScheduler]：触发计数、并发保护、记忆 AI 编排；
  /// 分析成功后仅当受影响的是当前查看智能体时刷新记忆 providers。
  void _scheduleMemoryAnalysis({
    required String agentId,
    required String apiKey,
    required String baseUrl,
    required double temperature,
    required String persona,
    required String worldview,
    required bool enableProfile,
  }) {
    _memoryAiScheduler.schedule(
      agentId: agentId,
      apiKey: apiKey,
      baseUrl: baseUrl,
      temperature: temperature,
      persona: persona,
      worldview: worldview,
      enableProfile: enableProfile,
      onApplied: (affectedAgentId) async {
        try {
          if (_agentId == affectedAgentId) await _syncMemoryProviders();
        } on StateError {
          // Provider 容器已销毁，数据库结果仍然有效，无需刷新界面。
        }
      },
    );
  }

  Future<void> clearChat() async {
    _memoryService.clearShortTerm();
    DatabaseService.clearChatMessages(agentId: _agentId);
    // 重置 Memory AI 触发计数器：清空聊天后对话轮次从头计起
    final agentId = _agentId;
    if (agentId != null) {
      await _memoryAiScheduler.resetRounds(agentId);
    }
    state = state.copyWith(messages: [], error: null, debugMessages: []);
  }

  Future<void> addSystemMessage(String content) async {
    final shortMsg = await _memoryService.addShortTermMessage(
      role: 'assistant',
      content: content,
    );
    final msg = ChatMessage(
      role: 'assistant',
      content: content,
      shortMemId: shortMsg.id,
    );
    state = state.copyWith(messages: [...state.messages, msg]);
    await _saveChatMessageToDb(msg);
  }

  Future<void> deleteMessageFrom(int index) async {
    final msgs = state.messages;
    if (index < 0 || index >= msgs.length) return;
    final toDelete = msgs.sublist(index);
    for (final msg in toDelete) {
      if (msg.dbId != null) {
        await DatabaseService.deleteChatMessage(msg.dbId!);
      }
      if (msg.shortMemId != null) {
        await _memoryService.deleteShortTermMessage(msg.shortMemId!);
      }
    }
    state = state.copyWith(messages: msgs.sublist(0, index));
  }

  /// 用户重写 AI 消息：聊天表与短期记忆同步改写，
  /// 后续对话上下文与记忆 AI 均以改写后内容为准。
  Future<void> rewriteMessage(int index, String newContent) async {
    final msgs = state.messages;
    if (index < 0 || index >= msgs.length) return;
    final msg = msgs[index];
    if (msg.isUser || msg.isStreaming) return;
    final trimmed = newContent.trim();
    if (trimmed.isEmpty || trimmed == msg.content) return;

    if (msg.dbId != null) {
      await DatabaseService.updateChatMessageContent(msg.dbId!, trimmed);
    }
    if (msg.shortMemId != null) {
      await DatabaseService.updateShortTermMessageContent(
        msg.shortMemId!,
        trimmed,
        agentId: _agentId,
      );
    }
    state = state.copyWith(
      messages: [
        for (var i = 0; i < msgs.length; i++)
          i == index ? msgs[i].copyWith(content: trimmed) : msgs[i],
      ],
      saveRevision: state.saveRevision + 1,
    );
  }
}

class _ToolLoopResult {
  final String? chatMessage;
  final List<ToolExecutionLog> toolLogs;
  final int? promptTokens;
  final int? completionTokens;
  final String? stickerId;
  final String? stickerDescription;
  final String? stickerPath;

  /// 流中途断开：chatMessage 为已接收的部分内容。
  final bool interrupted;
  _ToolLoopResult({
    this.chatMessage,
    this.toolLogs = const [],
    this.promptTokens,
    this.completionTokens,
    this.stickerId,
    this.stickerDescription,
    this.stickerPath,
    this.interrupted = false,
  });
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final planServiceProvider = Provider<PlanService>((ref) {
  final ps = PlanService(
    notificationService: ref.read(notificationServiceProvider),
  );
  ref.onDispose(() => ps.dispose());
  return ps;
});

final toolExecutorProvider = Provider<ToolExecutor>((ref) {
  return ToolExecutor(
    memoryService: ref.read(memoryServiceProvider),
    planService: ref.read(planServiceProvider),
    onAgentsChanged: () => ref.read(agentProvider.notifier).refresh(),
  );
});

final memoryAnalysisCoordinatorProvider = Provider<MemoryAnalysisCoordinator>(
  (ref) => MemoryAnalysisCoordinator(),
);

final chatMemoryTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

final scopedMemoryServiceFactoryProvider = Provider<ScopedMemoryServiceFactory>(
  (ref) =>
      ({
        required String agentId,
        required Iterable<ShortTermMessage> shortTermMessages,
        required int maxShortTermRounds,
      }) => MemoryService.scoped(
        agentId: agentId,
        shortTermMessages: shortTermMessages,
        maxShortTermRounds: maxShortTermRounds,
      ),
);

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final notifier = ChatNotifier(
    ref,
    ref.read(memoryServiceProvider),
    ref.read(memoryAnalysisCoordinatorProvider),
    ref.read(toolExecutorProvider),
    ref.read(chatMemoryTimeoutProvider),
    ref.read(scopedMemoryServiceFactoryProvider),
  );
  ref.listen<AgentState>(agentProvider, (previous, next) {
    final previousId = previous?.currentAgent?.id;
    final nextId = next.currentAgent?.id;
    if (nextId != previousId) {
      unawaited(notifier.reloadChatFromDb(nextId));
    }
  });
  return notifier;
});
