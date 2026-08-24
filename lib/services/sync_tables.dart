/// 参与多端同步的 13 张表清单。
///
/// 独立成无依赖的小模块，供 database_service（删除时记录墓碑）与
/// sync_service（上传/下载/合并）共用，破除两者之间的循环 import。
/// 依赖方向保持单向：sync_service → database_service。
const List<String> kSyncTables = [
  'agents',
  'chat_messages',
  'short_term_messages',
  'group_chats',
  'group_members',
  'group_messages',
  'group_short_term',
  'group_shared_memories',
  'long_term_memories',
  'base_memories',
  'planned_messages',
  'user_profiles',
  'providers',
];
