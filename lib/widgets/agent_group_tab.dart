import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/home_tab_provider.dart';
import 'contact_list.dart';
import 'group_list_tab.dart';

/// 合并的"智能体·群聊"tab 内容页。
///
/// 内部用 IndexedStack 同时保活智能体列表与群聊列表，
/// 当前显示哪个子页由 [agentTabSubPageProvider] 控制
/// （HomeScreen 的子页分段控件翻转；watch 保证桌面端缓存子页也能刷新）。
class AgentGroupTab extends ConsumerWidget {
  const AgentGroupTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGroups = ref.watch(agentTabSubPageProvider);
    return IndexedStack(
      index: showGroups ? 1 : 0,
      children: const [ContactListWidget(), GroupListTabWidget()],
    );
  }
}
