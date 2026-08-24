import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 合并 tab（智能体·群聊）当前显示的子页：false=智能体列表 true=群聊列表
///
/// 由 HomeScreen 的子页分段控件（移动端浮于底部导航栏上方，桌面端位于
/// 内容区顶部）翻转，AgentGroupTab 自行 watch
/// （桌面端缓存的 IndexedStack 子页也能正确刷新）。
final agentTabSubPageProvider = StateProvider<bool>((ref) => false);

/// 发现 tab 当前类型：false=网络智能体 true=网络群聊
///
/// 同样由 HomeScreen 的子页分段控件翻转，NetworkContentTab watch 后重新拉取列表。
final discoveryTabTypeProvider = StateProvider<bool>((ref) => false);

/// 智能体列表（contact_list）是否处于多选模式
///
/// ContactListWidget 进入/退出多选时更新；HomeScreen 监听后在多选中隐藏
/// 浮动的子页分段控件，避免遮挡多选底栏（加入编组/编辑/删除）。
final contactSelectionModeProvider = StateProvider<bool>((ref) => false);
