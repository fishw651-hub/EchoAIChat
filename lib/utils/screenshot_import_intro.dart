import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// 截图导入首次引导：第一次点击"从聊天/截图导入"时弹窗说明玩法，
/// 点"选择截图"返回 true 继续选图流程；取消则下次点击仍会提示。
class ScreenshotImportIntro {
  static const _prefKey = 'screenshot_import_intro_shown';

  /// 已展示过直接返回 true；未展示则弹窗，返回用户是否选择继续。
  static Future<bool> ensureShown(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return true;
    if (!context.mounted) return false;

    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.document_scanner_outlined,
          size: 40,
          color: scheme.primary,
        ),
        title: Text(l10n.get('screenshotImportIntroTitle')),
        content: Text(
          l10n.get('screenshotImportIntroBody'),
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.get('screenshotImportIntroAction')),
          ),
        ],
      ),
    );

    if (proceed == true) {
      // 仅在用户真正进入选图后标记：取消则保留下次引导机会
      await prefs.setBool(_prefKey, true);
      return true;
    }
    return false;
  }
}
