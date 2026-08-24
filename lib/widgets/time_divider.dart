import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// 微信式时间分割线：相邻消息间隔超过 [gapThreshold] 时显示。
const Duration kTimeDividerGap = Duration(minutes: 5);

/// 是否需要在 [previous] 与 [current] 两条消息之间插入时间分割线。
/// 首条消息（previous 为 null）总是显示。
bool shouldShowTimeDivider(DateTime current, DateTime? previous) {
  if (previous == null) return true;
  return current.difference(previous) > kTimeDividerGap;
}

/// 时间分割线的智能格式：
/// 今天 → HH:mm；昨天 → 昨天 HH:mm；今年 → M月d日 HH:mm；更早 → yyyy年M月d日 HH:mm
String formatTimeDivider(DateTime time, AppLocalizations l10n,
    {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final hm = DateFormat('HH:mm').format(time);
  final isToday =
      time.year == ref.year && time.month == ref.month && time.day == ref.day;
  if (isToday) return hm;
  final yesterday = ref.subtract(const Duration(days: 1));
  final isYesterday = time.year == yesterday.year &&
      time.month == yesterday.month &&
      time.day == yesterday.day;
  if (isYesterday) return '${l10n.get('yesterday')} $hm';
  final isZh = l10n.locale.languageCode == 'zh';
  if (time.year == ref.year) {
    return isZh
        ? DateFormat('M月d日 HH:mm').format(time)
        : '${DateFormat('MMM d').format(time)}, $hm';
  }
  return isZh
      ? DateFormat('yyyy年M月d日 HH:mm').format(time)
      : '${DateFormat('MMM d, yyyy').format(time)}, $hm';
}

/// 居中灰色时间分割线标签。
class TimeDivider extends StatelessWidget {
  final DateTime time;

  const TimeDivider({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          formatTimeDivider(time, l10n),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
