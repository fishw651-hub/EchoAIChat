// 回响 · 本地数据库服务（SQLite / sqflite，WAL 模式）。
//
// 本类为纯静态外观：所有公有静态方法的签名与行为保持不变，
// 方法体按表域拆到同库 part 文件的库私有顶层函数中（一行委托）：
//   - database_agent_store.dart：agents / agent_folders / agent_folder_members
//   - database_memory_store.dart：long_term / base / short_term / group_short_term / group_shared 记忆
//   - database_chat_store.dart：chat_messages / planned_messages / group_chats / group_members / group_messages
//   - database_misc_store.dart：providers / token_usage / stickers / token_cost / novel / user_profiles / draft_uploads
//   - database_sync_store.dart：墓碑 / client_id（local_tombstones 内联实现）
//   - database_maintenance.dart：例行清理 / 备份与恢复（WAL checkpoint）
//   - database_schema.dart：schema 建表与迁移（_onCreate/_onUpgrade/_ensureGroupTablesExist）

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/planned_message.dart';
import '../models/short_term_message.dart';
import '../models/provider_config.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import '../models/group_message.dart';
import '../models/group_shared_memory.dart';
import '../models/profile_entry.dart';
import 'sync_tables.dart';
import 'account_database_scope.dart';
import 'device_id_service.dart';
import 'image_paths_codec.dart';
import 'proactive_care_store.dart';

part 'database_agent_store.dart';
part 'database_memory_store.dart';
part 'database_chat_store.dart';
part 'database_misc_store.dart';
part 'database_sync_store.dart';
part 'database_maintenance.dart';
part 'database_schema.dart';
part 'account_database_migration.dart';

class DatabaseService {
  static Database? _database;
  static bool _cleanupDone = false;
  static int? _currentUserId;
  static String _databaseName = AccountDatabaseScope.guestDatabaseName;
  static Future<void> _operationTail = Future<void>.value();

  /// 由应用入口注入，用于在切库完成后使所有数据库 Provider 失效。
  static FutureOr<void> Function()? onAccountSwitched;

  static int? get currentUserId => _currentUserId;
  static String get currentDatabaseName => _databaseName;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    return _serialize(() async {
      if (_database != null) return _database!;
      _database = await _initDatabase(databaseName: _databaseName);
      await _cleanupOnce();
      return _database!;
    });
  }

  static Future<void> switchAccount(int? userId) async {
    if (userId != null && userId <= 0) {
      throw ArgumentError.value(userId, 'userId', '必须为正整数');
    }
    final targetName = AccountDatabaseScope.databaseNameForUser(userId);
    await _switchNamedDatabase(userId: userId, targetName: targetName);
  }

  /// 旧版会话没有可恢复的 userId 时使用 token 派生的临时隔离库，
  /// 待 profile 返回真实用户 ID 后立即迁移到账号库。
  static Future<void> switchOpaqueSession(String sessionKey) async {
    final targetName = AccountDatabaseScope.databaseNameForOpaqueKey(
      sessionKey,
    );
    await _switchNamedDatabase(userId: null, targetName: targetName);
  }

  static Future<void> _switchNamedDatabase({
    required int? userId,
    required String targetName,
  }) async {
    await _serialize(() async {
      if (_database != null &&
          _currentUserId == userId &&
          _databaseName == targetName) {
        return;
      }

      final carryUnownedData =
          _database != null &&
          _currentUserId == null &&
          _databaseName != targetName;
      final previousName = _databaseName;
      final previous = _database;
      if (previous != null) {
        try {
          await previous.rawQuery('PRAGMA wal_checkpoint(FULL)');
        } catch (_) {}
        await previous.close();
      }
      _database = null;
      _cleanupDone = false;

      if (carryUnownedData && !kIsWeb && previous != null) {
        final guestPath = await _databasePathForName(previousName);
        final targetPath = await _databasePathForName(targetName);
        if (await File(guestPath).exists() &&
            !await File(targetPath).exists()) {
          await File(guestPath).copy(targetPath);
        }
      }

      if (userId != null) {
        await AccountDatabaseMigration.claimLegacyIfNeeded(
          userId: userId,
          targetDatabaseName: targetName,
        );
      }
      final next = await _initDatabase(databaseName: targetName);
      _database = next;
      _databaseName = targetName;
      _currentUserId = userId;
      await _cleanupOnce();
      await onAccountSwitched?.call();
    });
  }

  /// 关闭并重置测试数据库，使下一套测试可以切换到独立路径。
  @visibleForTesting
  static Future<void> closeForTesting() async {
    await _serialize(() async {
      final db = _database;
      _database = null;
      _cleanupDone = false;
      _currentUserId = null;
      _databaseName = AccountDatabaseScope.guestDatabaseName;
      await db?.close();
    });
  }

  static Future<void> _cleanupOnce() async {
    if (_cleanupDone) return;
    await _routineCleanup();
    _cleanupDone = true;
  }

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _operationTail = _operationTail.catchError((_) {}).then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  // ─── Agents / 智能体编组 ───

  // 实现见 database_agent_store.dart
  static Future<List<Agent>> getAgents() => _getAgents();

  // 实现见 database_agent_store.dart
  static Future<Agent?> getActiveAgent() => _getActiveAgent();

  // 实现见 database_agent_store.dart
  static Future<Agent?> getAgent(String id) => _getAgent(id);

  // 实现见 database_agent_store.dart
  static Future<Agent?> findAgentByNameAndPersona(
    String name,
    String persona,
  ) => _findAgentByNameAndPersona(name, persona);

  // 实现见 database_agent_store.dart
  static Future<void> insertAgent(Agent agent) => _insertAgent(agent);

  // 实现见 database_agent_store.dart
  static Future<void> updateAgent(Agent agent) => _updateAgent(agent);

  // 实现见 database_agent_store.dart
  static Future<void> deleteAgent(String id) => _deleteAgent(id);

  // 实现见 database_agent_store.dart
  static Future<void> setActiveAgent(String id) => _setActiveAgent(id);

  // 实现见 database_agent_store.dart
  static Future<String> createAgentFolder(String name) =>
      _createAgentFolder(name);

  // 实现见 database_agent_store.dart
  static Future<void> renameAgentFolder(String id, String name) =>
      _renameAgentFolder(id, name);

  // 实现见 database_agent_store.dart
  static Future<void> deleteAgentFolder(String id) => _deleteAgentFolder(id);

  // 实现见 database_agent_store.dart
  static Future<void> addAgentsToFolder(
    String folderId,
    List<String> agentIds,
  ) => _addAgentsToFolder(folderId, agentIds);

  // 实现见 database_agent_store.dart
  static Future<void> removeAgentsFromFolder(List<String> agentIds) =>
      _removeAgentsFromFolder(agentIds);

  // 实现见 database_agent_store.dart
  static Future<List<String>> getFolderMemberAgentIds(String folderId) =>
      _getFolderMemberAgentIds(folderId);

  // 实现见 database_agent_store.dart
  static Future<List<Map<String, dynamic>>> getAgentFolders() =>
      _getAgentFolders();

  // 实现见 database_agent_store.dart
  static Future<Map<String, String>> getAgentFolderMemberships() =>
      _getAgentFolderMemberships();

  // ─── 三层记忆（长期/基础/短期 + 群域记忆 + 人设迁移 + 裁剪）───

  // 实现见 database_memory_store.dart
  static Future<List<LongTermMemory>> getLongTermMemories({
    String? agentId,
    String? groupId,
    bool privateOnly = true,
  }) => _getLongTermMemories(
    agentId: agentId,
    groupId: groupId,
    privateOnly: privateOnly,
  );

  // 实现见 database_memory_store.dart
  static Future<void> insertLongTermMemory(LongTermMemory memory) =>
      _insertLongTermMemory(memory);

  // 实现见 database_memory_store.dart
  static Future<void> updateLongTermMemory(
    LongTermMemory memory, {
    String? agentId,
  }) => _updateLongTermMemory(memory, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> deleteLongTermMemory(String id, {String? agentId}) =>
      _deleteLongTermMemory(id, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> clearLongTermMemories({String? agentId}) =>
      _clearLongTermMemories(agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<List<BaseMemory>> getBaseMemories({
    String? agentId,
    String? groupId,
    bool privateOnly = true,
  }) => _getBaseMemories(
    agentId: agentId,
    groupId: groupId,
    privateOnly: privateOnly,
  );

  // 实现见 database_memory_store.dart
  static Future<void> insertBaseMemory(BaseMemory memory) =>
      _insertBaseMemory(memory);

  // 实现见 database_memory_store.dart
  static Future<void> updateBaseMemory(BaseMemory memory, {String? agentId}) =>
      _updateBaseMemory(memory, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> deleteBaseMemory(String id, {String? agentId}) =>
      _deleteBaseMemory(id, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> clearBaseMemories({String? agentId}) =>
      _clearBaseMemories(agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<List<ShortTermMessage>> getShortTermMessages({
    int? limit,
    String? agentId,
  }) => _getShortTermMessages(limit: limit, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<int> getShortTermCount({String? agentId}) =>
      _getShortTermCount(agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<int> getMaxShortTermSeq({String? agentId}) =>
      _getMaxShortTermSeq(agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> insertShortTermMessage(ShortTermMessage msg) =>
      _insertShortTermMessage(msg);

  // 实现见 database_memory_store.dart
  static Future<void> deleteShortTermMessage(String id, {String? agentId}) =>
      _deleteShortTermMessage(id, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> clearShortTermMessages({String? agentId}) =>
      _clearShortTermMessages(agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<List<Map<String, dynamic>>> getUnprocessedShortTermMessages(
    String agentId,
  ) => _getUnprocessedShortTermMessages(agentId);

  // 实现见 database_memory_store.dart
  static Future<void> updateShortTermMessageContent(
    String id,
    String content, {
    String? agentId,
  }) => _updateShortTermMessageContent(id, content, agentId: agentId);

  // 实现见 database_memory_store.dart
  static Future<void> markShortTermMessagesProcessed(List<String> ids) =>
      _markShortTermMessagesProcessed(ids);

  // 实现见 database_memory_store.dart
  static Future<void> migrateDefaultPersona(String newPersona) =>
      _migrateDefaultPersona(newPersona);

  // 实现见 database_memory_store.dart
  static Future<void> insertGroupShortTerm({
    required String groupId,
    required String role,
    String? senderName,
    required String content,
    required int timestamp,
  }) => _insertGroupShortTerm(
    groupId: groupId,
    role: role,
    senderName: senderName,
    content: content,
    timestamp: timestamp,
  );

  // 实现见 database_memory_store.dart
  static Future<List<Map<String, dynamic>>> getGroupShortTerm(String groupId) =>
      _getGroupShortTerm(groupId);

  // 实现见 database_memory_store.dart
  static Future<int> getGroupShortTermCount(String groupId) =>
      _getGroupShortTermCount(groupId);

  // 实现见 database_memory_store.dart
  static Future<void> deleteOldestGroupShortTerm(String groupId, int keep) =>
      _deleteOldestGroupShortTerm(groupId, keep);

  // 实现见 database_memory_store.dart
  static Future<void> clearGroupShortTerm(String groupId) =>
      _clearGroupShortTerm(groupId);

  // 实现见 database_memory_store.dart
  static Future<List<Map<String, dynamic>>> getUnprocessedGroupShortTerm(
    String groupId,
  ) => _getUnprocessedGroupShortTerm(groupId);

  // 实现见 database_memory_store.dart
  static Future<void> markGroupShortTermProcessed(List<int> ids) =>
      _markGroupShortTermProcessed(ids);

  // 实现见 database_memory_store.dart
  static Future<List<GroupSharedMemory>> getGroupSharedMemories(
    String groupId,
  ) => _getGroupSharedMemories(groupId);

  // 实现见 database_memory_store.dart
  static Future<void> insertGroupSharedMemory(GroupSharedMemory m) =>
      _insertGroupSharedMemory(m);

  // 实现见 database_memory_store.dart
  static Future<void> updateGroupSharedMemory(GroupSharedMemory m) =>
      _updateGroupSharedMemory(m);

  // 实现见 database_memory_store.dart
  static Future<void> deleteGroupSharedMemory(String id) =>
      _deleteGroupSharedMemory(id);

  // 实现见 database_memory_store.dart
  static Future<List<LongTermMemory>> getLongTermMemoriesForGroup(
    String agentId,
    String groupId,
  ) => _getLongTermMemoriesForGroup(agentId, groupId);

  // 实现见 database_memory_store.dart
  static Future<List<BaseMemory>> getBaseMemoriesForGroup(
    String agentId,
    String groupId,
  ) => _getBaseMemoriesForGroup(agentId, groupId);

  // 实现见 database_memory_store.dart
  static Future<void> trimShortTermMessages({
    required String agentId,
    required int keep,
  }) => _trimShortTermMessages(agentId: agentId, keep: keep);

  // ─── 聊天消息 / 计划消息 / 群聊 / 群成员 / 群消息 ───

  // 实现见 database_chat_store.dart
  static Future<int> insertChatMessage({
    required String role,
    required String content,
    required int timestampMs,
    String? shortMemId,
    String? agentId,
    String? imagePath,
    List<String>? imagePaths,
  }) => _insertChatMessage(
    role: role,
    content: content,
    timestampMs: timestampMs,
    shortMemId: shortMemId,
    agentId: agentId,
    imagePath: imagePath,
    imagePaths: imagePaths,
  );

  // 实现见 database_chat_store.dart
  static Future<List<Map<String, dynamic>>> getChatMessages({
    String? agentId,
    int? limit,
    int? beforeId,
  }) => _getChatMessages(agentId: agentId, limit: limit, beforeId: beforeId);

  // 实现见 database_chat_store.dart
  static Future<int> getChatMessageCount(String agentId) =>
      _getChatMessageCount(agentId);

  // 实现见 database_chat_store.dart
  static Future<void> deleteChatMessage(int id) => _deleteChatMessage(id);

  // 实现见 database_chat_store.dart
  static Future<void> updateChatMessageContent(int id, String content) =>
      _updateChatMessageContent(id, content);

  // 实现见 database_chat_store.dart
  static Future<void> clearChatMessages({String? agentId}) =>
      _clearChatMessages(agentId: agentId);

  // 实现见 database_chat_store.dart
  static Future<Map<String, dynamic>?> getLastChatMessage(String agentId) =>
      _getLastChatMessage(agentId);

  // 实现见 database_chat_store.dart
  static Future<Map<String, Map<String, dynamic>>>
  getLastChatMessagesByAgent() => _getLastChatMessagesByAgent();

  // 实现见 database_chat_store.dart
  static Future<Map<String, Map<String, dynamic>>>
  getLastGroupMessagesByGroup() => _getLastGroupMessagesByGroup();

  // 实现见 database_chat_store.dart
  static Future<Map<String, dynamic>?> getLastGroupMessage(String groupId) =>
      _getLastGroupMessage(groupId);

  // 实现见 database_chat_store.dart
  static Future<List<PlannedMessage>> getPlannedMessages({String? agentId}) =>
      _getPlannedMessages(agentId: agentId);

  // 实现见 database_chat_store.dart
  static Future<int> insertPlannedMessage(PlannedMessage msg) =>
      _insertPlannedMessage(msg);

  // 实现见 database_chat_store.dart
  static Future<void> updatePlannedMessage(PlannedMessage msg) =>
      _updatePlannedMessage(msg);

  // 实现见 database_chat_store.dart
  static Future<void> deletePlannedMessage(int id) => _deletePlannedMessage(id);

  // 实现见 database_chat_store.dart
  static Future<void> markDelivered(int id) => _markDelivered(id);

  // 实现见 database_chat_store.dart
  static Future<List<GroupChat>> getGroupChats() => _getGroupChats();

  // 实现见 database_chat_store.dart
  static Future<GroupChat?> getGroupChat(String id) => _getGroupChat(id);

  // 实现见 database_chat_store.dart
  static Future<void> insertGroupChat(GroupChat g) => _insertGroupChat(g);

  // 实现见 database_chat_store.dart
  static Future<void> updateGroupChat(GroupChat g) => _updateGroupChat(g);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupChat(String id) => _deleteGroupChat(id);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupChatCascade(String groupId) =>
      _deleteGroupChatCascade(groupId);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupMembersForGroup(String groupId) =>
      _deleteGroupMembersForGroup(groupId);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupMessagesForGroup(String groupId) =>
      _deleteGroupMessagesForGroup(groupId);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupSharedMemoriesForGroup(String groupId) =>
      _deleteGroupSharedMemoriesForGroup(groupId);

  // 实现见 database_chat_store.dart
  static Future<List<GroupMember>> getGroupMembers(String groupId) =>
      _getGroupMembers(groupId);

  // 实现见 database_chat_store.dart
  static Future<void> insertGroupMember(GroupMember m) => _insertGroupMember(m);

  // 实现见 database_chat_store.dart
  static Future<void> updateGroupMember(GroupMember m) => _updateGroupMember(m);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupMember(int id) => _deleteGroupMember(id);

  // 实现见 database_chat_store.dart
  static Future<void> deleteAllGroupMembers(String groupId) =>
      _deleteAllGroupMembers(groupId);

  // 实现见 database_chat_store.dart
  static Future<List<GroupMessage>> getGroupMessages(
    String groupId, {
    int? limit,
    int? beforeId,
  }) => _getGroupMessages(groupId, limit: limit, beforeId: beforeId);

  // 实现见 database_chat_store.dart
  static Future<int> getGroupMessageCount(String groupId) =>
      _getGroupMessageCount(groupId);

  // 实现见 database_chat_store.dart
  static Future<int> insertGroupMessage(GroupMessage msg) =>
      _insertGroupMessage(msg);

  // 实现见 database_chat_store.dart
  static Future<void> deleteGroupMessage(int id) => _deleteGroupMessage(id);

  // 实现见 database_chat_store.dart
  static Future<void> clearGroupMessages(String groupId) =>
      _clearGroupMessages(groupId);

  // ─── 供应商 / Token 用量 / 表情包 / Token Cost / 小说 / 画像 / 草稿箱 ───

  // 实现见 database_misc_store.dart
  static Future<List<ProviderConfig>> getProviders() => _getProviders();

  // 实现见 database_misc_store.dart
  static Future<int> insertProvider(ProviderConfig p) => _insertProvider(p);

  // 实现见 database_misc_store.dart
  static Future<void> updateProvider(ProviderConfig p) => _updateProvider(p);

  // 实现见 database_misc_store.dart
  static Future<void> deleteProvider(int id) => _deleteProvider(id);

  // 实现见 database_misc_store.dart
  static Future<void> insertTokenUsage({
    required int promptTokens,
    required int completionTokens,
    String? model,
    String? agentId,
  }) => _insertTokenUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    model: model,
    agentId: agentId,
  );

  // 实现见 database_misc_store.dart
  static Future<List<Map<String, dynamic>>> getTokenUsage({
    int days = 30,
    String? agentId,
  }) => _getTokenUsage(days: days, agentId: agentId);

  // 实现见 database_misc_store.dart
  static Future<String> insertSticker({
    required String id,
    required String description,
    required String imagePath,
    required int createdAt,
    required int updatedAt,
  }) => _insertSticker(
    id: id,
    description: description,
    imagePath: imagePath,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  // 实现见 database_misc_store.dart
  static Future<List<Map<String, dynamic>>> getStickers({
    bool includeDeleted = false,
  }) => _getStickers(includeDeleted: includeDeleted);

  // 实现见 database_misc_store.dart
  static Future<void> updateSticker({
    required String id,
    required String description,
    required int updatedAt,
  }) => _updateSticker(id: id, description: description, updatedAt: updatedAt);

  // 实现见 database_misc_store.dart
  static Future<void> softDeleteSticker(String id, int deletedAt) =>
      _softDeleteSticker(id, deletedAt);

  // 实现见 database_misc_store.dart
  static Future<void> insertStickerMessageSnapshot({
    required int chatMessageId,
    required String? stickerId,
    required String description,
    required String imagePath,
    required int createdAt,
  }) => _insertStickerMessageSnapshot(
    chatMessageId: chatMessageId,
    stickerId: stickerId,
    description: description,
    imagePath: imagePath,
    createdAt: createdAt,
  );

  // 实现见 database_misc_store.dart
  static Future<Map<String, dynamic>?> getStickerMessageSnapshot(
    int chatMessageId,
  ) => _getStickerMessageSnapshot(chatMessageId);

  // 实现见 database_misc_store.dart
  static Future<Map<int, Map<String, dynamic>>> getStickerMessageSnapshots(
    List<int> chatMessageIds,
  ) => _getStickerMessageSnapshots(chatMessageIds);

  // 实现见 database_misc_store.dart
  static Future<void> upsertTokenCost({
    required String model,
    required double price,
    required String unit,
    String? agentId,
  }) => _upsertTokenCost(
    model: model,
    price: price,
    unit: unit,
    agentId: agentId,
  );

  // 实现见 database_misc_store.dart
  static Future<Map<String, dynamic>?> getTokenPrice({
    required String model,
    String? agentId,
  }) => _getTokenPrice(model: model, agentId: agentId);

  // 实现见 database_misc_store.dart
  static Future<List<Map<String, dynamic>>> getAllTokenCosts() =>
      _getAllTokenCosts();

  // 实现见 database_misc_store.dart
  static Future<void> deleteTokenCost(String model, {String? agentId}) =>
      _deleteTokenCost(model, agentId: agentId);

  // 实现见 database_misc_store.dart
  static Future<int> insertNovelGeneration({
    required String style,
    required int wordCount,
    required String prompt,
    required String result,
  }) => _insertNovelGeneration(
    style: style,
    wordCount: wordCount,
    prompt: prompt,
    result: result,
  );

  // 实现见 database_misc_store.dart
  static Future<List<Map<String, dynamic>>> getNovelGenerations() =>
      _getNovelGenerations();

  // 实现见 database_misc_store.dart
  static Future<void> deleteNovelGeneration(int id) =>
      _deleteNovelGeneration(id);

  // 实现见 database_misc_store.dart
  static Future<List<ProfileEntry>> getProfileEntries() => _getProfileEntries();

  // 实现见 database_misc_store.dart
  static Future<List<ProfileEntry>> getProfileEntriesByCategory(
    String category,
  ) => _getProfileEntriesByCategory(category);

  // 实现见 database_misc_store.dart
  static Future<ProfileEntry?> getProfileEntry(String key, String category) =>
      _getProfileEntry(key, category);

  // 实现见 database_misc_store.dart
  static Future<void> insertProfileEntry(ProfileEntry entry) =>
      _insertProfileEntry(entry);

  // 实现见 database_misc_store.dart
  static Future<void> updateProfileEntry(ProfileEntry entry) =>
      _updateProfileEntry(entry);

  // 实现见 database_misc_store.dart
  static Future<void> deleteProfileEntry(String id) => _deleteProfileEntry(id);

  // 实现见 database_misc_store.dart
  static Future<int> getProfileEntryCount() => _getProfileEntryCount();

  // 实现见 database_misc_store.dart
  static Future<void> clearProfileEntries() => _clearProfileEntries();

  // 实现见 database_misc_store.dart
  static Future<List<Map<String, dynamic>>> getAllDrafts() => _getAllDrafts();

  // 实现见 database_misc_store.dart
  static Future<List<Map<String, dynamic>>> getDraftsByType(String type) =>
      _getDraftsByType(type);

  // 实现见 database_misc_store.dart
  static Future<Map<String, dynamic>?> getDraft(String id) => _getDraft(id);

  // 实现见 database_misc_store.dart
  static Future<String> insertDraft({
    required String type,
    required String data,
    String? name,
    int? coverColor,
  }) =>
      _insertDraft(type: type, data: data, name: name, coverColor: coverColor);

  // 实现见 database_misc_store.dart
  static Future<void> updateDraft(
    String id, {
    String? name,
    String? data,
    int? coverColor,
  }) => _updateDraft(id, name: name, data: data, coverColor: coverColor);

  // 实现见 database_misc_store.dart
  static Future<void> deleteDraft(String id) => _deleteDraft(id);

  // ─── 数据库备份与恢复 ───

  // 实现见 database_maintenance.dart
  static Future<String?> createSyncSafetySnapshot() =>
      _createSyncSafetySnapshot();

  // 实现见 database_maintenance.dart
  static Future<void> deleteSyncSafetySnapshot() => _deleteSyncSafetySnapshot();

  // 实现见 database_maintenance.dart
  static Future<File> backupDatabase(String destPath) =>
      _backupDatabase(destPath);

  // 实现见 database_maintenance.dart
  static Future<void> restoreDatabase(String sourcePath) =>
      _restoreDatabase(sourcePath);

  // ─── 数据迁移（供 main.dart / 测试直接调用）───

  // 实现见 database_schema.dart
  static Future<void> migrateLegacySyncClientIds(
    Database database, {
    required String deviceId,
    List<String> tables = const [
      'chat_messages',
      'group_members',
      'group_messages',
      'group_short_term',
      'planned_messages',
      'providers',
    ],
  }) =>
      _migrateLegacySyncClientIds(database, deviceId: deviceId, tables: tables);

  // 实现见 database_schema.dart
  static Future<void> migrateNetworkSourceColumns(Database database) =>
      _migrateNetworkSourceColumns(database);

  // 实现见 database_schema.dart
  static Future<void> migrateMemoryIdsToUuid(Database db) =>
      _migrateMemoryIdsToUuid(db);
}
