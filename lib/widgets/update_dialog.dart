import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';

/// 显示更新提示弹窗（只处理非强制更新；强制更新由 main.dart 的
/// _AppShell 全屏拦截，不会走到这里）
void showAppUpdateDialog(BuildContext context) {
  final update = UpdateService.availableUpdate;
  if (update == null) return;

  final scheme = Theme.of(context).colorScheme;
  final sizeLabel = update.fileSizeLabel;

  showDialog(
    context: context,
    barrierDismissible: !update.isForce,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        update.isForce ? Icons.warning_amber_rounded : Icons.system_update,
        color: update.isForce ? scheme.error : scheme.primary,
        size: 32,
      ),
      title: Text(
        update.isForce
            ? AppLocalizations.of(ctx).get('forceUpdateTitle')
            : AppLocalizations.of(ctx).get('updateOptional'),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(
              ctx,
            ).getP('versionLabel', {'version': update.version}),
            style: TextStyle(
              fontSize: 14,
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sizeLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(
                ctx,
              ).getP('updateSize', {'size': sizeLabel}),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (update.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(ctx).get('releaseNotes'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  update.releaseNotes,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  AppLocalizations.of(ctx).get('updateDownloadHint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (!update.isForce)
          TextButton(
            onPressed: () {
              UpdateService.skipUpdate();
              Navigator.of(ctx).pop();
            },
            child: Text(AppLocalizations.of(ctx).get('skipThisVersion')),
          ),
        if (!update.isForce)
          TextButton(
            onPressed: () {
              UpdateService.dismiss();
              Navigator.of(ctx).pop();
            },
            child: Text(AppLocalizations.of(ctx).get('later')),
          ),
        FilledButton.icon(
          onPressed: () async {
            Navigator.of(ctx).pop();
            final ok = await UpdateService.downloadViaBrowser();
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).get('cannotOpenBrowser'),
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(AppLocalizations.of(ctx).get('updateNow')),
        ),
      ],
    ),
  );
}
