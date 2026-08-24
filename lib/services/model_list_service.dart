import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/server_config.dart';

/// 聊天模型条目（来自服务器公开端点 GET /api/v1/models）
class ModelInfo {
  final String id;
  final String name;

  /// 1 = 支持思考模式，0 = 不支持；旧版服务器无此字段时默认 1
  final int thinkingStatus;

  /// 是否原生支持视觉输入（native_vision）；旧版服务器无此字段时默认 false
  final bool nativeVision;

  /// 绑定的视觉模型 id（vision_model_id）；为空表示未绑定
  final String visionModelId;

  const ModelInfo({
    required this.id,
    required this.name,
    this.thinkingStatus = 1,
    this.nativeVision = false,
    this.visionModelId = '',
  });

  /// 该模型是否可通过某种方式识图（原生视觉或已绑定视觉模型）
  bool get canSeeImages => nativeVision || visionModelId.isNotEmpty;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? '').toString();
    final rawStatus = json['thinking_status'];
    final rawNativeVision = json['native_vision'];
    return ModelInfo(
      id: id,
      name: name.isEmpty ? id : name,
      thinkingStatus: rawStatus is num ? rawStatus.toInt() : 1,
      nativeVision: rawNativeVision is bool
          ? rawNativeVision
          : rawNativeVision is num
              ? rawNativeVision != 0
              : false,
      visionModelId: (json['vision_model_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'thinking_status': thinkingStatus,
    'native_vision': nativeVision,
    'vision_model_id': visionModelId,
  };
}

/// 拉取/缓存聊天模型列表。离线或拉取失败时使用 SharedPreferences 缓存。
class ModelListService {
  ModelListService._();
  static final ModelListService instance = ModelListService._();

  /// 默认聊天模型（未选择或列表为空时的回退）
  static const String defaultModel = 'deepseek-v4-flash';

  /// 读取用户选择的模型（无选择时回退 [defaultModel]）。
  /// 直接读 SharedPreferences，前台与后台 isolate 均可用
  /// （后台 isolate 需已 DartPluginRegistrant.ensureInitialized）。
  static Future<String> getSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('selected_model');
    return (selected == null || selected.isEmpty) ? defaultModel : selected;
  }

  static const String _cacheKey = 'cached_model_list';

  /// 测试注入点：设置后 fetch 走该 client
  @visibleForTesting
  static http.Client? testClient;

  /// 解析 /api/v1/models 响应体（code==0 信封，data 为模型数组）。
  /// thinking_status 缺失时默认 1（支持思考）。
  static List<ModelInfo> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('模型列表响应不是 JSON 对象');
    }
    if (decoded['code'] != 0) {
      throw FormatException(
        '服务器返回错误: ${decoded['message'] ?? decoded['code']}',
      );
    }
    final data = decoded['data'];
    // 服务器实际返回 data 为 {"models": [...]} 对象；兼容 data 直接是数组的旧形态
    final list = data is Map<String, dynamic> ? data['models'] : data;
    if (list is! List) {
      throw const FormatException('模型列表 data 字段缺失或不是数组');
    }
    final models = <ModelInfo>[];
    for (final item in list) {
      if (item is! Map) continue;
      final model = ModelInfo.fromJson(Map<String, dynamic>.from(item));
      if (model.id.isEmpty) continue;
      models.add(model);
    }
    if (models.isEmpty) {
      throw const FormatException('模型列表为空');
    }
    return models;
  }

  /// 读取缓存的模型列表（无缓存或损坏时返回空列表）
  static Future<List<ModelInfo>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) ModelInfo.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveCache(List<ModelInfo> models) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode([for (final m in models) m.toJson()]),
    );
  }

  /// 从服务器拉取模型列表（不写缓存，由调用方决定）
  Future<List<ModelInfo>> fetch() async {
    final client = testClient ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse(ServerConfig.modelsUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw FormatException('HTTP ${response.statusCode}');
      }
      return parse(response.body);
    } finally {
      if (testClient == null) client.close();
    }
  }

  /// 所选模型是否支持思考模式。未知模型（不在列表中）不降级（fail-open）。
  static bool supportsThinking(Iterable<ModelInfo> models, String modelId) {
    for (final m in models) {
      if (m.id == modelId) return m.thinkingStatus != 0;
    }
    return true;
  }

  /// 发图能力预检（私聊图片按钮）：查不到模型（列表未就绪/刷新失败）时
  /// 视为能力未知，fail-open 放行让服务器裁决；只有明确查到不能识图才拦截。
  static bool canSendImages(ModelInfo? info) => info == null || info.canSeeImages;

  /// 按 id 查找模型，未找到返回 null
  static ModelInfo? findById(Iterable<ModelInfo> models, String modelId) {
    for (final m in models) {
      if (m.id == modelId) return m;
    }
    return null;
  }
}

class ModelListState {
  final List<ModelInfo> models;
  final bool refreshing;

  const ModelListState({
    this.models = const [
      ModelInfo(
        id: ModelListService.defaultModel,
        name: ModelListService.defaultModel,
      ),
    ],
    this.refreshing = false,
  });

  ModelListState copyWith({List<ModelInfo>? models, bool? refreshing}) {
    return ModelListState(
      models: models ?? this.models,
      refreshing: refreshing ?? this.refreshing,
    );
  }
}

class ModelListNotifier extends StateNotifier<ModelListState> {
  ModelListNotifier() : super(const ModelListState()) {
    _init();
  }

  Future<void> _init() async {
    final cached = await ModelListService.loadCached();
    if (cached.isNotEmpty && mounted) {
      state = ModelListState(models: cached);
    }
  }

  /// 重拉模型列表。成功返回 null 并写入缓存；失败返回错误描述并保留现状。
  Future<String?> refresh() async {
    if (state.refreshing) return null;
    state = state.copyWith(refreshing: true);
    try {
      final models = await ModelListService.instance.fetch();
      await ModelListService.saveCache(models);
      if (mounted) state = ModelListState(models: models);
      return null;
    } catch (e) {
      if (mounted) state = state.copyWith(refreshing: false);
      return e.toString();
    }
  }
}

final modelListProvider =
    StateNotifierProvider<ModelListNotifier, ModelListState>(
      (ref) => ModelListNotifier(),
    );
