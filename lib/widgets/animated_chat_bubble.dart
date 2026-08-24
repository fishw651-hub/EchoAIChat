import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../screens/agent_create_screen.dart';
import '../services/feedback_analysis_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import 'agent_avatar.dart';
import 'chat_image_viewer.dart';
import 'echo_visual_surface.dart';
import 'message_action_sheet.dart';
import 'user_avatar.dart';

/// Animated chat bubble with slide/fade entrance
class AnimatedChatBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback onDelete;
  final VoidCallback? onRegenerate;
  final VoidCallback? onRewrite;
  final VoidCallback? onTap;
  final VoidCallback? onMultiSelect;
  final VoidCallback? onSelectToHere;
  final bool showCheckbox;
  final bool isSelected;

  const AnimatedChatBubble({
    super.key,
    required this.message,
    required this.onDelete,
    this.onRegenerate,
    this.onRewrite,
    this.onTap,
    this.onMultiSelect,
    this.onSelectToHere,
    this.showCheckbox = false,
    this.isSelected = false,
  });

  @override
  State<AnimatedChatBubble> createState() => _AnimatedChatBubbleState();
}

class _AnimatedChatBubbleState extends State<AnimatedChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _isHovered = false;

  // 文件存在性缓存：build 里 existsSync 是每帧同步系统调用，
  // 流式期间每个 token 都会触发——按路径缓存，widget 生命周期内有效
  final Map<String, bool> _fileExistsCache = {};

  bool _fileExists(String path) =>
      _fileExistsCache.putIfAbsent(path, () => File(path).existsSync());

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _scale = Tween<double>(
      begin: 0.93,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppTheme.curveSpring));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final agentState = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(agentProvider);

    final onBubbleColor = isUser ? scheme.onPrimary : scheme.onSurface;
    final maxBubbleWidth = ResponsiveLayout.bubbleMaxWidth(context);
    final stickerMarker = message.stickerDescription == null
        ? null
        : '[表情]${message.stickerDescription}';
    final visibleContent = stickerMarker == null
        ? message.content
        : message.content
              .split('\n')
              .where((line) => line.trim() != stickerMarker)
              .join('\n')
              .trim();
    final stickerAvailable =
        message.stickerPath != null &&
        !kIsWeb &&
        _fileExists(message.stickerPath!);
    final displayContent =
        !stickerAvailable && visibleContent.isEmpty && stickerMarker != null
        ? stickerMarker
        : visibleContent;
    // 消息图片（单图/多图）：仅保留本地文件仍存在的路径（存在性走缓存）
    final imagePaths = kIsWeb
        ? const <String>[]
        : message.allImagePaths
              .where((p) => _fileExists(p))
              .toList(growable: false);

    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (widget.showCheckbox)
                  GestureDetector(
                    onTap: widget.onTap,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        widget.isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: widget.isSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        size: 24,
                      ),
                    ),
                  ),
                if (!isUser && !widget.showCheckbox)
                  GestureDetector(
                    onTap: () {
                      final agent = agentState.currentAgent;
                      if (agent != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AgentCreateScreen(agent: agent),
                          ),
                        );
                      }
                    },
                    child: _agentAvatarSmall(agentState.currentAgent),
                  ),
                if (!isUser && !widget.showCheckbox) const SizedBox(width: 8),
                Flexible(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHovered = true),
                    onExit: (_) => setState(() => _isHovered = false),
                    child: GestureDetector(
                      onTap: widget.showCheckbox
                          ? (widget.onTap ?? () {})
                          : widget.onTap,
                      onLongPressStart: (d) {
                        if (!widget.showCheckbox) {
                          _showActionBar(context, d.globalPosition);
                        }
                      },
                      onSecondaryTapDown: ResponsiveLayout.isDesktop(context)
                          ? (d) => _showActionBar(context, d.globalPosition)
                          : null,
                      child: EchoBubbleSurface(
                        isUser: isUser,
                        isHovered: _isHovered,
                        isSelected: widget.isSelected,
                        maxWidth: maxBubbleWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (stickerAvailable)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSm,
                                ),
                                child: Image.file(
                                  File(message.stickerPath!),
                                  fit: BoxFit.contain,
                                  cacheWidth: 640,
                                ),
                              ),
                            if (imagePaths.isNotEmpty)
                              _buildMessageImages(imagePaths),
                            if (displayContent.isNotEmpty ||
                                message.isStreaming) ...[
                              if (imagePaths.isNotEmpty)
                                const SizedBox(height: 4),
                              Text(
                                message.isStreaming
                                    ? '${message.content}▌'
                                    : displayContent,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: onBubbleColor,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Text(
                                DateFormat('HH:mm').format(message.timestamp),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: onBubbleColor.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (isUser) const SizedBox(width: 8),
                if (isUser)
                  Consumer(
                    builder: (context, ref, _) {
                      final avatar = ref.watch(authProvider).user?.avatar;
                      if (avatar != null && avatar.isNotEmpty) {
                        return Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: AppTheme.primaryShadowSm(scheme),
                          ),
                          child: UserAvatar(avatar: avatar, radius: 18),
                        );
                      }
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.primaryShadowSm(scheme),
                        ),
                        child: Icon(
                          Icons.person,
                          color: scheme.onPrimary,
                          size: 20,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _agentAvatarSmall(dynamic agent) {
    final scheme = Theme.of(context).colorScheme;
    return AgentAvatar(
      name: agent?.name,
      avatarColor:
          agent?.avatarColor ?? scheme.surfaceContainerHighest.toARGB32(),
      avatarPath: agent?.avatarPath,
      size: 36,
      radius: 18,
      fontSize: 14,
      fallbackText: 'AI',
    );
  }

  /// 消息图片：单图保持整宽展示；多图为横向小图排，点击查看大图
  Widget _buildMessageImages(List<String> paths) {
    if (paths.length == 1) {
      return GestureDetector(
        onTap: () => showChatImageViewer(context, paths, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Image.file(
            File(paths.first),
            fit: BoxFit.cover,
            cacheWidth: 640,
            width: double.infinity,
          ),
        ),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < paths.length; i++)
          GestureDetector(
            onTap: () => showChatImageViewer(context, paths, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Image.file(
                File(paths[i]),
                fit: BoxFit.cover,
                cacheWidth: 320,
                width: 100,
                height: 100,
              ),
            ),
          ),
      ],
    );
  }

  void _showActionBar(BuildContext context, [Offset? position]) {
    final l10n = AppLocalizations.of(context);
    final isUser = widget.message.isUser;
    final scheme = Theme.of(context).colorScheme;

    final actions = <MessageActionItem>[
      MessageActionItem(
        icon: Icons.copy_outlined,
        label: l10n.get('copyText'),
        color: scheme.primary,
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.get('copied')),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
      if (widget.showCheckbox && widget.onSelectToHere != null)
        MessageActionItem(
          icon: Icons.playlist_add_check_rounded,
          label: l10n.get('selectToHere'),
          color: scheme.primary,
          onTap: () => widget.onSelectToHere?.call(),
        )
      else if (widget.onMultiSelect != null)
        MessageActionItem(
          icon: Icons.checklist_rounded,
          label: l10n.get('multiSelect'),
          color: scheme.primary,
          onTap: () => widget.onMultiSelect?.call(),
        ),
      if (!isUser && widget.onRegenerate != null) ...[
        MessageActionItem(
          icon: Icons.thumb_up_alt_outlined,
          label: l10n.get('like'),
          color: scheme.primary,
          onTap: () => _analyzeFeedback(context, isLike: true),
        ),
        MessageActionItem(
          icon: Icons.thumb_down_alt_outlined,
          label: l10n.get('dislike'),
          color: scheme.tertiary,
          onTap: () => _analyzeFeedback(context, isLike: false),
        ),
        MessageActionItem(
          icon: Icons.refresh_rounded,
          label: l10n.get('regenerate'),
          color: scheme.primary,
          onTap: () => widget.onRegenerate?.call(),
        ),
      ],
      if (!isUser && widget.onRewrite != null)
        MessageActionItem(
          icon: Icons.edit_note_rounded,
          label: l10n.get('rewrite'),
          color: scheme.primary,
          onTap: () => widget.onRewrite?.call(),
        ),
      if (!isUser && widget.message.toolLogs != null)
        MessageActionItem(
          icon: Icons.code_rounded,
          label: l10n.get('viewToolCalls'),
          color: scheme.primary,
          onTap: () => _showToolLogs(context),
        ),
      MessageActionItem(
        icon: Icons.delete_outline_rounded,
        label: l10n.get('deleteMessage'),
        color: scheme.error,
        onTap: () => widget.onDelete(),
      ),
    ];

    if (position != null) {
      MessageActionSheet.showAt(context, position, actions);
    } else {
      // 没有位置信息（如桌面端右键没传位置），在屏幕中上方弹
      MessageActionSheet.showAt(
        context,
        Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 3,
        ),
        actions,
      );
    }
  }

  /// 点赞/踩反馈：调用 Flash Thinking High 分析最近 5 轮对话，
  /// 把分析结论写入 base_memories（event 类型），后续会自动注入到 system prompt
  Future<void> _analyzeFeedback(
    BuildContext context, {
    required bool isLike,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final chatState = container.read(chatProvider);
    final agent = container.read(agentProvider).currentAgent;
    final auth = container.read(authProvider);

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    if (agent == null || agent.id.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('noAgentCurrent')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (auth.apiKey == null || auth.apiKey!.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('pleaseLoginFirst')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 收集最近 5 轮（10 条）消息
    final recent = chatState.messages.length > 10
        ? chatState.messages.sublist(chatState.messages.length - 10)
        : chatState.messages;
    if (recent.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.get('noConversationToAnalyze')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isLike
              ? l10n.get('analyzingPreferences')
              : l10n.get('analyzingDislikes'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    final err = await FeedbackAnalysisService.analyzeAndStore(
      isLike: isLike,
      recentMessages: recent,
      agentId: agent.id,
      apiKey: auth.apiKey!,
    );

    if (!mounted) return;
    if (err == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isLike
                ? l10n.get('preferenceRecorded')
                : l10n.get('dislikeRecorded'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _showToolLogs(BuildContext context) {
    if (widget.message.toolLogs == null) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.get('toolCalls'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message.promptTokens != null ||
                  widget.message.completionTokens != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.get('tokenUsage'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (widget.message.promptTokens != null)
                        Text(
                          '${l10n.get("promptTokens")}: ${widget.message.promptTokens}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (widget.message.completionTokens != null)
                        Text(
                          '${l10n.get("completionTokens")}: ${widget.message.completionTokens}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (widget.message.promptTokens != null &&
                          widget.message.completionTokens != null)
                        Text(
                          '${l10n.get("totalTokens")}: ${widget.message.promptTokens! + widget.message.completionTokens!}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.message.toolLogs!.length,
                  itemBuilder: (_, i) {
                    final log = widget.message.toolLogs![i];
                    final formattedArgs = const JsonEncoder.withIndent(
                      '  ',
                    ).convert(log.arguments);
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.get('tool')}: ${log.toolName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Args:',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 2, bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                formattedArgs,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            Text(
                              'Result: ${log.result}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('close')),
          ),
        ],
      ),
    );
  }
}
