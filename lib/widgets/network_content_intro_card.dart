import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../theme/app_theme.dart';

class NetworkContentIntroCard extends StatelessWidget {
  final String title;
  final String description;
  final String? worldview;
  final String? groupSetting;
  final List<String> memberNames;
  final VoidCallback onDismiss;

  const NetworkContentIntroCard._({
    required this.title,
    required this.description,
    required this.worldview,
    required this.groupSetting,
    required this.memberNames,
    required this.onDismiss,
  });

  factory NetworkContentIntroCard.agent({
    required Agent agent,
    required VoidCallback onDismiss,
  }) {
    return NetworkContentIntroCard._(
      title: agent.name,
      description: agent.description,
      worldview: agent.worldview,
      groupSetting: null,
      memberNames: const [],
      onDismiss: onDismiss,
    );
  }

  factory NetworkContentIntroCard.group({
    required GroupChat group,
    required List<String> memberNames,
    required VoidCallback onDismiss,
  }) {
    return NetworkContentIntroCard._(
      title: group.name,
      description: group.description,
      worldview: group.worldSetting,
      groupSetting: group.groupPersona,
      memberNames: memberNames,
      onDismiss: onDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final hasDescription = description.trim().isNotEmpty;
    final hasWorldview = worldview?.trim().isNotEmpty == true;
    final hasGroupSetting = groupSetting?.trim().isNotEmpty == true;

    return Semantics(
      container: true,
      label: l10n.get('contentIntro'),
      child: Container(
        key: const Key('network-content-archive'),
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space4,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppTheme.brSm,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.035),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 28,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '网络作品档案',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        l10n.get('contentIntro'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasDescription) ...[
              const SizedBox(height: AppTheme.space1),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasWorldview)
              _ArchiveSection(
                key: const Key('network-content-section-worldview'),
                index: '01',
                label: l10n.get('worldview'),
                icon: Icons.public_outlined,
                value: worldview!,
              ),
            if (hasGroupSetting)
              _ArchiveSection(
                index: '02',
                label: l10n.get('groupSetting'),
                icon: Icons.forum_outlined,
                value: groupSetting!,
              ),
            if (memberNames.isNotEmpty)
              _ArchiveSection(
                index: hasGroupSetting ? '03' : '02',
                label: l10n.get('members'),
                icon: Icons.people_outline,
                value: memberNames.join('、'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveSection extends StatelessWidget {
  final String index;
  final String label;
  final IconData icon;
  final String value;

  const _ArchiveSection({
    super.key,
    required this.index,
    required this.label,
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppTheme.space3),
      padding: const EdgeInsets.only(top: AppTheme.space3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.62)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              index,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space1),
                Text(value, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
