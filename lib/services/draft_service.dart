import 'database_service.dart';

/// 上传草稿（draft_uploads 表）的本地持久化服务。
///
/// 草稿箱页面与网络上传页统一经此服务读写草稿，
/// screens/widgets 不直接触 DatabaseService。
class DraftService {
  /// 列出草稿；type 为 null 返回全部，否则按 'agent' / 'group' 过滤
  Future<List<Map<String, dynamic>>> listDrafts({String? type}) {
    if (type == null) return DatabaseService.getAllDrafts();
    return DatabaseService.getDraftsByType(type);
  }

  Future<Map<String, dynamic>?> getDraft(String id) {
    return DatabaseService.getDraft(id);
  }

  /// 保存草稿：draftId 非空时更新原草稿，否则新建。返回草稿 id。
  Future<String> saveDraft({
    String? draftId,
    required String type,
    required String data,
    String? name,
    int? coverColor,
  }) async {
    if (draftId != null) {
      await DatabaseService.updateDraft(
        draftId,
        name: name,
        data: data,
        coverColor: coverColor,
      );
      return draftId;
    }
    return DatabaseService.insertDraft(
      type: type,
      data: data,
      name: name,
      coverColor: coverColor,
    );
  }

  Future<void> deleteDraft(String id) {
    return DatabaseService.deleteDraft(id);
  }

  /// 批量删除（草稿箱"清空"）
  Future<void> deleteDrafts(Iterable<String> ids) async {
    for (final id in ids) {
      await DatabaseService.deleteDraft(id);
    }
  }
}
