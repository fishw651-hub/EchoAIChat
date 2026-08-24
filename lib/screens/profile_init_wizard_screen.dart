import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/profile_entry.dart';
import '../providers/user_profile_provider.dart';

/// 画像初始化问卷：8 个分类各问 1 个引导问题，用户可留空跳过。
/// 触发条件：新建 Agent + 启用真实信息 + 当前 user_profiles 表为空。
class ProfileInitWizardScreen extends ConsumerStatefulWidget {
  const ProfileInitWizardScreen({super.key});

  @override
  ConsumerState<ProfileInitWizardScreen> createState() => _ProfileInitWizardScreenState();
}

class _ProfileInitWizardScreenState extends ConsumerState<ProfileInitWizardScreen> {
  int _step = 0;
  bool _saving = false;
  final List<TextEditingController> _controllers = [];

  static const _steps = [
    _WizardStep(category: 'basic_info', icon: Icons.person_outline, keyHint: '姓名'),
    _WizardStep(category: 'work_study', icon: Icons.work_outline, keyHint: '职业'),
    _WizardStep(category: 'interests', icon: Icons.favorite_outline, keyHint: '爱好'),
    _WizardStep(category: 'personality', icon: Icons.psychology_outlined, keyHint: '性格'),
    _WizardStep(category: 'habits', icon: Icons.schedule_outlined, keyHint: '作息'),
    _WizardStep(category: 'preferences', icon: Icons.palette_outlined, keyHint: '偏好'),
    _WizardStep(category: 'social', icon: Icons.groups_outlined, keyHint: '社交'),
    _WizardStep(category: 'health', icon: Icons.health_and_safety_outlined, keyHint: '健康'),
  ];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _steps.length; i++) {
      _controllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final entries = <ProfileEntryDraft>[];
    for (int i = 0; i < _steps.length; i++) {
      final answer = _controllers[i].text.trim();
      if (answer.isEmpty) continue;
      entries.add(ProfileEntryDraft(
        category: _steps[i].category,
        key: _steps[i].keyHint,
        value: answer,
        confidence: 95,
        source: 'init_wizard',
      ));
    }
    try {
      await profileNotifier.createProfiles(entries);
    } catch (e) {
      debugPrint('[ProfileWizard] create profiles failed: $e');
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('profileInitComplete'))),
      );
      Navigator.pop(context);
    }
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  void _skip() {
    _controllers[_step].clear();
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;
    final progress = (_step + 1) / _steps.length;

    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: l10n.get('skip'),
          ),
          title: Text(l10n.get('profileInitTitle')),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 进度
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.get('profileInitStep').replaceAll('{n}', (_step + 1).toString()).replaceAll('{total}', _steps.length.toString()),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(),
                        // 问题卡片
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(step.icon, size: 48, color: scheme.primary),
                                const SizedBox(height: 16),
                                Text(
                                  ProfileEntry.categoryLabels[step.category] ?? step.category,
                                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _getQuestion(l10n, step.category),
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                TextField(
                                  controller: _controllers[_step],
                                  maxLines: 4,
                                  autofocus: true,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    hintText: l10n.get('profileInitHint'),
                                  ),
                                  onSubmitted: (_) => _next(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 底部按钮
                        Row(
                          children: [
                            if (_step > 0)
                              TextButton(
                                onPressed: _prev,
                                child: Text(l10n.get('previous')),
                              ),
                            const Spacer(),
                            TextButton(
                              onPressed: _skip,
                              child: Text(l10n.get('skip')),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving ? null : (isLast ? _finish : _next),
                              child: _saving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(isLast ? l10n.get('finish') : l10n.get('next')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _getQuestion(AppLocalizations l10n, String category) {
    return l10n.get('profileInitQuestion_$category');
  }
}

class _WizardStep {
  final String category;
  final IconData icon;
  final String keyHint;
  const _WizardStep({required this.category, required this.icon, required this.keyHint});
}
