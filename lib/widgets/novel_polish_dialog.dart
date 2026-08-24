import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/server_config.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_runtime_policy.dart';
import '../services/novel_service.dart';

/// AI 润色/小说生成弹窗：对多选选中的聊天文本（[text]）按所选风格与字数
/// 生成一段新文本，可复制或保存到小说历史（novel_generations 表）。
/// [readApiKey] 由调用方注入，点击"生成"时现取（避免把 provider 耦合进来）。
Future<void> showNovelPolishDialog(
  BuildContext context, {
  required String text,
  required String Function() readApiKey,
}) async {
  final l10n = AppLocalizations.of(context);
  String style = NovelService.defaultStyles.first;
  int wordCount = NovelService.defaultWordCount;
  final customCtrl = TextEditingController();
  String? result;
  bool loading = false;

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          l10n.get('aiNovelGeneration'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.get('selectedMessagesLabel'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(text, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.get('novelStyle'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: NovelService.defaultStyles
                      .map(
                        (s) => ChoiceChip(
                          label: Text(
                            s,
                            style: const TextStyle(fontSize: 13),
                          ),
                          selected: style == s,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setDialogState(() => style = s),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      l10n.get('wordCount'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l10n.getP('wordCountValue', {'n': '$wordCount'}),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: wordCount.clamp(200, 3000).toDouble(),
                  min: 200,
                  max: 3000,
                  divisions: 28,
                  onChanged: (v) =>
                      setDialogState(() => wordCount = v.round()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.get('customPromptOptional'),
                    hintText: l10n.get('customPromptHint'),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                if (result != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        l10n.get('generationResult'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$style · ${l10n.getP('wordCountValue', {'n': '$wordCount'})}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        result!,
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                  ),
                ],
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (result != null) ...[
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result!));
                Navigator.pop(ctx);
              },
              child: Text(l10n.get('copyResult')),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await NovelService.save(
                  style: style,
                  wordCount: wordCount,
                  prompt: text,
                  result: result!,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (context.mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.get('saved')),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
              child: Text(l10n.get('save')),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get(loading ? 'cancel' : 'close')),
          ),
          if (!loading)
            FilledButton(
              onPressed: () async {
                setDialogState(() => loading = true);
                try {
                  final r = await NovelService.generate(
                    content: text,
                    style: style,
                    wordCount: wordCount,
                    customPrompt: customCtrl.text.trim(),
                    baseUrl: ServerConfig.baseUrl,
                    apiKey: readApiKey(),
                    model: ChatRuntimePolicy.standard.model,
                  );
                  setDialogState(() {
                    result = r;
                    loading = false;
                  });
                } catch (e) {
                  setDialogState(() {
                    result = l10n.getP('generationFailed', {'error': '$e'});
                    loading = false;
                  });
                }
              },
              child: Text(l10n.get('generate')),
            ),
        ],
      ),
    ),
  );
}
