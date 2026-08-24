import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/short_term_message.dart';
import '../models/agent.dart';
import 'memory_repository.dart';
import 'chat_repository.dart';
import 'agent_repository.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) => const MemoryRepository());

final chatRepositoryProvider = Provider<ChatRepository>((ref) => const ChatRepository());

final agentRepositoryProvider = Provider<AgentRepository>((ref) => const AgentRepository());

final longTermMemoriesProvider = FutureProvider.family<List<LongTermMemory>, String>((ref, agentId) {
  return ref.read(memoryRepositoryProvider).getLongTermMemories(agentId: agentId);
});

final baseMemoriesProvider = FutureProvider.family<List<BaseMemory>, String>((ref, agentId) {
  return ref.read(memoryRepositoryProvider).getBaseMemories(agentId: agentId);
});

final shortTermMessagesProvider = FutureProvider.family<List<ShortTermMessage>, String>((ref, agentId) {
  return ref.read(memoryRepositoryProvider).getShortTermMessages(agentId: agentId);
});

final chatMessagesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, agentId) {
  return ref.read(chatRepositoryProvider).getMessages(agentId: agentId);
});

final agentListProvider = FutureProvider<List<Agent>>((ref) {
  return ref.read(agentRepositoryProvider).getAll();
});
