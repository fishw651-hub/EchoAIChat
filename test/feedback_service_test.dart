import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/services/feedback_service.dart';

void main() {
  group('FeedbackItem.fromJson', () {
    test('解析完整字段', () {
      final item = FeedbackItem.fromJson({
        'id': 7,
        'category': 'bug',
        'content': '闪退问题',
        'status': 2,
        'reply': '已修复，请更新到最新版',
        'created_at': '2026-07-20T10:30:00Z',
      });
      expect(item.id, 7);
      expect(item.category, 'bug');
      expect(item.content, '闪退问题');
      expect(item.status, 2);
      expect(item.reply, '已修复，请更新到最新版');
      expect(item.createdAt, isNotNull);
      expect(item.hasReply, isTrue);
    });

    test('缺失字段使用安全默认值', () {
      final item = FeedbackItem.fromJson({});
      expect(item.id, 0);
      expect(item.category, 'other');
      expect(item.content, '');
      expect(item.status, 0);
      expect(item.reply, '');
      expect(item.createdAt, isNull);
      expect(item.hasReply, isFalse);
    });

    test('状态为已回复但回复为空时 hasReply 为 false', () {
      final item = FeedbackItem.fromJson({'status': 2, 'reply': '   '});
      expect(item.hasReply, isFalse);
    });
  });

  group('FeedbackService.parseList', () {
    test('data 为 null（服务端无记录）时返回空列表', () {
      expect(FeedbackService.parseList(null), isEmpty);
    });

    test('解析反馈列表', () {
      final items = FeedbackService.parseList([
        {
          'id': 2,
          'category': 'ui',
          'content': '建议深色模式',
          'status': 1,
          'reply': '',
          'created_at': '2026-07-21T08:00:00Z',
        },
        {
          'id': 1,
          'category': 'feature',
          'content': '希望支持导出聊天记录',
          'status': 0,
          'reply': '',
          'created_at': '2026-07-20T08:00:00Z',
        },
      ]);
      expect(items.length, 2);
      expect(items.first.id, 2);
      expect(items.first.status, 1);
      expect(items.last.category, 'feature');
    });

    test('跳过非 Map 项', () {
      final items = FeedbackService.parseList([
        'garbage',
        {'id': 3, 'content': '正常项'},
      ]);
      expect(items.length, 1);
      expect(items.single.id, 3);
    });
  });
}
