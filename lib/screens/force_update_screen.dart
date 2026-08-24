import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/update_service.dart';

/// 强制更新全屏拦截页
///
/// 不可返回、不可关闭、不可跳过。
/// 用户必须点击"立即更新"跳转浏览器下载安装，
/// 安装新版本后 app 会被系统重启，本页面自然失效。
/// 如果用户在浏览器下载后未安装就返回 app，本页面仍然拦截。
class ForceUpdateScreen extends StatefulWidget {
  final UpdateInfo update;

  const ForceUpdateScreen({super.key, required this.update});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _launching = false;

  Future<void> _onUpdateTap() async {
    if (_launching) return;
    setState(() => _launching = true);
    try {
      final ok = await UpdateService.downloadViaBrowser();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).get('cannotOpenBrowser'),
            ),
          ),
        );
      }
      // 不论打开成功与否，强制更新状态保持不变：
      // - 成功：用户在浏览器下载，返回 app 仍被拦截，直到安装新版本
      // - 失败：用户可再次点击重试
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final update = widget.update;
    final sizeLabel = update.fileSizeLabel;

    // PopScope 拦截 Android 系统返回键，禁止退出
    return PopScope(
      canPop: false,
      child: Scaffold(
        // 不显示 AppBar，无返回按钮
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                scheme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 警告图标
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.system_update_alt_rounded,
                        size: 48,
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.get('forceUpdateTitle'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.get('forceUpdateSubtitle'),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // 版本信息卡片
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                l10n.get('latestVersion'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'v${update.version}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          if (sizeLabel.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  l10n.get('packageSize'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  sizeLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 更新说明
                    if (update.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.get('releaseNotes'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 220),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            update.releaseNotes,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.55,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // 唯一按钮：立即更新
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _launching ? null : _onUpdateTap,
                        icon: _launching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          _launching
                              ? l10n.get('openingBrowser')
                              : l10n.get('updateNow'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 操作提示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline,
                            size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '点击更新将跳转浏览器下载，下载完成后请点击通知安装。',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
