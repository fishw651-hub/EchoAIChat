import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/models/agent.dart';
import 'package:aichat/services/proactive_care_alarm.dart';
import 'package:aichat/services/proactive_care_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseAwakeWindow', () {
    test('空输入回退默认 8:00-20:00', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const []);
      expect(w.startMinutes, 8 * 60);
      expect(w.endMinutes, 20 * 60);
    });

    test('无法解析的文本回退默认', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['喜欢吃辣', '经常熬夜但没说几点']);
      expect(w.startMinutes, 8 * 60);
      expect(w.endMinutes, 20 * 60);
    });

    test('解析"23:30睡 7点起"', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['23:30睡 7点起']);
      expect(w.startMinutes, 7 * 60);
      expect(w.endMinutes, 23 * 60 + 30);
    });

    test('解析区间"7:00-23:00"', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['7:00-23:00']);
      expect(w.startMinutes, 7 * 60);
      expect(w.endMinutes, 23 * 60);
    });

    test('解析"晚上11点睡，早上7点起床"（11点→23点）', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['晚上11点睡，早上7点起床']);
      expect(w.startMinutes, 7 * 60);
      expect(w.endMinutes, 23 * 60);
    });

    test('只解析出睡觉时间时，起床侧用默认 8:00', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['一般22:30睡觉']);
      expect(w.startMinutes, 8 * 60);
      expect(w.endMinutes, 22 * 60 + 30);
    });

    test('只解析出起床时间时，睡觉侧用默认 20:00', () {
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['每天6:30起床']);
      expect(w.startMinutes, 6 * 60 + 30);
      expect(w.endMinutes, 20 * 60);
    });

    test('窗口倒置（起床晚于睡觉）回退默认', () {
      // "19点起"超出合法起床范围被丢弃，只剩"1点睡"也非法 → 整体回退
      final w = ProactiveCarePolicy.parseAwakeWindow(const ['19点起 1点睡']);
      expect(w.startMinutes, 8 * 60);
      expect(w.endMinutes, 20 * 60);
    });
  });

  group('pending reply detection', () {
    test('pending 后出现用户消息即视为已回复，与最后一条消息角色无关', () {
      final pendingSince = DateTime(2026, 8, 12, 9);

      expect(
        ProactiveCarePolicy.hasUserReplied(
          pendingSince: pendingSince,
          latestUserMessageTime: DateTime(2026, 8, 12, 9, 5),
        ),
        isTrue,
      );
      expect(
        ProactiveCarePolicy.hasUserReplied(
          pendingSince: pendingSince,
          latestUserMessageTime: DateTime(2026, 8, 12, 8, 59),
        ),
        isFalse,
      );
    });
  });

  group('proactive response length', () {
    test('uses the agent setting and clamps legacy values', () {
      expect(
        ProactiveCarePolicy.responseLengthGuidance(50),
        contains('50字以内'),
      );
      expect(
        ProactiveCarePolicy.responseLengthGuidance(800),
        contains('800字以内'),
      );
      expect(
        ProactiveCarePolicy.responseLengthGuidance(300),
        contains('300字以内'),
      );
      expect(
        ProactiveCarePolicy.responseLengthGuidance(10),
        contains('${Agent.minAllowedResponseLength}字以内'),
      );
    });
  });

  group('next proactive care alarm', () {
    const window = AwakeWindow(8 * 60, 20 * 60);

    test('窗口前安排到当天窗口开始', () {
      final now = DateTime(2026, 8, 12, 7, 30);
      expect(
        ProactiveCareAlarmScheduler.nextCheckTime(now: now, window: window),
        DateTime(2026, 8, 12, 8),
      );
    });

    test('窗口内安排到 30 分钟后', () {
      final now = DateTime(2026, 8, 12, 12);
      expect(
        ProactiveCareAlarmScheduler.nextCheckTime(now: now, window: window),
        DateTime(2026, 8, 12, 12, 30),
      );
    });

    test('窗口末尾安排到次日窗口开始', () {
      final now = DateTime(2026, 8, 12, 19, 45);
      expect(
        ProactiveCareAlarmScheduler.nextCheckTime(now: now, window: window),
        DateTime(2026, 8, 13, 8),
      );
    });
  });

}
