import 'package:aichat/models/agent.dart';
import 'package:aichat/models/base_memory.dart';
import 'package:aichat/models/long_term_memory.dart';
import 'package:aichat/models/profile_entry.dart';
import 'package:aichat/services/chat_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void expectPrivateToolPolicy(String prompt) {
  expect(prompt, contains('普通回复使用 chat 工具'));
  expect(prompt, contains('未来提醒时调用 plan 工具'));
  expect(prompt, contains('不需要未来提醒时不得调用 plan'));
  expect(prompt, contains('记忆更新由独立的记忆服务负责'));
  expect(prompt, isNot(contains('不要使用任何工具调用')));
}

void main() {
  ChatPromptBuilder builder({
    RealInfoReader? readRealInfo,
    ProfileEntriesReader? readProfileEntries,
    Duration memoryTimeout = const Duration(seconds: 2),
  }) {
    return ChatPromptBuilder(
      memoryTimeout: memoryTimeout,
      readRealInfo: readRealInfo ?? () async => <String, String>{},
      readProfileEntries: readProfileEntries ?? () async => <ProfileEntry>[],
      log: (_) {},
    );
  }

  Future<List<LongTermMemory>> noLongTerm() async => <LongTermMemory>[];
  Future<List<BaseMemory>> noBase() async => <BaseMemory>[];

  Agent agent({
    bool realInfoEnabled = false,
    String worldview = '',
    int maxResponseLength = 300,
  }) {
    return Agent(
      id: 'a1',
      name: '小红',
      gender: '女',
      description: '温柔体贴',
      persona: '你是{{NAME}}，性别{{GENDER}}。{{DESCRIPTION}}',
      worldview: worldview,
      realInfoEnabled: realInfoEnabled,
      maxResponseLength: maxResponseLength,
    );
  }

  group('ChatPromptBuilder.build 基本结构', () {
    test('完整提示词包含无冲突的私聊工具规则', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
        agent: agent(),
      );
      expectPrivateToolPolicy(prompt);
    });

    test('包含时间、人设、记忆与固定段落', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
        agent: agent(),
      );
      expect(prompt, contains('【当前真实时间】'));
      expect(prompt, contains('（星期'));
      expect(prompt, contains('你是小红，性别女。温柔体贴'));
      expect(prompt, contains('（暂无长期记忆条目）'));
      expect(prompt, contains('（暂无基础记忆条目）'));
      expect(prompt, contains('## 角色定位（极其重要）'));
      expect(prompt, contains('## 你的记忆'));
      expect(prompt, contains('## 对话风格'));
      expect(prompt, contains('每次回复尽量控制在不超过 300 个字以内'));
    });

    test('人设占位符 {{NAME}}/{{GENDER}}/{{DESCRIPTION}} 全部替换', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
        agent: agent(),
      );
      expect(prompt, isNot(contains('{{NAME}}')));
      expect(prompt, isNot(contains('{{GENDER}}')));
      expect(prompt, isNot(contains('{{DESCRIPTION}}')));
    });

    test('自定义 maxResponseLength 注入回复长度段', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
        agent: agent(maxResponseLength: 120),
      );
      expect(prompt, contains('不超过 120 个字以内'));
    });

    test('世界观非空时注入世界观段与严格遵守要求', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
        agent: agent(worldview: '末世废土'),
      );
      expect(prompt, contains('## 世界观\n末世废土'));
      expect(prompt, contains('你必须严格遵守以上世界观设定'));
    });

    test('世界观为空时不出现世界观段', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
        agent: agent(),
      );
      expect(prompt, isNot(contains('## 世界观')));
    });
  });

  group('ChatPromptBuilder.build 记忆格式化', () {
    test('长期/基础记忆按 toPromptLine 逐行注入', () async {
      final prompt = await builder().build(
        readLongTerm: () async => [
          LongTermMemory(id: 'L-1', field: '喜好', content: '喜欢草莓蛋糕'),
          LongTermMemory(id: 'L-2', field: '约定', content: '周末一起看海'),
        ],
        readBase: () async => [
          BaseMemory(id: 'B-1', type: 'setting', content: '用户是夜猫子'),
          BaseMemory(id: 'B-2', type: 'event', content: '上周去了海边'),
        ],
        agent: agent(),
      );
      expect(prompt, contains('【长期记忆】\nL-1 [喜好]: 喜欢草莓蛋糕\nL-2 [约定]: 周末一起看海'));
      expect(
        prompt,
        contains('【基础记忆】\nB-1 [setting]: 用户是夜猫子\nB-2 [event]: 上周去了海边'),
      );
    });

    test('无智能体时人设取基础记忆 setting 条目拼接', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: () async => [
          BaseMemory(id: 'B-1', type: 'setting', content: '你是小绿'),
          BaseMemory(id: 'B-2', type: 'event', content: '不相关事件'),
          BaseMemory(id: 'B-3', type: 'setting', content: '性格活泼'),
        ],
      );
      expect(prompt, contains('你是小绿\n性格活泼'));
      expect(prompt, isNot(contains(defaultSystemPersona)));
    });

    test('无智能体且无 setting 记忆时人设回退 defaultSystemPersona', () async {
      final prompt = await builder().build(
        readLongTerm: noLongTerm,
        readBase: noBase,
      );
      expect(prompt, contains(defaultSystemPersona));
    });

    test('单份记忆读取失败时该份按空列表降级，另一份仍注入', () async {
      final prompt = await builder().build(
        readLongTerm: () => throw StateError('db broken'),
        readBase: () async => [
          BaseMemory(id: 'B-1', type: 'setting', content: '用户是夜猫子'),
        ],
        agent: agent(),
      );
      expect(prompt, contains('（暂无长期记忆条目）'));
      expect(prompt, contains('B-1 [setting]: 用户是夜猫子'));
    });
  });

  group('ChatPromptBuilder.build 真实信息/画像开关', () {
    test('realInfoEnabled=false 时不注入环境信息与用户画像', () async {
      var realInfoCalled = false;
      final prompt = await builder(
        readRealInfo: () async {
          realInfoCalled = true;
          return {'weather': '晴'};
        },
        readProfileEntries: () async => [
          ProfileEntry(
            id: 'p1',
            category: 'basic_info',
            key: '姓名',
            value: '小明',
            confidence: 90,
          ),
        ],
      ).build(readLongTerm: noLongTerm, readBase: noBase, agent: agent());
      expect(realInfoCalled, isFalse);
      expect(prompt, isNot(contains('## 环境信息')));
      expect(prompt, isNot(contains('## 用户画像')));
    });

    test('realInfoEnabled=true 时注入环境信息与用户画像（按可信度降序）', () async {
      final prompt =
          await builder(
            readRealInfo: () async => {
              'weather': '晴 25℃',
              'device': 'Android 手机',
            },
            readProfileEntries: () async => [
              ProfileEntry(
                id: 'p1',
                category: 'basic_info',
                key: '姓名',
                value: '小明',
                confidence: 60,
              ),
              ProfileEntry(
                id: 'p2',
                category: 'basic_info',
                key: '年龄',
                value: '25',
                confidence: 95,
              ),
              ProfileEntry(
                id: 'p3',
                category: 'interests',
                key: '喜欢的音乐',
                value: '爵士',
                confidence: 80,
              ),
            ],
          ).build(
            readLongTerm: noLongTerm,
            readBase: noBase,
            agent: agent(realInfoEnabled: true),
          );
      expect(prompt, contains('## 环境信息'));
      expect(prompt, contains('【天气】晴 25℃'));
      expect(prompt, contains('## 用户画像'));
      expect(prompt, contains('### 📋 基本信息'));
      // 同分类内按可信度降序：年龄(95) 在 姓名(60) 之前
      final ageIdx = prompt.indexOf('- 年龄: 25（可信度95%）');
      final nameIdx = prompt.indexOf('- 姓名: 小明（可信度60%）');
      expect(ageIdx, greaterThanOrEqualTo(0));
      expect(nameIdx, greaterThan(ageIdx));
      expect(prompt, contains('### 🎯 兴趣爱好'));
      expect(prompt, contains('- 喜欢的音乐: 爵士（可信度80%）'));
    });

    test('画像读取失败时仅跳过画像段，不整体降级', () async {
      final prompt =
          await builder(
            readRealInfo: () async => {'weather': '晴'},
            readProfileEntries: () => throw StateError('profile db broken'),
          ).build(
            readLongTerm: noLongTerm,
            readBase: noBase,
            agent: agent(realInfoEnabled: true),
          );
      expect(prompt, contains('## 环境信息'));
      expect(prompt, isNot(contains('## 用户画像')));
      // 仍包含完整记忆段（未走 fallback）
      expect(prompt, contains('【长期记忆】'));
    });
  });

  group('ChatPromptBuilder.build 降级路径', () {
    test('降级提示词同样保留私聊工具规则', () {
      expectPrivateToolPolicy(builder().buildFallback(agent()));
    });

    test('整体超时降级为精简提示词（无记忆/时间/环境段）', () async {
      final prompt =
          await builder(
            memoryTimeout: const Duration(milliseconds: 50),
            // 真实信息采集不走逐份降级，直接拖慢以触发整体超时
            readRealInfo: () async {
              await Future.delayed(const Duration(seconds: 5));
              return <String, String>{};
            },
          ).build(
            readLongTerm: noLongTerm,
            readBase: noBase,
            agent: agent(realInfoEnabled: true),
          );
      expect(prompt, contains('你是小红，性别女。温柔体贴'));
      expect(prompt, contains('## 角色定位（极其重要）'));
      expect(prompt, contains('## 对话风格'));
      expect(prompt, isNot(contains('【当前真实时间】')));
      expect(prompt, isNot(contains('【长期记忆】')));
      expect(prompt, isNot(contains('## 你的记忆')));
    });

    test('构建抛异常同样降级', () async {
      // 真实信息采集在构建中途抛错且不走逐份降级 → 整体 fallback
      final prompt =
          await builder(
            readRealInfo: () => throw StateError('realinfo broken'),
          ).build(
            readLongTerm: noLongTerm,
            readBase: noBase,
            agent: agent(realInfoEnabled: true),
          );
      expect(prompt, contains('你是小红，性别女。温柔体贴'));
      expect(prompt, isNot(contains('【长期记忆】')));
    });

    test('buildFallback 无智能体时使用 defaultSystemPersona', () {
      final prompt = builder().buildFallback(null);
      expect(prompt, contains(defaultSystemPersona));
      expect(prompt, contains('不超过 300 个字以内'));
    });

    test('buildFallback 保留世界观与自定义回复长度', () {
      final prompt = builder().buildFallback(
        agent(worldview: ' 赛博朋克 ', maxResponseLength: 80),
      );
      expect(prompt, contains('## 世界观\n赛博朋克'));
      expect(prompt, contains('不超过 80 个字以内'));
    });
  });
}
