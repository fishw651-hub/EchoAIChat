import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/agent.dart';
import '../services/agent_share_service.dart';

/// 分享智能体对话框：创建分享码 → 展示 6 位码 + 倒计时 + 复制
class AgentShareDialog extends StatefulWidget {
  final Agent agent;
  final String? jwt;

  const AgentShareDialog({super.key, required this.agent, this.jwt});

  @override
  State<AgentShareDialog> createState() => _AgentShareDialogState();
}

class _AgentShareDialogState extends State<AgentShareDialog> {
  AgentShareResult? _result;
  String? _error;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final result = await AgentShareService(
        token: widget.jwt,
      ).createShare(widget.agent);
      if (!mounted) return;
      setState(() => _result = result);
      _startTicker(result.expiresAtParsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _startTicker(DateTime? expiresAt) {
    _ticker?.cancel();
    if (expiresAt == null) return;
    void tick() {
      final left = expiresAt.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left.isNegative) _ticker?.cancel();
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String get _countdownText {
    final total = _remaining.inSeconds;
    final mm = (total ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _copy(AppLocalizations l10n) async {
    final code = _result?.code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.get('shareCodeCopied')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.get('shareAgent')),
      content: SizedBox(
        width: 320,
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${l10n.get('shareCreateFailed')}: $_error',
                    style: TextStyle(color: scheme.error),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _create,
                    child: Text(l10n.get('retry')),
                  ),
                ],
              )
            : _result == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    _result!.code,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.get('shareCodeValidHint'),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (_result!.expiresAtParsed != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _remaining == Duration.zero
                          ? l10n.get('shareCodeExpired')
                          : '${l10n.get('remainingTime')} $_countdownText',
                      style: TextStyle(
                        fontSize: 13,
                        color: _remaining == Duration.zero
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _copy(l10n),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l10n.get('copy')),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.get('cancel')),
        ),
      ],
    );
  }
}
