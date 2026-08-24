import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class EchoConversationTile extends StatelessWidget {
  const EchoConversationTile({
    super.key,
    required this.avatar,
    required this.title,
    required this.preview,
    this.timestamp,
    this.unreadCount = 0,
    this.showDivider = true,
    required this.onTap,
  });

  final Widget avatar;
  final String title;
  final String preview;
  final DateTime? timestamp;
  final int unreadCount;

  /// 是否在 tile 底部渲染分隔线（卡片化列表中末个 tile 置 false）
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: AppLocalizations.of(
        context,
      ).getP('conversationWith', {'title': title}),
      child: Material(
        color: scheme.surfaceContainerLowest,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space4,
                  AppTheme.space3,
                  AppTheme.space4,
                  AppTheme.space3,
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: AppTheme.brMd,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                          width: 0.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: AppTheme.brMd,
                        child: avatar,
                      ),
                    ),
                    const SizedBox(width: AppTheme.space3),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (timestamp != null)
                                Text(
                                  _formatTimestamp(timestamp!),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.72),
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.space1),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.25,
                                      ),
                                ),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(width: AppTheme.space2),
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showDivider)
                Container(
                  key: const Key('conversation-divider'),
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 76),
                  color: scheme.outlineVariant.withValues(alpha: 0.48),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final dayDifference = today.difference(date).inDays;
    if (dayDifference == 0) return DateFormat('HH:mm').format(timestamp);
    if (dayDifference == 1) return AppLocalizations.instance.get('yesterday');
    if (now.year == timestamp.year) return DateFormat('M/d').format(timestamp);
    return DateFormat('yyyy/M/d').format(timestamp);
  }
}
