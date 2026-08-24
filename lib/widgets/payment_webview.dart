import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 支付页面 — 打开外部浏览器支付，用户支付后手动返回
class PaymentWebView extends StatefulWidget {
  final String url;
  final String? jwtToken;
  const PaymentWebView({required this.url, this.jwtToken, super.key});

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final String _normalizedUrl;

  @override
  void initState() {
    super.initState();
    _normalizedUrl = widget.url.trim();
    _openBrowser();
  }

  Future<void> _openBrowser() async {
    final uri = Uri.tryParse(_normalizedUrl);
    if (uri == null || !uri.hasScheme) {
      if (mounted) _showError('无效的支付链接');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _showError('无法打开浏览器');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('支付'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_browser, size: 56, color: scheme.primary),
              const SizedBox(height: 20),
              const Text(
                '请在浏览器中完成支付',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                '支付完成后请点击下方按钮返回应用',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('已完成支付', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('支付遇到问题'),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(_normalizedUrl);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新打开浏览器'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
