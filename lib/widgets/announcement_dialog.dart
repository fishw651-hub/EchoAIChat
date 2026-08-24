import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/announcement_service.dart';

/// 公告弹窗的关闭方式
enum AnnouncementDismiss { close, dontShowToday }

/// 公告弹窗：标题 + 可滚动 Markdown 内容区 + 频率相关按钮区。
///
/// 按钮规则（记录逻辑由 [AnnouncementService.recordDismiss] 落实）：
/// - once：两个按钮都在，任一按钮关闭都会写 once 记录（内容更新前不再弹）
/// - daily：「关闭」不写记录（下次启动还弹）；「今天不再提示」写 daily 记录
/// - always：只显示「关闭」，不写任何记录，下次进入首页仍弹
class AnnouncementDialog extends StatelessWidget {
  const AnnouncementDialog({super.key, required this.announcement});

  final Announcement announcement;

  /// 弹出单条公告；返回用户选择的关闭方式（系统返回键等异常路径返回 null，
  /// 调用方按「关闭」处理即可）
  static Future<AnnouncementDismiss?> show(
    BuildContext context,
    Announcement announcement,
  ) {
    // barrierDismissible: false —— 强制用户点按钮，避免点空白处绕过频率记录
    return showDialog<AnnouncementDismiss>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(announcement: announcement),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Semantics(
      container: true,
      label: l10n.get('announcement'),
      child: AlertDialog(
        title: Text(announcement.title),
        content: ConstrainedBox(
          // 内容区限高 55% 屏高，超出滚动，避免长公告撑满全屏
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: announcement.content,
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri == null) return;
                unawaited(
                  launchUrl(uri, mode: LaunchMode.externalApplication),
                );
              },
              sizedImageBuilder: (config) =>
                  _buildImage(context, scheme, config),
            ),
          ),
        ),
        actions: [
          // always 公告没有"跳过"语义，只给「关闭」
          if (announcement.frequency != AnnouncementFrequency.always)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, AnnouncementDismiss.dontShowToday),
              child: Text(l10n.get('dontShowAgainToday')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, AnnouncementDismiss.close),
            child: Text(l10n.get('close')),
          ),
        ],
      ),
    );
  }

  /// Markdown 图片：网络图宽度撑满内容区自适应，加载失败给占位块
  Widget _buildImage(
    BuildContext context,
    ColorScheme scheme,
    MarkdownImageConfig config,
  ) {
    if (config.uri.scheme != 'http' && config.uri.scheme != 'https') {
      return _imagePlaceholder(scheme, alt: config.alt);
    }
    return Image.network(
      config.uri.toString(),
      width: config.width ?? double.infinity,
      height: config.height,
      fit: BoxFit.fitWidth,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _imagePlaceholder(scheme),
      errorBuilder: (context, error, stackTrace) =>
          _imagePlaceholder(scheme, alt: config.alt),
    );
  }

  Widget _imagePlaceholder(ColorScheme scheme, {String? alt}) {
    return Container(
      height: 96,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 18, color: scheme.outline),
          if (alt != null && alt.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                alt,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.outline, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
