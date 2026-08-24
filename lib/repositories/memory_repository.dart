import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/short_term_message.dart';
import '../services/database_service.dart';

class MemoryRepository {
  const MemoryRepository();

  Future<List<LongTermMemory>> getLongTermMemories({required String agentId, String? groupId}) async {
    try {
      return await DatabaseService.getLongTermMemories(agentId: agentId, groupId: groupId);
    } catch (e) {
      debugPrint('[MemoryRepo] getLongTermMemories error: $e');
      return [];
    }
  }

  Future<String> createLongTermMemory({required String agentId, required String field, required String content, String? groupId}) async {
    // 全局唯一 UUID（带 L- 前缀供工具按前缀路由），避免跨智能体同号碰撞
    final id = 'L-${const Uuid().v4()}';
    final m = LongTermMemory(id: id, field: field, content: content, agentId: agentId, groupId: groupId);
    await DatabaseService.insertLongTermMemory(m);
    return id;
  }

  Future<void> updateLongTermMemory({required String targetId, required String content, String? field, String? agentId}) async {
    String effectiveField = field ?? 'status';
    // field 为 null 时查询现有记忆的原 field，避免覆盖原有分类
    if (field == null && agentId != null) {
      final existing = await DatabaseService.getLongTermMemories(agentId: agentId, privateOnly: false);
      final found = existing.where((m) => m.id == targetId).firstOrNull;
      if (found != null) {
        effectiveField = found.field;
      }
    }
    final m = LongTermMemory(id: targetId, field: effectiveField, content: content, agentId: agentId);
    await DatabaseService.updateLongTermMemory(m, agentId: agentId);
  }

  Future<void> deleteLongTermMemory(String id, {String? agentId}) async {
    await DatabaseService.deleteLongTermMemory(id, agentId: agentId);
  }

  Future<List<BaseMemory>> getBaseMemories({required String agentId, String? groupId}) async {
    try {
      return await DatabaseService.getBaseMemories(agentId: agentId, groupId: groupId);
    } catch (e) {
      debugPrint('[MemoryRepo] getBaseMemories error: $e');
      return [];
    }
  }

  Future<String> createBaseMemory({required String agentId, required String type, required String content, String? groupId}) async {
    // 全局唯一 UUID（带 B- 前缀供工具按前缀路由）
    final id = 'B-${const Uuid().v4()}';
    final m = BaseMemory(id: id, type: type, content: content, agentId: agentId, groupId: groupId);
    await DatabaseService.insertBaseMemory(m);
    return id;
  }

  Future<void> updateBaseMemory(BaseMemory memory, {String? agentId}) async {
    await DatabaseService.updateBaseMemory(memory, agentId: agentId);
  }

  Future<void> deleteBaseMemory(String id, {String? agentId}) async {
    await DatabaseService.deleteBaseMemory(id, agentId: agentId);
  }

  Future<List<ShortTermMessage>> getShortTermMessages({required String agentId, int? limit}) async {
    try {
      return await DatabaseService.getShortTermMessages(agentId: agentId, limit: limit);
    } catch (e) {
      debugPrint('[MemoryRepo] getShortTermMessages error: $e');
      return [];
    }
  }

  Future<int> getMaxShortTermSeq({required String agentId}) async {
    return await DatabaseService.getMaxShortTermSeq(agentId: agentId);
  }

  Future<void> insertShortTermMessage(ShortTermMessage msg) async {
    await DatabaseService.insertShortTermMessage(msg);
  }

  Future<void> deleteShortTermMessage(String id, {required String agentId}) async {
    await DatabaseService.deleteShortTermMessage(id, agentId: agentId);
  }

  Future<void> clearShortTermMessages({required String agentId}) async {
    await DatabaseService.clearShortTermMessages(agentId: agentId);
  }

  Future<void> deleteByAgent(String agentId) async {
    await DatabaseService.clearLongTermMemories(agentId: agentId);
    await DatabaseService.clearBaseMemories(agentId: agentId);
    await DatabaseService.clearShortTermMessages(agentId: agentId);
  }
}
