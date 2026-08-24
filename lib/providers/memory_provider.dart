import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../services/memory_service.dart';
import '../repositories/memory_repository.dart';
import '../repositories/repository_providers.dart';
import 'agent_provider.dart';

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

class LongTermState {
  final List<LongTermMemory> memories;
  final bool isLoading;

  const LongTermState({this.memories = const [], this.isLoading = false});

  LongTermState copyWith({List<LongTermMemory>? memories, bool? isLoading}) {
    return LongTermState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LongTermNotifier extends StateNotifier<LongTermState> {
  final MemoryService _memoryService;
  final MemoryRepository _repo;
  final Ref _ref;

  LongTermNotifier(this._memoryService, this._ref)
      : _repo = _ref.read(memoryRepositoryProvider),
        super(const LongTermState()) {
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final id = _ref.read(agentProvider).currentAgent?.id;
    if (id != null) {
      _memoryService.setAgentId(id);
    }
    await loadMemories();
    if (_memoryService.agentId == null) {
      // 启动时 agentProvider 可能尚未从 SQLite 加载完当前智能体。
      // 此 delay 仅为初次加载竞态的兜底；后续智能体切换由下方
      // longTermProvider 中的 ref.listen(agentProvider, ...) 响应式处理。
      await Future.delayed(const Duration(milliseconds: 100));
      final retryId = _ref.read(agentProvider).currentAgent?.id;
      if (retryId != null) {
        _memoryService.setAgentId(retryId);
        await loadMemories();
      }
    }
  }

  Future<void> loadMemories() async {
    state = state.copyWith(isLoading: true);
    final agentId = _memoryService.agentId;
    if (agentId != null) {
      final memories = await _repo.getLongTermMemories(agentId: agentId);
      state = state.copyWith(memories: memories, isLoading: false);
    } else {
      state = state.copyWith(memories: const [], isLoading: false);
    }
  }

  void _syncAgentId() {
    final id = _ref.read(agentProvider).currentAgent?.id;
    if (id != null && id != _memoryService.agentId) {
      _memoryService.setAgentId(id);
    }
  }

  Future<void> updateMemory(LongTermMemory memory) async {
    _syncAgentId();
    await _memoryService.updateLongTermMemory(
      targetId: memory.id,
      content: memory.content,
      field: memory.field,
    );
    await loadMemories();
  }

  Future<void> deleteMemory(String id) async {
    _syncAgentId();
    await _memoryService.deleteLongTermMemory(id);
    await loadMemories();
  }

  Future<void> addMemory({required String field, required String content}) async {
    _syncAgentId();
    await _memoryService.createLongTermMemory(field: field, content: content);
    await loadMemories();
  }

  Future<void> clearAll() async {
    _syncAgentId();
    await _memoryService.compressLongTerm(0);
    await loadMemories();
  }
}

class BaseState {
  final List<BaseMemory> memories;
  final bool isLoading;

  const BaseState({this.memories = const [], this.isLoading = false});

  BaseState copyWith({List<BaseMemory>? memories, bool? isLoading}) {
    return BaseState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BaseNotifier extends StateNotifier<BaseState> {
  final MemoryService _memoryService;
  final Ref _ref;

  BaseNotifier(this._memoryService, this._ref) : super(const BaseState()) {
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final id = _ref.read(agentProvider).currentAgent?.id;
    if (id != null) {
      _memoryService.setAgentId(id);
    }
    await loadMemories();
    if (_memoryService.agentId == null) {
      // 启动时 agentProvider 可能尚未从 SQLite 加载完当前智能体。
      // 此 delay 仅为初次加载竞态的兜底；后续智能体切换由下方
      // baseProvider 中的 ref.listen(agentProvider, ...) 响应式处理。
      await Future.delayed(const Duration(milliseconds: 100));
      final retryId = _ref.read(agentProvider).currentAgent?.id;
      if (retryId != null) {
        _memoryService.setAgentId(retryId);
        await loadMemories();
      }
    }
  }

  Future<void> loadMemories() async {
    state = state.copyWith(isLoading: true);
    final agentId = _memoryService.agentId;
    if (agentId != null) {
      final memories = await _memoryService.getBaseMemories();
      state = state.copyWith(memories: memories, isLoading: false);
    } else {
      state = state.copyWith(memories: const [], isLoading: false);
    }
  }

  void _syncAgentId() {
    final id = _ref.read(agentProvider).currentAgent?.id;
    if (id != null && id != _memoryService.agentId) {
      _memoryService.setAgentId(id);
    }
  }

  Future<void> updateMemory(BaseMemory memory) async {
    _syncAgentId();
    await _memoryService.updateBaseMemory(memory);
    await loadMemories();
  }

  Future<void> deleteMemory(String id) async {
    _syncAgentId();
    await _memoryService.deleteBaseMemory(id);
    await loadMemories();
  }

  Future<void> createSetting(String content) async {
    _syncAgentId();
    await _memoryService.createBaseMemory(type: 'setting', content: content);
    await loadMemories();
  }

  Future<void> clearEvents() async {
    _syncAgentId();
    final all = await _memoryService.getBaseMemories();
    for (final m in all.where((m) => m.isEvent)) {
      await _memoryService.deleteBaseMemory(m.id);
    }
    await loadMemories();
  }

  Future<void> clearAll() async {
    _syncAgentId();
    final all = await _memoryService.getBaseMemories();
    for (final m in all) {
      await _memoryService.deleteBaseMemory(m.id);
    }
    await loadMemories();
  }
}

final longTermProvider =
    StateNotifierProvider<LongTermNotifier, LongTermState>((ref) {
  final notifier = LongTermNotifier(ref.read(memoryServiceProvider), ref);
  ref.listen<AgentState>(agentProvider, (prev, next) {
    final newId = next.currentAgent?.id;
    if (prev?.currentAgent?.id != newId && newId != null) {
      notifier._syncAgentId();
      notifier.loadMemories();
    }
  });
  return notifier;
});

final baseProvider = StateNotifierProvider<BaseNotifier, BaseState>((ref) {
  final notifier = BaseNotifier(ref.read(memoryServiceProvider), ref);
  ref.listen<AgentState>(agentProvider, (prev, next) {
    final newId = next.currentAgent?.id;
    if (prev?.currentAgent?.id != newId && newId != null) {
      notifier._syncAgentId();
      notifier.loadMemories();
    }
  });
  return notifier;
});
