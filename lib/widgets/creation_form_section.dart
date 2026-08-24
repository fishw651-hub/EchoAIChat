import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CreationFormSection extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const CreationFormSection({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.only(top: AppTheme.space6),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (description != null) ...[
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppTheme.space3),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppTheme.space3),
          child,
        ],
      ),
    );
  }
}

class CreationQuickActions extends StatelessWidget {
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimaryPressed;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback? onSecondaryPressed;

  const CreationQuickActions({
    super.key,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimaryPressed,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final primary = FilledButton.tonalIcon(
          key: const Key('creation-primary-quick-action'),
          onPressed: onPrimaryPressed,
          icon: Icon(primaryIcon),
          label: Text(primaryLabel, textAlign: TextAlign.center),
        );
        final secondary = OutlinedButton.icon(
          key: const Key('creation-secondary-quick-action'),
          onPressed: onSecondaryPressed,
          icon: Icon(secondaryIcon),
          label: Text(secondaryLabel, textAlign: TextAlign.center),
        );

        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: AppTheme.space2),
              secondary,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: primary),
            const SizedBox(width: AppTheme.space2),
            Expanded(child: secondary),
          ],
        );
      },
    );
  }
}

class CreationSubmitActions extends StatelessWidget {
  final String primaryLabel;
  final String uploadLabel;
  final VoidCallback? onPrimaryPressed;
  final VoidCallback? onUploadPressed;
  final bool loading;
  final String? disabledUploadReason;

  const CreationSubmitActions({
    super.key,
    required this.primaryLabel,
    required this.uploadLabel,
    required this.onPrimaryPressed,
    required this.onUploadPressed,
    this.loading = false,
    this.disabledUploadReason,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const Key('creation-primary-submit'),
          onPressed: loading ? null : onPrimaryPressed,
          child: loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(primaryLabel),
        ),
        const SizedBox(height: AppTheme.space3),
        OutlinedButton.icon(
          key: const Key('creation-upload-submit'),
          onPressed: loading ? null : onUploadPressed,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(uploadLabel),
        ),
        if (disabledUploadReason != null) ...[
          const SizedBox(height: AppTheme.space2),
          Text(
            disabledUploadReason!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }
}
