import 'package:aichat/services/ai_prompt_writer_service.dart';
import 'package:aichat/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PromptDraft parses agent fields from JSON content', () {
    final draft = AiPromptWriterService.parseDraftFromContent('''
{
  "name": "林浅",
  "gender": "女",
  "description": "温柔但有边界感的同伴",
  "persona": "你是林浅，会自然表达关心。",
  "opening_line": "今天想从哪里开始聊？"
}
''');

    expect(draft, isNotNull);
    expect(draft!.name, '林浅');
    expect(draft.gender, '女');
    expect(draft.description, contains('边界感'));
    expect(draft.persona, contains('自然表达'));
    expect(draft.openingLine, contains('开始聊'));
  });

  test('parseReasoningContent reads thinking text from response message', () {
    final reasoning = ApiService.parseReasoningContent({
      'choices': [
        {
          'message': {
            'reasoning_content': '先判断用户想要的角色类型。',
            'content': '',
          },
        },
      ],
    });

    expect(reasoning, '先判断用户想要的角色类型。');
  });
}
