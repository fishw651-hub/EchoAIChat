import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';
import '../providers/memory_provider.dart';
import '../services/backup_service.dart';
import '../agreements/user_agreement.dart';
import '../agreements/privacy_policy.dart';
import '../agreements/network_usage_agreement.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/echo_profile_motion.dart';
import '../widgets/echo_visual_surface.dart';
import '../widgets/feedback_dialog.dart';
import 'feedback_track_screen.dart';
import 'novel_history_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _roundsController = TextEditingController();
  Timer? _roundsSaveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = ref.read(settingsProvider);
      _roundsController.text = s.maxShortTermRounds.toString();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _roundsSaveTimer?.cancel();
    _roundsController.dispose();
    super.dispose();
  }

  void _scheduleRoundsSave(String value) {
    final rounds = int.tryParse(value);
    if (rounds == null) return;
    _roundsSaveTimer?.cancel();
    _roundsSaveTimer = Timer(const Duration(milliseconds: 320), () {
      _saveRounds(rounds);
    });
  }

  void _saveRounds(int rounds) {
    if (!mounted) return;
    if (ref.read(settingsProvider).maxShortTermRounds == rounds) return;
    ref.read(settingsProvider.notifier).updateMaxShortTermRounds(rounds);
    ref.read(memoryServiceProvider).maxShortTermRounds = rounds;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error
            ? scheme.errorContainer
            : scheme.primaryContainer,
        showCloseIcon: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sectionBuilders = <Widget Function()>[
      () => _buildOverviewCard(scheme, l10n),
      () => _sectionHeader(l10n.get('memoryAndData')),
      () => _buildMemoryDataSection(s),
      () => _sectionHeader(l10n.get('backupAndRestore')),
      _buildConfigSection,
      () => _sectionHeader(l10n.get('theme')),
      _buildThemeSection,
      () => _sectionHeader(l10n.get('agreementsAndLegal')),
      _buildAgreementsSection,
      () => _sectionHeader(l10n.get('feedback')),
      _buildFeedbackSection,
    ];

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(l10n.get('settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 40),
            itemCount: sectionBuilders.length,
            itemBuilder: (context, index) => sectionBuilders[index](),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ColorScheme scheme, AppLocalizations l10n) {
    return Container(
      key: const ValueKey('settingsOverview'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.72),
            scheme.tertiaryContainer.withValues(alpha: 0.42),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.brXl,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: AppTheme.primaryShadowSm(scheme),
      ),
      child: ClipRRect(
        borderRadius: AppTheme.brXl,
        child: Stack(
          children: [
            Positioned(
              right: -36,
              top: -46,
              child: IgnorePointer(
                child: EchoOrbitRings(
                  color: scheme.primary.withValues(alpha: 0.13),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: Row(
                children: [
                  EchoIconBadge(
                    icon: Icons.tune_rounded,
                    size: 48,
                    iconSize: 24,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppTheme.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.get('settingsOverviewTitle'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppTheme.space1),
                        Text(
                          l10n.get('settingsOverviewSubtitle'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ 反馈 ═══

  Widget _buildFeedbackSection() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      children: [
        InkWell(
          onTap: () => FeedbackDialog.show(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                EchoIconBadge(icon: Icons.feedback_outlined, color: scheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.get('feedback'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.get('feedbackSubtitle'),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          indent: 60,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FeedbackTrackScreen()),
          ),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                EchoIconBadge(
                  icon: Icons.track_changes_outlined,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.get('feedbackTrack'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.get('feedbackTrackSubtitle'),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══ 协议与法律 ═══

  Widget _buildAgreementsSection() {
    final l10n = AppLocalizations.of(context);
    return _sectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _agreementTile(
                icon: Icons.description,
                title: l10n.get('userAgreement'),
                subtitle: UserAgreement.version,
                content: UserAgreement.content,
                displayTitle: UserAgreement.title,
              ),
              const Divider(height: 1),
              _agreementTile(
                icon: Icons.privacy_tip,
                title: l10n.get('privacyPolicy'),
                subtitle: PrivacyPolicy.version,
                content: PrivacyPolicy.content,
                displayTitle: PrivacyPolicy.title,
              ),
              const Divider(height: 1),
              _agreementTile(
                icon: Icons.public,
                title: l10n.get('networkUsageAgreement'),
                subtitle: NetworkUsageAgreement.version,
                content: NetworkUsageAgreement.content,
                displayTitle: NetworkUsageAgreement.title,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _agreementTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String content,
    required String displayTitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showAgreementContent(displayTitle, content),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            EchoIconBadge(icon: icon, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  void _showAgreementContent(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              content,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.brLg,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  }

  // ═══ 4. Memory & Data ═══

  Widget _buildMemoryDataSection(SettingsState s) {
    final l10n = AppLocalizations.of(context);
    final shortDesc =
        '${l10n.get('retain')} ${s.maxShortTermRounds} ${l10n.get('roundsUnit')}';
    return _sectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _listTileRow(
                Icons.memory,
                l10n.get('shortTermMemory'),
                shortDesc,
                null,
                trailing: SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _roundsController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: _scheduleRoundsSave,
                    onEditingComplete: () {
                      _roundsSaveTimer?.cancel();
                      final rounds = int.tryParse(_roundsController.text);
                      if (rounds != null) _saveRounds(rounds);
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              _listTileRow(
                Icons.auto_awesome,
                l10n.get('novelHistory'),
                l10n.get('novelHistoryDesc'),
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NovelHistoryScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _listTileRow(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap, {
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            EchoIconBadge(icon: icon, color: scheme.tertiary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }

  // ═══ 5. Config Import/Export ═══

  Widget _buildConfigSection() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.get('backupRestoreHint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space3),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.backup, size: 18),
                  label: Text(l10n.get('backupDatabase')),
                  onPressed: _backupDatabase,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restore, size: 18),
                  label: Text(l10n.get('restoreDatabase')),
                  onPressed: _restoreDatabase,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _backupDatabase() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await BackupService().backup();
      if (result.inDownloads) {
        _snack('${l10n.get('backupSaved')}: ${result.fileName}');
      } else {
        _snack('${l10n.get('backupSaved')}: ${result.path}');
      }
    } catch (e) {
      _snack('${l10n.get('backupFailed')}: $e', error: true);
    }
  }

  Future<void> _restoreDatabase() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 32,
          ),
          title: Text(l10n.get('restoreDatabase')),
          content: Text(l10n.get('restoreDbConfirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.get('confirmResetAction')),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await BackupService().restore(result.files.single.path!);
        _snack(l10n.get('dbRestored'));
      }
    } catch (e) {
      _snack('${l10n.get('restoreFailed')}: $e', error: true);
    }
  }

  // ═══ 6. Theme ═══

  ThemeMode _themeModeFromString(String mode) => switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  String _themeModeToString(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  Widget _buildThemeSection() {
    final s = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EchoIconBadge(
                    icon: Icons.brightness_6_rounded,
                    color: scheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.get('themeMode'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space3),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(
                        Icons.brightness_auto_outlined,
                        size: 16,
                      ),
                      label: Text(l10n.get('systemTheme')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_outlined, size: 16),
                      label: Text(l10n.get('lightTheme')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_outlined, size: 16),
                      label: Text(l10n.get('darkTheme')),
                    ),
                  ],
                  selected: {_themeModeFromString(s.themeMode)},
                  onSelectionChanged: (selection) {
                    ref
                        .read(settingsProvider.notifier)
                        .updateThemeMode(_themeModeToString(selection.first));
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
