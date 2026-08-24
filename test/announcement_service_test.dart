import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aichat/services/announcement_service.dart';

Announcement _ann({
  String id = 'a1',
  AnnouncementFrequency frequency = AnnouncementFrequency.always,
  AnnouncementAudience audience = AnnouncementAudience.all,
  String updatedAt = '2026-08-01T00:00:00Z',
}) => Announcement(
  id: id,
  title: '标题',
  content: '内容',
  frequency: frequency,
  audience: audience,
  updatedAt: updatedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Announcement.fromJson 容错解析', () {
    test('完整字段正常解析', () {
      final a = Announcement.fromJson(const {
        'id': 7,
        'title': '维护通知',
        'content': '# Hello',
        'frequency': 'once',
        'audience': 'subscriber',
        'start_at': '2026-08-01T00:00:00Z',
        'end_at': '2026-08-10T00:00:00Z',
        'updated_at': '2026-08-02T03:04:05Z',
      });
      expect(a.id, '7'); // 数字 id 转字符串
      expect(a.title, '维护通知');
      expect(a.content, '# Hello');
      expect(a.frequency, AnnouncementFrequency.once);
      expect(a.audience, AnnouncementAudience.subscriber);
      expect(a.updatedAt, '2026-08-02T03:04:05Z');
    });

    test('字段缺失/未知枚举给默认值，不抛异常', () {
      final a = Announcement.fromJson(const {'id': 'x'});
      expect(a.id, 'x');
      expect(a.title, '');
      expect(a.content, '');
      // 未知/缺失频率按 always 处理（宁可多弹不漏弹），受众默认 all
      expect(a.frequency, AnnouncementFrequency.always);
      expect(a.audience, AnnouncementAudience.all);
      expect(a.updatedAt, '');

      final b = Announcement.fromJson(const {
        'id': 'y',
        'frequency': 'weekly',
        'audience': 'vip',
      });
      expect(b.frequency, AnnouncementFrequency.always);
      expect(b.audience, AnnouncementAudience.all);
    });
  });

  group('频率控制 shouldShow / markShown', () {
    test('once：未记录弹 → 记录后不弹 → updated_at 变化后重弹', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = _ann(frequency: AnnouncementFrequency.once);

      expect(AnnouncementService.shouldShow(a, prefs), isTrue);
      await AnnouncementService.markShown(a, prefs);
      expect(prefs.getString('annonce_once_a1'), a.updatedAt);
      expect(AnnouncementService.shouldShow(a, prefs), isFalse);

      // 内容更新（updated_at 变了）→ 重新弹
      final updated = _ann(
        frequency: AnnouncementFrequency.once,
        updatedAt: '2026-08-05T00:00:00Z',
      );
      expect(AnnouncementService.shouldShow(updated, prefs), isTrue);
    });

    test('daily：当天不重复弹，跨天重新弹', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = _ann(frequency: AnnouncementFrequency.daily);
      final day1 = DateTime(2026, 8, 9, 10);
      final day1Later = DateTime(2026, 8, 9, 23, 59);
      final day2 = DateTime(2026, 8, 10, 0, 1);

      expect(
        AnnouncementService.shouldShow(a, prefs, now: day1),
        isTrue,
      );
      await AnnouncementService.markShown(a, prefs, now: day1);
      expect(prefs.getString('annonce_daily_a1'), '2026-08-09');
      expect(
        AnnouncementService.shouldShow(a, prefs, now: day1Later),
        isFalse,
      );
      expect(AnnouncementService.shouldShow(a, prefs, now: day2), isTrue);
    });

    test('always：总是弹且 markShown 不落任何记录', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = _ann();

      expect(AnnouncementService.shouldShow(a, prefs), isTrue);
      await AnnouncementService.markShown(a, prefs);
      expect(prefs.getKeys(), isEmpty);
      expect(AnnouncementService.shouldShow(a, prefs), isTrue);
    });
  });

  group('recordDismiss 弹窗关闭记录', () {
    test('once：任一按钮（含直接关闭）都写 once 记录', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = _ann(frequency: AnnouncementFrequency.once);

      await AnnouncementService.recordDismiss(
        a,
        dontShowToday: false,
        prefs: prefs,
      );
      expect(AnnouncementService.shouldShow(a, prefs), isFalse);
    });

    test('daily：「关闭」不写记录，「今天不再提示」写 daily 记录', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = _ann(frequency: AnnouncementFrequency.daily);
      final now = DateTime(2026, 8, 9, 12);

      // 直接关闭 → 不写，稍后（同一天）仍应弹
      await AnnouncementService.recordDismiss(
        a,
        dontShowToday: false,
        prefs: prefs,
        now: now,
      );
      expect(prefs.getKeys(), isEmpty);
      expect(AnnouncementService.shouldShow(a, prefs, now: now), isTrue);

      // 今天不再提示 → 写 daily 记录，当天不再弹
      await AnnouncementService.recordDismiss(
        a,
        dontShowToday: true,
        prefs: prefs,
        now: now,
      );
      expect(AnnouncementService.shouldShow(a, prefs, now: now), isFalse);
    });

    test('always：两种按钮都不写记录', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = _ann();

      await AnnouncementService.recordDismiss(
        a,
        dontShowToday: false,
        prefs: prefs,
      );
      await AnnouncementService.recordDismiss(
        a,
        dontShowToday: true,
        prefs: prefs,
      );
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('matchesAudience 目标过滤', () {
    test('all 对所有用户可见', () {
      final a = _ann();
      expect(
        AnnouncementService.matchesAudience(a, hasActiveSubscription: true),
        isTrue,
      );
      expect(
        AnnouncementService.matchesAudience(a, hasActiveSubscription: false),
        isTrue,
      );
    });

    test('subscriber 仅订阅用户可见', () {
      final a = _ann(audience: AnnouncementAudience.subscriber);
      expect(
        AnnouncementService.matchesAudience(a, hasActiveSubscription: true),
        isTrue,
      );
      expect(
        AnnouncementService.matchesAudience(a, hasActiveSubscription: false),
        isFalse,
      );
    });

    test('free 仅非订阅用户可见', () {
      final a = _ann(audience: AnnouncementAudience.free);
      expect(
        AnnouncementService.matchesAudience(a, hasActiveSubscription: true),
        isFalse,
      );
      expect(
        AnnouncementService.matchesAudience(a, hasActiveSubscription: false),
        isTrue,
      );
    });
  });
}
