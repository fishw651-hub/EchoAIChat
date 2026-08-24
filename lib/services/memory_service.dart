import '../models/short_term_message.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'database_service.dart';
import 'package:uuid/uuid.dart';

class MemoryService {
  final List<ShortTermMessage> _shortTermMessages = [];
  int maxShortTermRounds = 20;
  String? _agentId;
  String? _groupId;

  MemoryService();

  /// 为一次生成创建绑定智能体的短期上下文快照。
  /// 生成期间切换当前智能体时，快照不会被全局 MemoryService.setAgentId 清空。
  MemoryService.scoped({
    required String agentId,
    required Iterable<ShortTermMessage> shortTermMessages,
    required this.maxShortTermRounds,
  }) : _agentId = agentId {
    final scoped = shortTermMessages
        .where((message) => message.agentId == agentId)
        .toList(growable: false);
    final start = scoped.length > maxShortTermRounds
        ? scoped.length - maxShortTermRounds
        : 0;
    _shortTermMessages.addAll(scoped.skip(start));
  }

  List<ShortTermMessage> get shortTermMessages =>
      List.unmodifiable(_shortTermMessages);

  void setAgentId(String? id) {
    _groupId = null;
    if (_agentId != id) {
      _agentId = id;
      _shortTermMessages.clear();
    }
  }

  String? get agentId => _agentId;

  void setGroupId(String? id) {
    _groupId = id;
  }

  String? get groupId => _groupId;

  Future<void> loadShortTermFromDb(int limit) async {
    final targetAgentId = _agentId;
    if (targetAgentId == null) {
      _shortTermMessages.clear();
      return;
    }
    final msgs = await DatabaseService.getShortTermMessages(
      limit: limit,
      agentId: targetAgentId,
    );
    if (_agentId != targetAgentId) return;
    _shortTermMessages.clear();
    _shortTermMessages.addAll(msgs);
  }

  String _nextShortTermId() => 'S-${const Uuid().v4()}';

  Future<ShortTermMessage> addShortTermMessage({
    required String role,
    required String content,
    String? agentId,
    String? imagePath,
    List<String>? imagePaths,
  }) async {
    final targetAgentId = agentId ?? _agentId;
    final msg = ShortTermMessage(
      id: _nextShortTermId(),
      role: role,
      content: content,
      agentId: targetAgentId,
      imagePath: imagePath,
      imagePaths: imagePaths,
    );
    if (targetAgentId == _agentId) {
      _shortTermMessages.add(msg);
      _trimShortTerm();
    }
    await DatabaseService.insertShortTermMessage(msg);
    return msg;
  }

  void _trimShortTerm() {
    while (_shortTermMessages.length > maxShortTermRounds) {
      final removed = _shortTermMessages.removeAt(0);
      DatabaseService.deleteShortTermMessage(removed.id, agentId: _agentId);
    }
  }

  void clearShortTerm() {
    // 批量清空由 clearShortTermMessages 统一记录墓碑并整表删除，
    // 逐条 deleteShortTermMessage 会重复记墓碑 + N 次小事务，纯属冗余
    _shortTermMessages.clear();
    if (_agentId != null) {
      DatabaseService.clearShortTermMessages(agentId: _agentId!);
    }
  }

  List<Map<String, dynamic>> getShortTermAsMessages() {
    // 携带 image_path/image_paths 键供视觉上下文构建（VisionMessageBuilder.
    // attachImagesToMessages 消费这些键并保证最终发给 API 的 messages 不再携带）
    return _shortTermMessages
        .map(
          (m) => {
            ...m.toOpenAiMessage(),
            'image_path': m.imagePath,
            'image_paths': m.imagePaths,
          },
        )
        .toList();
  }

  /// 更新短期记忆消息内容（内存 + DB）。用于发图后经视觉模型描述
  /// 把占位的 [图片] 文本替换为包含图片内容的完整描述。
  Future<void> updateShortTermContent(String id, String content) async {
    final idx = _shortTermMessages.indexWhere((m) => m.id == id);
    if (idx != -1) {
      final old = _shortTermMessages[idx];
      _shortTermMessages[idx] = ShortTermMessage(
        id: old.id,
        role: old.role,
        content: content,
        agentId: old.agentId,
        imagePath: old.imagePath,
        imagePaths: old.imagePaths,
        timestamp: old.timestamp,
      );
    }
    await DatabaseService.updateShortTermMessageContent(
      id,
      content,
      agentId: _agentId,
    );
  }

  void compressShortTerm(int keepRounds) {
    final keep = keepRounds.clamp(1, maxShortTermRounds);
    while (_shortTermMessages.length > keep) {
      final removed = _shortTermMessages.removeAt(0);
      DatabaseService.deleteShortTermMessage(removed.id, agentId: _agentId);
    }
  }

  Future<void> deleteShortTermMessage(String id, {String? agentId}) async {
    final targetAgentId = agentId ?? _agentId;
    if (targetAgentId == _agentId) {
      _shortTermMessages.removeWhere((m) => m.id == id);
    }
    await DatabaseService.deleteShortTermMessage(id, agentId: targetAgentId);
  }

  // ─── 长期记忆 ────

  Future<String> createLongTermMemory({
    required String field,
    required String content,
  }) async {
    // 全局唯一 UUID（带 L- 前缀供工具按前缀路由），避免跨智能体同号碰撞
    final newId = 'L-${const Uuid().v4()}';
    final memory = LongTermMemory(
      id: newId,
      field: field,
      content: content,
      agentId: _agentId,
      groupId: _groupId,
    );
    await DatabaseService.insertLongTermMemory(memory);
    return newId;
  }

  Future<void> updateLongTermMemory({
    required String targetId,
    required String content,
    String? field,
  }) async {
    await DatabaseService.updateLongTermMemory(
      LongTermMemory(
        id: targetId,
        field: field ?? 'status',
        content: content,
        agentId: _agentId,
      ),
      agentId: _agentId,
    );
  }

  Future<void> deleteLongTermMemory(String id) async {
    await DatabaseService.deleteLongTermMemory(id, agentId: _agentId);
  }

  Future<List<LongTermMemory>> getLongTermMemories() async {
    return await DatabaseService.getLongTermMemories(
      agentId: _agentId,
      groupId: _groupId,
    );
  }

  Future<List<LongTermMemory>> compressLongTerm(int keepCount) async {
    final all = await getLongTermMemories();
    if (all.length <= keepCount) return all;
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final toKeep = all.take(keepCount).toList();
    for (final item in all.skip(keepCount)) {
      await deleteLongTermMemory(item.id);
    }
    return toKeep;
  }

  // ─── 基础记忆 ────

  Future<String> createBaseMemory({
    required String type,
    required String content,
  }) async {
    // 全局唯一 UUID（带 B- 前缀供工具按前缀路由）
    final newId = 'B-${const Uuid().v4()}';
    final memory = BaseMemory(
      id: newId,
      type: type,
      content: content,
      agentId: _agentId,
      groupId: _groupId,
    );
    await DatabaseService.insertBaseMemory(memory);
    return newId;
  }

  Future<void> updateBaseMemory(BaseMemory memory) async {
    await DatabaseService.updateBaseMemory(memory, agentId: _agentId);
  }

  Future<void> deleteBaseMemory(String id) async {
    await DatabaseService.deleteBaseMemory(id, agentId: _agentId);
  }

  Future<List<BaseMemory>> getBaseMemories() async {
    return await DatabaseService.getBaseMemories(
      agentId: _agentId,
      groupId: _groupId,
    );
  }

  Future<List<BaseMemory>> compressBaseMemories(int keepEventCount) async {
    final all = await getBaseMemories();
    final settings = all.where((m) => m.isSetting).toList();
    final events = all.where((m) => m.isEvent).toList();
    events.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final toKeep = events.take(keepEventCount).toList();
    for (final item in events.skip(keepEventCount)) {
      await deleteBaseMemory(item.id);
    }
    return [...settings, ...toKeep];
  }

  // ─── 提示词构建 ──

  Future<String> buildLongTermPrompt() async {
    final memories = await getLongTermMemories();
    if (memories.isEmpty) return '（暂无长期记忆条目）';
    return memories.map((m) => m.toPromptLine()).join('\n');
  }

  Future<String> buildBasePrompt() async {
    final memories = await getBaseMemories();
    if (memories.isEmpty) return '（暂无基础记忆条目）';
    return memories.map((m) => m.toPromptLine()).join('\n');
  }

  static int estimateTokens(String text) {
    int chineseChars = 0, otherChars = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF ||
          char >= 0x3400 && char <= 0x4DBF) {
        chineseChars++;
      } else {
        otherChars++;
      }
    }
    return (chineseChars * 1.5 + otherChars * 0.25).ceil();
  }

  Future<int> estimateContextTokens() async {
    int total = 0;
    for (final msg in _shortTermMessages) {
      total += estimateTokens(msg.content);
    }
    final longTerm = await getLongTermMemories();
    for (final m in longTerm) {
      total += estimateTokens('${m.field}: ${m.content}');
    }
    final base = await getBaseMemories();
    for (final m in base) {
      total += estimateTokens(m.content);
    }
    return total;
  }
}
