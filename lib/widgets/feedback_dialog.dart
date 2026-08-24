import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/feedback_service.dart';

/// 反馈对话框
///
/// 通过 [FeedbackDialog.show] 弹出，用户选择分类、填写内容 + 联系方式后提交。
class FeedbackDialog extends ConsumerStatefulWidget {
  const FeedbackDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FeedbackDialog(),
    );
  }

  @override
  ConsumerState<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<FeedbackDialog> {
  FeedbackCategory _category = FeedbackCategory.feature;
  final _contentCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    final l10n = AppLocalizations.of(context);

    if (content.length < 5) {
      _toast(l10n.get('feedbackContentMinLength'));
      return;
    }
    if (contact.isEmpty) {
      _toast(l10n.get('feedbackContactRequired'));
      return;
    }

    setState(() => _submitting = true);
    final err = await FeedbackService.submit(
      auth: ref.read(authProvider),
      category: _category,
      content: content,
      contact: contact,
      loginRequiredMessage: l10n.get('feedbackLoginRequired'),
      submitFailedMessage: l10n.get('feedbackSubmitFailed'),
      networkErrorMessage: (error) =>
          l10n.getP('feedbackNetworkErrorWithDetail', {'error': error}),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (err == null) {
      Navigator.pop(context);
      _toast(l10n.get('feedbackSubmitted'));
    } else {
      _toast(err);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.feedback_outlined, color: scheme.primary, size: 24),
          const SizedBox(width: 8),
          Text(
            l10n.get('feedback'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.get('feedbackCategory'),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: FeedbackCategory.values.map((c) {
                  final selected = c == _category;
                  return ChoiceChip(
                    label: Text(
                      _categoryLabel(c, l10n),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = c),
                    selectedColor: scheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 1.2 : 0.5,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.get('feedbackContent'),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _contentCtrl,
                maxLines: 5,
                minLines: 3,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: l10n.get('feedbackContentHint'),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.get('feedbackContact'),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _contactCtrl,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: l10n.get('feedbackContactHint'),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(l10n.get('cancel')),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 16),
          label: Text(
            _submitting ? l10n.get('submitting') : l10n.get('submit'),
          ),
        ),
      ],
    );
  }

  String _categoryLabel(FeedbackCategory category, AppLocalizations l10n) {
    switch (category) {
      case FeedbackCategory.feature:
        return l10n.get('feedbackCategoryFeature');
      case FeedbackCategory.featureTweak:
        return l10n.get('feedbackCategoryFeatureTweak');
      case FeedbackCategory.bug:
        return l10n.get('feedbackCategoryBug');
      case FeedbackCategory.ui:
        return l10n.get('feedbackCategoryUi');
      case FeedbackCategory.pricing:
        return l10n.get('feedbackCategoryPricing');
      case FeedbackCategory.other:
        return l10n.get('feedbackCategoryOther');
    }
  }
}
