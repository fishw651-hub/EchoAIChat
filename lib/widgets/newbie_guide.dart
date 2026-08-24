import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../screens/agent_create_screen.dart';
import '../screens/group_create_screen.dart';
import '../theme/app_theme.dart';

/// 新手引导：新账号首次进入主界面时询问是否需要指导，
/// 需要则分步教用户创建第一个智能体或模拟器（用户自选）。
class NewbieGuide {
  static const _keyPrefix = 'newbie_guide_done_';

  /// 判断是否应展示引导：本账号未看过引导 且 没有任何智能体和群聊（新账号）。
  /// 满足条件时弹出询问对话框。每次启动最多调用一次（由 HomeScreen 触发）。
  static Future<void> maybeShow(
    BuildContext context, {
    required String userId,
    required bool hasAgents,
    required bool hasGroups,
  }) async {
    if (userId.isEmpty || hasAgents || hasGroups) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_keyPrefix$userId') == true) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _GuideDialog(),
    );
    await prefs.setBool('$_keyPrefix$userId', true);
  }
}

enum _GuidePhase { ask, choose, steps }

class _GuideDialog extends StatefulWidget {
  const _GuideDialog();

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  _GuidePhase _phase = _GuidePhase.ask;
  bool _choseAgent = true; // true=智能体 false=模拟器
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: switch (_phase) {
        _GuidePhase.ask => _buildAsk(l10n, scheme),
        _GuidePhase.choose => _buildChoose(l10n, scheme),
        _GuidePhase.steps => _buildSteps(l10n, scheme),
      },
    );
  }

  Widget _buildAsk(AppLocalizations l10n, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.school_outlined, size: 48, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          l10n.get('guideAskTitle'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.get('guideAskDesc'),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.get('guideSkip')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() => _phase = _GuidePhase.choose),
                child: Text(l10n.get('guideStart')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildChoose(AppLocalizations l10n, ColorScheme scheme) {
    Widget option({
      required IconData icon,
      required String title,
      required String desc,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTheme.durFast,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.get('guideChooseTitle'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        option(
          icon: Icons.person_outline_rounded,
          title: l10n.get('guideAgentOption'),
          desc: l10n.get('guideAgentOptionDesc'),
          selected: _choseAgent,
          onTap: () => setState(() => _choseAgent = true),
        ),
        const SizedBox(height: 10),
        option(
          icon: Icons.groups_outlined,
          title: l10n.get('guideSimOption'),
          desc: l10n.get('guideSimOptionDesc'),
          selected: !_choseAgent,
          onTap: () => setState(() => _choseAgent = false),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() {
              _step = 0;
              _phase = _GuidePhase.steps;
            }),
            child: Text(l10n.get('guideNext')),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSteps(AppLocalizations l10n, ColorScheme scheme) {
    const total = 3;
    final titles = _choseAgent
        ? [
            l10n.get('guideAgentStep1Title'),
            l10n.get('guideAgentStep2Title'),
            l10n.get('guideAgentStep3Title'),
          ]
        : [
            l10n.get('guideSimStep1Title'),
            l10n.get('guideSimStep2Title'),
            l10n.get('guideSimStep3Title'),
          ];
    final descs = _choseAgent
        ? [
            l10n.get('guideAgentStep1Desc'),
            l10n.get('guideAgentStep2Desc'),
            l10n.get('guideAgentStep3Desc'),
          ]
        : [
            l10n.get('guideSimStep1Desc'),
            l10n.get('guideSimStep2Desc'),
            l10n.get('guideSimStep3Desc'),
          ];
    final isLast = _step == total - 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.getP('guideStepProgress', {'n': '${_step + 1}', 'total': '$total'}),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Icon(
          _choseAgent ? Icons.person_outline_rounded : Icons.groups_outlined,
          size: 40,
          color: scheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          titles[_step],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          descs[_step],
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  child: Text(l10n.get('guidePrev')),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  if (!isLast) {
                    setState(() => _step++);
                    return;
                  }
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _choseAgent
                          ? const AgentCreateScreen()
                          : const GroupCreateScreen(),
                    ),
                  );
                },
                child: Text(isLast ? l10n.get('guideGoCreate') : l10n.get('guideNext')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
