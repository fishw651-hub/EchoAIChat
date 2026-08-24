import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

/// 智能体编组（本地分组，不参与多端同步）
class AgentFolder {
  final String id;
  final String name;
  final int createdAt;
  final int memberCount;

  const AgentFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.memberCount = 0,
  });
}

class AgentFolderState {
  final List<AgentFolder> folders;

  /// agentId → folderId（一个智能体最多属于一个编组）
  final Map<String, String> memberships;

  const AgentFolderState({
    this.folders = const [],
    this.memberships = const {},
  });

  AgentFolderState copyWith({
    List<AgentFolder>? folders,
    Map<String, String>? memberships,
  }) {
    return AgentFolderState(
      folders: folders ?? this.folders,
      memberships: memberships ?? this.memberships,
    );
  }
}

class AgentFolderNotifier extends StateNotifier<AgentFolderState> {
  AgentFolderNotifier() : super(const AgentFolderState()) {
    refresh();
  }

  Future<void> refresh() async {
    final rows = await DatabaseService.getAgentFolders();
    final folders = rows
        .map(
          (r) => AgentFolder(
            id: r['id'] as String,
            name: r['name'] as String,
            createdAt: r['created_at'] as int,
            memberCount: (r['member_count'] as int?) ?? 0,
          ),
        )
        .toList();
    final memberships = await DatabaseService.getAgentFolderMemberships();
    // 异步间隙中 container 可能已销毁（如测试 tearDown），避免 set state 抛错
    if (!mounted) return;
    state = state.copyWith(folders: folders, memberships: memberships);
  }

  Future<String> createFolder(String name) async {
    final id = await DatabaseService.createAgentFolder(name);
    await refresh();
    return id;
  }

  Future<void> renameFolder(String id, String name) async {
    await DatabaseService.renameAgentFolder(id, name);
    await refresh();
  }

  /// 解散编组：只删编组及映射，不删智能体
  Future<void> dissolveFolder(String id) async {
    await DatabaseService.deleteAgentFolder(id);
    await refresh();
  }

  /// 批量加入编组（一个智能体只属于一个编组，旧映射自动移除）
  Future<void> addAgentsToFolder(String folderId, List<String> agentIds) async {
    await DatabaseService.addAgentsToFolder(folderId, agentIds);
    await refresh();
  }

  Future<void> removeAgentsFromFolder(List<String> agentIds) async {
    await DatabaseService.removeAgentsFromFolder(agentIds);
    await refresh();
  }
}

final agentFolderProvider =
    StateNotifierProvider<AgentFolderNotifier, AgentFolderState>((ref) {
      return AgentFolderNotifier();
    });
