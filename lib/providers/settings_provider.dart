import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    final totalPromptTokens = prefs.getInt('total_prompt_tokens') ?? 0;
    final totalCompletionTokens = prefs.getInt('total_completion_tokens') ?? 0;

    state = state.copyWith(
      maxShortTermRounds: prefs.getInt('max_short_term_rounds') ?? 20,
      isFirstRun: prefs.getBool('is_first_run') ?? true,
      totalPromptTokens: totalPromptTokens,
      totalCompletionTokens: totalCompletionTokens,
      themeMode: prefs.getString('theme_mode') ?? 'system',
      selectedModel: prefs.getString('selected_model') ?? SettingsState.defaultModel,
      locale: prefs.getString('locale') ?? 'zh',
    );
    // 主题外观固定为“静谧回响”，仅保留系统/浅色/深色模式。
    await prefs.remove('primary_color');
    await prefs.remove('wechat_theme');
    await prefs.remove('theme_style');
    // 清理已废弃的模型价格配置（不再使用）
    await prefs.remove('input_price');
    await prefs.remove('input_unit');
    await prefs.remove('output_price');
    await prefs.remove('output_unit');
    await prefs.remove('thinking_mode');
    await prefs.remove('temperature');
  }

  // ─── Token 用量 ─────────────────

  Future<void> addTokenUsage(int promptTokens, int completionTokens) async {
    final prefs = await SharedPreferences.getInstance();
    final newPrompt = state.totalPromptTokens + promptTokens;
    final newCompletion = state.totalCompletionTokens + completionTokens;
    await prefs.setInt('total_prompt_tokens', newPrompt);
    await prefs.setInt('total_completion_tokens', newCompletion);
    state = state.copyWith(
      totalPromptTokens: newPrompt,
      totalCompletionTokens: newCompletion,
    );
  }

  // ─── 配置导出导入 ─────────────────

  Map<String, dynamic> exportConfig() {
    return {
      'memory_settings': {'maxShortTermRounds': state.maxShortTermRounds},
      'export_time': DateTime.now().toIso8601String(),
    };
  }

  Future<void> importConfig(Map<String, dynamic> config) async {
    final memorySettings = config['memory_settings'] as Map<String, dynamic>?;
    if (memorySettings != null) {
      final rounds = memorySettings['maxShortTermRounds'] as int?;
      if (rounds != null) await updateMaxShortTermRounds(rounds);
    }
  }

  // ─── 其他设置 ─────────────────

  Future<void> updateMaxShortTermRounds(int r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_short_term_rounds', r);
    state = state.copyWith(maxShortTermRounds: r);
  }

  Future<void> markFirstRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_run', false);
    state = state.copyWith(isFirstRun: false);
  }

  Future<void> updateThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setSelectedModel(String model) async {
    if (model.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_model', model);
    state = state.copyWith(selectedModel: model);
  }

  Future<void> updateLocale(String locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
    state = state.copyWith(locale: locale);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    // 只清除设置相关 key，保留 auth/sync/quota/agreement/locale/device 等其他 key
    for (final key in [
      'total_prompt_tokens',
      'total_completion_tokens',
      'max_short_term_rounds',
      'is_first_run',
      'theme_mode',
      'primary_color',
      'theme_style',
      'wechat_theme',
      'input_price',
      'input_unit',
      'output_price',
      'output_unit',
      'selected_model',
      'thinking_mode',
      'temperature',
      'locale',
    ]) {
      await prefs.remove(key);
    }
    state = const SettingsState();
  }
}

class SettingsState {
  static const String defaultModel = 'deepseek-v4-flash';

  final int maxShortTermRounds;
  final bool isFirstRun;
  final int totalPromptTokens;
  final int totalCompletionTokens;
  final String themeMode;
  final String selectedModel;
  final String locale;

  const SettingsState({
    this.maxShortTermRounds = 20,
    this.isFirstRun = true,
    this.totalPromptTokens = 0,
    this.totalCompletionTokens = 0,
    this.themeMode = 'system',
    this.selectedModel = defaultModel,
    this.locale = 'zh',
  });

  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  SettingsState copyWith({
    int? maxShortTermRounds,
    bool? isFirstRun,
    int? totalPromptTokens,
    int? totalCompletionTokens,
    String? themeMode,
    String? selectedModel,
    String? locale,
  }) {
    return SettingsState(
      maxShortTermRounds: maxShortTermRounds ?? this.maxShortTermRounds,
      isFirstRun: isFirstRun ?? this.isFirstRun,
      totalPromptTokens: totalPromptTokens ?? this.totalPromptTokens,
      totalCompletionTokens:
          totalCompletionTokens ?? this.totalCompletionTokens,
      themeMode: themeMode ?? this.themeMode,
      selectedModel: selectedModel ?? this.selectedModel,
      locale: locale ?? this.locale,
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
