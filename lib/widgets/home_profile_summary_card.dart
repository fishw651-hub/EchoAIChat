import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/profile_entry.dart';
import '../theme/app_theme.dart';
import 'echo_profile_motion.dart';

class HomeProfileSummaryCard extends StatefulWidget {
  const HomeProfileSummaryCard({
    super.key,
    required this.entries,
    required this.totalCount,
    required this.onOpenProfile,
  });

  final List<ProfileEntry> entries;
  final int totalCount;
  final VoidCallback onOpenProfile;

  @override
  State<HomeProfileSummaryCard> createState() => _HomeProfileSummaryCardState();
}

class _HomeProfileSummaryCardState extends State<HomeProfileSummaryCard>
    with WidgetsBindingObserver {
  Timer? _rotationTimer;
  int _rememberedIndex = 0;
  bool _motionEnabled = true;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _syncRotationTimer();
  }

  @override
  void didUpdateWidget(covariant HomeProfileSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entrySignature(oldWidget.entries) != _entrySignature(widget.entries)) {
      _rememberedIndex = 0;
      _syncRotationTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncRotationTimer();
  }

  void _syncRotationTimer() {
    _rotationTimer?.cancel();
    final candidates = _rememberedEntries(widget.entries);
    if (!_motionEnabled || !_appActive || candidates.length < 2) return;
    _rotationTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        _rememberedIndex = (_rememberedIndex + 1) % candidates.length;
      });
    });
  }

  List<ProfileEntry> _sortedEntries(List<ProfileEntry> source) {
    return [...source]
      ..sort((first, second) => second.updatedAt.compareTo(first.updatedAt));
  }

  List<ProfileEntry> _rememberedEntries(List<ProfileEntry> source) {
    return _sortedEntries(source).skip(1).take(5).toList(growable: false);
  }

  String _entrySignature(List<ProfileEntry> source) {
    return source
        .map((entry) => '${entry.id}:${entry.updatedAt.microsecondsSinceEpoch}')
        .join('|');
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlights = _sortedEntries(widget.entries);
    final remembered = highlights.length > 1
        ? highlights
              .skip(1)
              .take(5)
              .elementAt(_rememberedIndex % (highlights.length - 1).clamp(1, 5))
        : null;
    final foreground = scheme.onPrimary;
    final l10n = AppLocalizations.of(context);

    return Semantics(
      button: true,
      label: l10n.get('openProfileCardLabel'),
      child: Material(
        color: const Color(0x00000000),
        child: InkWell(
          onTap: widget.onOpenProfile,
          borderRadius: AppTheme.brXl,
          child: Container(
            key: const ValueKey('homeProfileCardSurface'),
            constraints: const BoxConstraints(minHeight: 164),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space5,
              vertical: AppTheme.space4,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.92),
                  scheme.primary,
                  scheme.primary.withValues(alpha: 0.82),
                ],
              ),
              borderRadius: AppTheme.brXl,
              border: Border.all(
                color: scheme.onPrimary.withValues(alpha: 0.12),
              ),
              boxShadow: AppTheme.primaryShadowMd(scheme),
            ),
            child: Stack(
              children: [
                Positioned(
                  key: const ValueKey('homeProfileOrbitRings'),
                  right: -36,
                  top: -46,
                  child: IgnorePointer(
                    child: EchoOrbitRings(
                      color: foreground.withValues(alpha: 0.13),
                      animate: _motionEnabled,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        EchoVoiceWave(
                          key: const ValueKey('homeProfileVoiceWave'),
                          color: foreground.withValues(alpha: 0.82),
                          animate: _motionEnabled,
                        ),
                        const SizedBox(width: AppTheme.space2),
                        Text(
                          l10n.get('youInMyEyes'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      widget.totalCount == 0
                          ? l10n.get('profileFormingHint')
                          : _headline(highlights),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: AppTheme.space1),
                    if (highlights.isEmpty)
                      Text(
                        l10n.get('chatLongerUnderstand'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground.withValues(alpha: 0.76),
                        ),
                      )
                    else
                      AnimatedSwitcher(
                        duration: _motionEnabled
                            ? const Duration(milliseconds: 220)
                            : Duration.zero,
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: Text(
                          remembered == null
                              ? l10n.get('latestObservation')
                              : l10n.getP('rememberObservation', {
                                  'key': remembered.key,
                                  'value': remembered.value,
                                }),
                          key: ValueKey(remembered?.id ?? 'single-profile'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.76),
                              ),
                        ),
                      ),
                    const SizedBox(height: AppTheme.space3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.getP('observationCount', {
                              'count': '${widget.totalCount}',
                            }),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: foreground.withValues(alpha: 0.7),
                                ),
                          ),
                        ),
                        Text(
                          l10n.get('viewFullProfile'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: AppTheme.space1),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: foreground,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _headline(List<ProfileEntry> highlights) {
    final first = highlights.first;
    return '${first.key}，${first.value}';
  }
}
