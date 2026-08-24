import 'package:aichat/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('初始化删除思考和温度偏好，保留主题与所选模型', () async {
    SharedPreferences.setMockInitialValues({
      'selected_model': 'deepseek-v4-pro',
      'thinking_mode': true,
      'temperature': 0.2,
      'theme_mode': 'dark',
    });

    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();

    // 所选模型恢复持久化并加载进状态
    expect(prefs.getString('selected_model'), 'deepseek-v4-pro');
    expect(notifier.state.selectedModel, 'deepseek-v4-pro');
    expect(prefs.containsKey('thinking_mode'), isFalse);
    expect(prefs.containsKey('temperature'), isFalse);
    expect(notifier.state.themeMode, 'dark');
  });

  test('无持久化值时 selectedModel 回退默认模型', () async {
    SharedPreferences.setMockInitialValues({});

    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(notifier.state.selectedModel, SettingsState.defaultModel);
  });

  test('setSelectedModel 持久化并更新状态，空值被忽略', () async {
    SharedPreferences.setMockInitialValues({});

    final notifier = SettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await notifier.setSelectedModel('deepseek-v4-pro');
    expect(notifier.state.selectedModel, 'deepseek-v4-pro');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('selected_model'), 'deepseek-v4-pro');

    await notifier.setSelectedModel('  ');
    expect(notifier.state.selectedModel, 'deepseek-v4-pro');
  });
}
