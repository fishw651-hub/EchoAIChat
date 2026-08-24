import 'dart:convert';
import 'model_list_service.dart';

import 'api_service.dart';

enum PromptWriterTarget { agent, group }

class PromptDraft {
  final String name;
  final String gender;
  final String description;
  final String persona;
  final String openingLine;

  const PromptDraft({
    this.name = '',
    this.gender = '',
    this.description = '',
    this.persona = '',
    this.openingLine = '',
  });

  bool get isEmpty =>
      name.trim().isEmpty &&
      gender.trim().isEmpty &&
      description.trim().isEmpty &&
      persona.trim().isEmpty &&
      openingLine.trim().isEmpty;

  factory PromptDraft.fromJsonMap(Map<String, dynamic> json) {
    String read(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      return '';
    }

    return PromptDraft(
      name: read(['name', 'group_name', 'title']),
      gender: read(['gender', 'sex']),
      description: read(['description', 'intro', 'summary']),
      persona: read(['persona', 'prompt', 'group_persona', 'world_setting']),
      openingLine: read(['opening_line', 'openingLine', 'greeting']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gender': gender,
      'description': description,
      'persona': persona,
      'opening_line': openingLine,
    };
  }
}

class PromptWriterQuestion {
  final String question;
  final List<String> options;

  const PromptWriterQuestion({required this.question, this.options = const []});
}

typedef PromptWriterAskUser =
    Future<String> Function(PromptWriterQuestion question);

typedef PromptWriterReasoning = void Function(String reasoning);

class AiPromptWriterService {
  static PromptDraft? parseDraftFromContent(String? content) {
    if (content == null || content.trim().isEmpty) return null;
    final parsed = _parseJsonObject(content);
    if (parsed == null) return null;
    final draft = PromptDraft.fromJsonMap(parsed);
    return draft.isEmpty ? null : draft;
  }

  Future<PromptDraft> generate({
    required PromptWriterTarget target,
    required String apiKey,
    required String baseUrl,
    required String userBrief,
    required PromptDraft currentDraft,
    required PromptWriterAskUser askUser,
    PromptWriterReasoning? onReasoning,
    double temperature = 1.0,
  }) async {
    final apiService = ApiService.fromConfig(
      model: await ModelListService.getSelectedModel(),
      apiKey: apiKey,
      baseUrl: baseUrl,
      thinkingMode: true,
      temperature: temperature,
    );

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(target)},
      {
        'role': 'user',
        'content': _buildUserPrompt(
          target: target,
          userBrief: userBrief,
          currentDraft: currentDraft,
        ),
      },
    ];

    var toolChoice = 'required';
    for (var round = 0; round < 6; round++) {
      final response = await apiService.chatCompletion(
        messages: messages,
        tools: _toolDefinitions(target),
        toolChoice: toolChoice,
      );

      final reasoning = ApiService.parseReasoningContent(response);
      if (reasoning != null) {
        onReasoning?.call(reasoning);
      }

      final finishReason = ApiService.parseFinishReason(response);
      if (finishReason != 'tool_calls') {
        final draft = parseDraftFromContent(ApiService.parseContent(response));
        if (draft != null) return draft;
        throw ApiException('AI 没有返回可用的提示词草稿');
      }

      final assistantChoice = response['choices']?[0]?['message'];
      if (assistantChoice is Map<String, dynamic>) {
        messages.add(assistantChoice);
      }

      final toolCalls = ApiService.parseToolCalls(response);
      if (toolCalls.isEmpty) {
        throw ApiException('AI 请求调用工具，但没有提供工具参数');
      }

      for (final toolCall in toolCalls) {
        final name = toolCall['name'] as String? ?? '';
        final arguments =
            (toolCall['arguments'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final toolCallId = toolCall['id'] as String? ?? '';

        final toolResult = await _handleToolCall(
          toolName: name,
          arguments: arguments,
          askUser: askUser,
        );

        if (toolResult.draft != null) {
          return toolResult.draft!;
        }

        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': toolResult.message,
        });
      }

      toolChoice = 'auto';
    }

    throw ApiException('AI 帮写超过最大工具轮次，请再试一次');
  }

  static Future<_PromptToolResult> _handleToolCall({
    required String toolName,
    required Map<String, dynamic> arguments,
    required PromptWriterAskUser askUser,
  }) async {
    switch (toolName) {
      case 'ask_user':
        final question = arguments['question'] as String? ?? '你希望补充什么细节？';
        final rawOptions = arguments['options'];
        final options = rawOptions is List
            ? rawOptions
                  .map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : <String>[];
        final answer = await askUser(
          PromptWriterQuestion(question: question, options: options),
        );
        return _PromptToolResult.messageOnly('用户回答：$answer');
      case 'apply_prompt':
        final draft = PromptDraft.fromJsonMap(arguments);
        if (draft.isEmpty) {
          return _PromptToolResult.messageOnly('错误：apply_prompt 参数为空');
        }
        return _PromptToolResult(draft: draft, message: '已生成草稿');
      default:
        return _PromptToolResult.messageOnly('未知工具：$toolName');
    }
  }

  static String _systemPrompt(PromptWriterTarget target) {
    final targetName = target == PromptWriterTarget.agent ? '智能体' : '群聊';
    final requiredFields = target == PromptWriterTarget.agent
        ? 'name, gender, description, persona, opening_line'
        : 'name, description, persona';
    return '''
你是一个擅长创作 AI 聊天角色和群聊设定的提示词设计师。
你正在帮助用户创建$targetName。

工作规则：
1. 先理解用户输入，如果关键信息不足，可以调用 ask_user 询问用户。优先给 2-4 个可选项。
2. 信息足够后，必须调用 apply_prompt 输出最终草稿。
3. 最终草稿字段必须包含：$requiredFields。
4. persona 要可直接作为系统提示词使用，具体、稳定、能约束说话风格和行为边界。
5. 不要生成违法、仇恨或现实伤害内容。
6. 输出语言跟随用户输入；用户用中文就写中文。
''';
  }

  static String _buildUserPrompt({
    required PromptWriterTarget target,
    required String userBrief,
    required PromptDraft currentDraft,
  }) {
    final targetName = target == PromptWriterTarget.agent ? '智能体' : '群聊';
    return '''
请根据用户的详细内容，为$targetName写一份可用草稿。

用户详细内容：
$userBrief

当前表单已有内容：
${const JsonEncoder.withIndent('  ').convert(currentDraft.toJson())}

如果信息不足，请用 ask_user 问一个最关键的问题。
如果信息足够，请直接调用 apply_prompt。
''';
  }

  static List<Map<String, dynamic>> _toolDefinitions(
    PromptWriterTarget target,
  ) {
    final properties = <String, dynamic>{
      'name': {'type': 'string', 'description': '姓名、角色名或群聊名'},
      'description': {'type': 'string', 'description': '简短简介'},
      'persona': {'type': 'string', 'description': '完整人设提示词或群聊提示词'},
    };
    final required = ['name', 'description', 'persona'];

    if (target == PromptWriterTarget.agent) {
      properties['gender'] = {'type': 'string', 'description': '性别或性别表达'};
      properties['opening_line'] = {'type': 'string', 'description': '开场白'};
      required
        ..add('gender')
        ..add('opening_line');
    }

    return [
      {
        'type': 'function',
        'function': {
          'name': 'ask_user',
          'description': '当缺少关键设定时，询问用户一个问题。界面会弹出选择框。',
          'parameters': {
            'type': 'object',
            'properties': {
              'question': {'type': 'string', 'description': '要问用户的问题'},
              'options': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': '给用户选择的 2-4 个选项',
              },
            },
            'required': ['question'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'apply_prompt',
          'description': '提交最终可回填到创建表单的草稿。',
          'parameters': {
            'type': 'object',
            'properties': properties,
            'required': required,
          },
        },
      },
    ];
  }

  static Map<String, dynamic>? _parseJsonObject(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    try {
      final match = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content);
      if (match != null) {
        final decoded = jsonDecode(match.group(1)!.trim());
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    try {
      final start = content.indexOf('{');
      final end = content.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final decoded = jsonDecode(content.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    return null;
  }
}

class _PromptToolResult {
  final String message;
  final PromptDraft? draft;

  const _PromptToolResult({required this.message, this.draft});

  const _PromptToolResult.messageOnly(String message) : this(message: message);
}
