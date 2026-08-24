import 'package:flutter/material.dart';

import '../services/ai_prompt_writer_service.dart';

Future<PromptDraft?> showAiPromptWriterDialog({
  required BuildContext context,
  required PromptWriterTarget target,
  required String apiKey,
  required String baseUrl,
  required double temperature,
  required PromptDraft currentDraft,
}) async {
  final brief = await _askForBrief(context, target);
  if (brief == null || brief.trim().isEmpty || !context.mounted) {
    return null;
  }

  return showDialog<PromptDraft>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AiPromptWriterProgressDialog(
      target: target,
      apiKey: apiKey,
      baseUrl: baseUrl,
      temperature: temperature,
      userBrief: brief.trim(),
      currentDraft: currentDraft,
    ),
  );
}

Future<String?> _askForBrief(
  BuildContext context,
  PromptWriterTarget target,
) {
  final controller = TextEditingController();
  final hint = target == PromptWriterTarget.agent
      ? '例如：我想要一个温柔但有主见的都市女性角色，像朋友一样陪我聊天，有一点俏皮。'
      : '例如：我想要一个现代奇幻调查小队群聊，成员之间会互相吐槽，也会推动剧情。';

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('AI帮写提示词'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        decoration: InputDecoration(
          hintText: hint,
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, controller.text),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('开始生成'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _AiPromptWriterProgressDialog extends StatefulWidget {
  final PromptWriterTarget target;
  final String apiKey;
  final String baseUrl;
  final double temperature;
  final String userBrief;
  final PromptDraft currentDraft;

  const _AiPromptWriterProgressDialog({
    required this.target,
    required this.apiKey,
    required this.baseUrl,
    required this.temperature,
    required this.userBrief,
    required this.currentDraft,
  });

  @override
  State<_AiPromptWriterProgressDialog> createState() =>
      _AiPromptWriterProgressDialogState();
}

class _AiPromptWriterProgressDialogState
    extends State<_AiPromptWriterProgressDialog> {
  final _reasoning = <String>[];
  PromptDraft? _draft;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final draft = await AiPromptWriterService().generate(
        target: widget.target,
        apiKey: widget.apiKey,
        baseUrl: widget.baseUrl,
        temperature: widget.temperature,
        userBrief: widget.userBrief,
        currentDraft: widget.currentDraft,
        askUser: _askUser,
        onReasoning: (reasoning) {
          if (!mounted) return;
          setState(() => _reasoning.add(reasoning));
        },
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<String> _askUser(PromptWriterQuestion question) async {
    if (!mounted) return '';
    final answer = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromptWriterQuestionDialog(question: question),
    );
    return answer?.trim().isNotEmpty == true ? answer!.trim() : '按你的推荐继续';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.9;

    return AlertDialog(
      title: const Text('AI帮写提示词'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth.clamp(320, 560).toDouble(),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '正在思考和调用工具...',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              if (_reasoning.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '思考过程',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _reasoning.join('\n\n'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              if (_draft != null) ...[
                const SizedBox(height: 12),
                _DraftPreview(draft: _draft!, target: widget.target),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed:
              _draft == null ? null : () => Navigator.pop(context, _draft),
          icon: const Icon(Icons.check),
          label: const Text('应用到表单'),
        ),
      ],
    );
  }
}

class _PromptWriterQuestionDialog extends StatefulWidget {
  final PromptWriterQuestion question;

  const _PromptWriterQuestionDialog({required this.question});

  @override
  State<_PromptWriterQuestionDialog> createState() =>
      _PromptWriterQuestionDialogState();
}

class _PromptWriterQuestionDialogState
    extends State<_PromptWriterQuestionDialog> {
  late String? _selected =
      widget.question.options.isNotEmpty ? widget.question.options.first : null;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 需要确认'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.question.question),
            const SizedBox(height: 12),
            for (final option in widget.question.options)
              RadioListTile<String>(
                value: option,
                groupValue: _selected,
                contentPadding: EdgeInsets.zero,
                title: Text(option),
                onChanged: (value) => setState(() => _selected = value),
              ),
            TextField(
              controller: _customCtrl,
              decoration: const InputDecoration(
                labelText: '其他想法',
                hintText: '也可以自己输入',
              ),
              onChanged: (value) {
                if (value.trim().isNotEmpty) {
                  setState(() => _selected = null);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            final custom = _customCtrl.text.trim();
            Navigator.pop(context, custom.isNotEmpty ? custom : _selected);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _DraftPreview extends StatelessWidget {
  final PromptDraft draft;
  final PromptWriterTarget target;

  const _DraftPreview({
    required this.draft,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final fields = <String, String>{
      if (target == PromptWriterTarget.agent) '姓名': draft.name,
      if (target == PromptWriterTarget.group) '群名': draft.name,
      if (target == PromptWriterTarget.agent) '性别': draft.gender,
      '简介': draft.description,
      target == PromptWriterTarget.agent ? '人设提示词' : '群聊提示词': draft.persona,
      if (target == PromptWriterTarget.agent) '开场白': draft.openingLine,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '生成结果',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final entry in fields.entries)
          if (entry.value.trim().isNotEmpty) ...[
            Text(
              entry.key,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            SelectableText(
              entry.value,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}
