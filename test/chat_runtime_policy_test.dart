import 'package:aichat/services/chat_runtime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('标准聊天策略固定为 Flash、非思考和温度 1.3', () {
    const policy = ChatRuntimePolicy.standard;

    expect(policy.model, 'deepseek-v4-flash');
    expect(policy.thinkingMode, isFalse);
    expect(policy.temperature, 1.3);
  });

  test('高质量任务策略启用思考且不传温度', () {
    const policy = ChatRuntimePolicy.qualityTask;

    expect(policy.thinkingMode, isTrue);
    expect(policy.temperature, isNull);
  });
}
