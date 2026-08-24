import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';

/// 反馈追踪：查看本人提交的反馈及开发者回复
class FeedbackTrackScreen extends ConsumerStatefulWidget {
  const FeedbackTrackScreen({super.key});

  @override
  ConsumerState<FeedbackTrackScreen> createState() =>
      _FeedbackTrackScreenState();
}

class _FeedbackTrackScreenState extends ConsumerState<FeedbackTrackScreen> {
  List<FeedbackItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final items = await FeedbackService.listMine(
        auth: ref.read(authProvider),
        loginRequiredMessage: AppLocalizations.of(
          context,
        ).get('feedbackLoginRequired'),
      );
      if (!mounted) return;
      setState(() => _items = items);
    } on FeedbackException catch (e) {
      if (!mounted) return;
      setState(() {
        _items = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = null;
        _error = e.toString();
      });
    }
  }

  String _categoryLabel(AppLocalizations l10n, String code) {
    const keys = {
      'feature': 'feedbackCatFeature',
      'feature_tweak': 'feedbackCatFeatureTweak',
      'bug': 'feedbackCatBug',
      'ui': 'feedbackCatUi',
      'pricing': 'feedbackCatPricing',
      'other': 'feedbackCatOther',
    };
    return l10n.get(keys[code] ?? 'feedbackCatOther');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = _items;

    Widget body;
    if (_error != null) {
      body = _buildCentered(
        scheme,
        icon: Icons.error_outline,
        title: l10n.get('loadFailed'),
        subtitle: _error,
        action: FilledButton.tonal(
          onPressed: _load,
          child: Text(l10n.get('retry')),
        ),
      );
    } else if (items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      body = _buildCentered(
        scheme,
        icon: Icons.inbox_outlined,
        title: l10n.get('feedbackEmpty'),
        subtitle: l10n.get('feedbackEmptyHint'),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildItem(items[index], l10n),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(l10n.get('feedbackTrack'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(onRefresh: _load, child: body),
        ),
      ),
    );
  }

  Widget _buildCentered(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: AppTheme.space3),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: AppTheme.space4),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(FeedbackItem item, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final (badgeBg, badgeFg, badgeText) = switch (item.status) {
      1 => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        l10n.get('feedbackStatusProcessing'),
      ),
      2 => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        l10n.get('feedbackStatusReplied'),
      ),
      3 => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        l10n.get('feedbackStatusClosed'),
      ),
      _ => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        l10n.get('feedbackStatusPending'),
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppTheme.space4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppTheme.brLg,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _categoryLabel(l10n, item.category),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space2),
          Text(item.content, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: AppTheme.space2),
          Text(
            item.createdAt != null
                ? DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt!)
                : '',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (item.hasReply) ...[
            const SizedBox(height: AppTheme.space3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.space3),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.35),
                borderRadius: AppTheme.brMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.support_agent,
                        size: 14,
                        color: scheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.get('feedbackDevReply'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space1),
                  Text(item.reply, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
