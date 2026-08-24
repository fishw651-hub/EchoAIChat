import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/account_guard_service.dart';

/// 本地账号切换封禁拦截页 — 封禁期间替代主界面，无法使用任何功能
class AccountBanScreen extends StatelessWidget {
  final BanStatus status;

  const AccountBanScreen({super.key, required this.status});

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_bad_outlined, size: 72, color: scheme.error),
              const SizedBox(height: 24),
              Text(
                l10n.get('accountBanTitle'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.getP('accountBanMessage', {
                  'days': '${status.remainingDays}',
                }),
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              if (status.banUntil != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.getP('accountBanUntil', {
                    'date': _formatDate(status.banUntil!),
                  }),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
