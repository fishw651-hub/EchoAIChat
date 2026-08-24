import 'package:flutter/foundation.dart';
import '../services/database_service.dart';

class ChatRepository {
  const ChatRepository();

  Future<List<Map<String, dynamic>>> getMessages({required String agentId}) async {
    try {
      return await DatabaseService.getChatMessages(agentId: agentId);
    } catch (e) {
      debugPrint('[ChatRepo] getMessages error: $e');
      return [];
    }
  }

  Future<int> insertMessage({required String role, required String content, required int timestampMs, String? shortMemId, required String agentId, String? imagePath}) async {
    return await DatabaseService.insertChatMessage(role: role, content: content, timestampMs: timestampMs, shortMemId: shortMemId, agentId: agentId, imagePath: imagePath);
  }

  Future<void> deleteMessage(int id) async {
    await DatabaseService.deleteChatMessage(id);
  }

  Future<void> clearMessages({required String agentId}) async {
    await DatabaseService.clearChatMessages(agentId: agentId);
  }
}
