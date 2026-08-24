import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/voice_input_service.dart';
import '../theme/app_theme.dart';

/// 语音栏：按住说话（识别结果实时上屏 + 音量指示条），松开后文本填入
/// 普通输入框可编辑再发送；按住期间手指在栏左右半侧滑动切换模式
/// （左半 语言 / 右半（动作），以中线实时判定），分段胶囊仅作指示器。
///
/// 识别状态机由持有方（chat_screen）驱动，本组件只负责展示与手势上报。
class VoiceInputBar extends StatelessWidget {
  /// 当前发送模式（语言 / 动作），分段胶囊据此高亮
  final VoiceSendMode sendMode;

  /// 是否处于"按住说话"会话中（含启动中）
  final bool listening;

  /// 识别结果实时文本（部分/最终结果）
  final String text;

  /// 识别服务最新状态（listening/done/notListening...），区分启动中与聆听中
  final String status;

  /// 识别服务回调的音量电平（约 -2~10 dB），驱动收音指示条
  final double soundLevel;

  /// 按住开始
  final VoidCallback onHoldStart;

  /// 按住期间手指滑动（dx 为栏内横坐标，width 为栏宽）
  final void Function(double dx, double width) onHoldSlide;

  /// 松开 / 手势被打断（结束识别并提交草稿）
  final VoidCallback onHoldEnd;

  const VoiceInputBar({
    super.key,
    required this.sendMode,
    required this.listening,
    required this.text,
    required this.status,
    required this.soundLevel,
    required this.onHoldStart,
    required this.onHoldSlide,
    required this.onHoldEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final displayText = listening
        ? (text.isNotEmpty
              ? text
              // 识别服务已报 listening → "正在聆听"，否则还在启动中
              : status == 'listening'
              ? l10n.get('voiceListening')
              : l10n.get('voiceStarting'))
        : l10n.get('voiceHoldToTalk');
    // 音量电平归一化（Android SpeechRecognizer 电平约 -2~10 dB）
    final level01 = ((soundLevel + 2) / 12).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (_) => onHoldStart(),
          // 与长按说话共用同一手势识别器（无竞技场冲突）：
          // 手指横坐标越过栏中线即切换模式
          onLongPressMoveUpdate: (details) =>
              onHoldSlide(details.localPosition.dx, barWidth),
          onLongPressEnd: (_) => onHoldEnd(),
          onLongPressCancel: () => onHoldEnd(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppTheme.durFast,
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                // 无边框融入外层容器，仅录音时给一点主题色底色作反馈
                decoration: BoxDecoration(
                  color: listening ? scheme.primary.withValues(alpha: 0.1) : null,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Row(
                  children: [
                    Icon(
                      listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      size: 20,
                      color: listening ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    // 收音指示条：随 onSoundLevelChange 电平起伏，
                    // 让用户确认麦克风确实在收音
                    if (listening) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: LinearProgressIndicator(
                          value: level01,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          color: scheme.primary,
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: listening && text.isNotEmpty
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 分段胶囊为纯指示器：实时高亮当前模式
                    // （按住期间左右滑动栏身切换，无点按）
                    _buildVoiceModeChip(l10n, scheme),
                  ],
                ),
              ),
              // 切换方式小字提示（录音时隐藏，避免跳动）
              if (!listening)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.get('voiceSwitchModeHint'),
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 语音发送模式分段胶囊（语言 | （动作））：纯指示器，
  /// 当前模式高亮（按住说话期间滑动切换时实时刷新）。
  Widget _buildVoiceModeChip(AppLocalizations l10n, ColorScheme scheme) {
    final isAction = sendMode == VoiceSendMode.action;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildVoiceModeSegment(
            label: l10n.get('voiceModeReply'),
            active: !isAction,
            accent: scheme.primary,
            scheme: scheme,
          ),
          _buildVoiceModeSegment(
            label: l10n.get('voiceModeAction'),
            active: isAction,
            accent: scheme.tertiary,
            scheme: scheme,
          ),
        ],
      ),
    );
  }

  /// 分段胶囊的单段：激活时高亮底色 + 彩色加粗文字
  Widget _buildVoiceModeSegment({
    required String label,
    required bool active,
    required Color accent,
    required ColorScheme scheme,
  }) {
    return AnimatedContainer(
      duration: AppTheme.durFast,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          color: active ? accent : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
