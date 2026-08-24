import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'client_protocol.dart';
import 'local_typing_chunks.dart';
import 'sticker_message_codec.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;
  ApiException(this.message, {this.statusCode, this.responseBody});
  @override
  String toString() => message;
}

class ModelNotAllowedException extends ApiException {
  final List<String> allowedModels;
  final bool thinking;
  ModelNotAllowedException(
    super.message,
    this.allowedModels, {
    this.thinking = false,
    super.statusCode,
    super.responseBody,
  });
}

class ThinkingNotAllowedException extends ApiException {
  final List<String> allowedModels;
  ThinkingNotAllowedException(
    super.message,
    this.allowedModels, {
    super.statusCode,
    super.responseBody,
  });
}

/// 客户端本地渐进展示使用的事件类型。
enum ChatStreamEventType {
  /// 完整回复在本地切分后的纯文本增量（无工具调用的兜底路径）
  content,

  /// 工具调用参数的本地分片（按 index 归组拼装）
  toolCall,

  /// 完整响应的 `choices[0].finish_reason`（stop / tool_calls 等）
  finish,

  /// 完整响应携带的 usage（若有）
  usage,

  /// 完整响应携带的本次计费金额
  cost,

  /// 本地事件序列结束
  done,
}

/// 单条本地渐进展示事件。按 [type] 取用对应字段。
class ChatStreamEvent {
  final ChatStreamEventType type;
  final String? contentDelta;
  final int? toolCallIndex;
  final String? toolCallId;
  final String? toolCallName;
  final String? argumentsDelta;
  final String? finishReason;
  final Map<String, dynamic>? usage;
  final String? model;
  final double? cost;

  const ChatStreamEvent._({
    required this.type,
    this.contentDelta,
    this.toolCallIndex,
    this.toolCallId,
    this.toolCallName,
    this.argumentsDelta,
    this.finishReason,
    this.usage,
    this.model,
    this.cost,
  });

  factory ChatStreamEvent.content(String delta) =>
      ChatStreamEvent._(type: ChatStreamEventType.content, contentDelta: delta);

  factory ChatStreamEvent.toolCall({
    required int index,
    String? id,
    String? name,
    String? argumentsDelta,
  }) => ChatStreamEvent._(
    type: ChatStreamEventType.toolCall,
    toolCallIndex: index,
    toolCallId: id,
    toolCallName: name,
    argumentsDelta: argumentsDelta,
  );

  factory ChatStreamEvent.finish(String reason) =>
      ChatStreamEvent._(type: ChatStreamEventType.finish, finishReason: reason);

  factory ChatStreamEvent.usage(Map<String, dynamic> usage, String? model) =>
      ChatStreamEvent._(
        type: ChatStreamEventType.usage,
        usage: usage,
        model: model,
      );

  factory ChatStreamEvent.cost(double? cost) =>
      ChatStreamEvent._(type: ChatStreamEventType.cost, cost: cost);

  static const ChatStreamEvent done = ChatStreamEvent._(
    type: ChatStreamEventType.done,
  );
}

class ApiService {
  static const defaultChatRequestTimeout = Duration(seconds: 180);
  static final http.Client _sharedClient = http.Client();

  /// 测试注入点：设置后所有新构造的 ApiService（未显式传 client 的）
  /// 都走该 client，用于用 MockClient 驱动 provider 级测试。
  @visibleForTesting
  static http.Client? testClient;

  /// 401 全局回调（在 main.dart 注册为静默重登）：返回 true 表示登录态
  /// 已恢复，调用方用 [apiKeyProvider] 取新 token 重发一次原请求。
  static Future<bool> Function()? onUnauthorizedRetry;

  /// 提供当前最新 API Key（静默重登后 token 已变更）。
  static String? Function()? apiKeyProvider;

  /// 提供当前账号当前智能体的客户端 ID，供辅助 AI 服务补齐硬协议字段。
  static String? Function()? clientAgentIdProvider;

  /// 在非 utility 请求发出前，确保本地智能体已幂等登记到当前服务端账号。
  static Future<void> Function(String clientAgentId)?
  ensureClientAgentRegistered;

  String _baseUrl;
  String _apiKey;
  String _model;
  final bool _thinkingMode;
  final double _temperature;
  final String? _clientAgentId;
  final String _requestKind;
  final String? _proactiveClaimToken;
  final http.Client _client;
  final Duration _chatRequestTimeout;
  final Duration _localTypingInterval;
  bool _clientAgentRegistrationEnsured = false;

  ApiService({
    required String baseUrl,
    required String apiKey,
    required String model,
    bool thinkingMode = false,
    double temperature = 1.0,
    String? clientAgentId,
    String requestKind = 'chat',
    String? proactiveClaimToken,
    http.Client? client,
    Duration chatRequestTimeout = defaultChatRequestTimeout,
    Duration localTypingInterval = const Duration(milliseconds: 20),
  }) : _baseUrl = baseUrl,
       _apiKey = apiKey,
       _model = model,
       _thinkingMode = thinkingMode,
       _temperature = temperature,
       _clientAgentId = clientAgentId,
       _requestKind = requestKind,
       _proactiveClaimToken = proactiveClaimToken,
       _client = client ?? testClient ?? _sharedClient,
       _chatRequestTimeout = chatRequestTimeout,
       _localTypingInterval = localTypingInterval;

  void updateConfig({String? baseUrl, String? apiKey, String? model}) {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (apiKey != null) _apiKey = apiKey;
    if (model != null) _model = model;
  }

  static ApiService fromConfig({
    required String model,
    required String apiKey,
    required String baseUrl,
    bool thinkingMode = false,
    double temperature = 1.0,
    String? clientAgentId,
    String requestKind = 'chat',
    String? proactiveClaimToken,
  }) {
    return ApiService(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      thinkingMode: thinkingMode,
      temperature: temperature,
      clientAgentId: clientAgentId,
      requestKind: requestKind,
      proactiveClaimToken: proactiveClaimToken,
    );
  }

  /// 只读检查服务器鉴权与模型配置，不调用聊天接口或消耗计费配额。
  static Future<String> testConnection({
    required String baseUrl,
    required String apiKey,
    String? model,
  }) async {
    final baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final client = testClient ?? _sharedClient;
    final headers = {
      'Authorization': 'Bearer $apiKey',
      ...ClientProtocol.currentHeaders,
    };

    final profileResponse = await client
        .get(baseUri.resolve('api/v1/user/profile'), headers: headers)
        .timeout(const Duration(seconds: 10));

    if (profileResponse.statusCode == 401 ||
        profileResponse.statusCode == 403) {
      return 'API Key 无效或无权限';
    }
    if (profileResponse.statusCode != 200) {
      return _connectionHttpFailure(profileResponse);
    }
    try {
      final json = jsonDecode(profileResponse.body) as Map<String, dynamic>;
      if (json['code'] != 0) {
        final code = json['code'] as int? ?? -1;
        if (code == 40100) return 'API Key 无效或已过期';
        if (code == 40300) return '无权限访问';
        return '连接失败: ${json['message'] ?? '未知错误'}';
      }
    } catch (_) {
      return '连接失败: 服务器鉴权响应格式异常';
    }

    final modelsResponse = await client
        .get(baseUri.resolve('api/v1/models'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (modelsResponse.statusCode != 200) {
      return _connectionHttpFailure(modelsResponse);
    }
    try {
      final json = jsonDecode(modelsResponse.body) as Map<String, dynamic>;
      if (json['code'] != 0) {
        return '连接失败: ${json['message'] ?? '读取模型列表失败'}';
      }
      final data = json['data'];
      final rawModels = data is Map<String, dynamic> ? data['models'] : data;
      if (rawModels is! List || rawModels.isEmpty) {
        return '连接失败: 服务器没有可用模型';
      }
      if (model != null && model.isNotEmpty) {
        final available = rawModels.any(
          (item) => item is Map && item['id']?.toString() == model,
        );
        if (!available) return '连接失败: 模型 $model 当前不可用';
      }
      return '连接成功';
    } catch (_) {
      return '连接失败: 模型列表响应格式异常';
    }
  }

  static String _connectionHttpFailure(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'API Key 无效或无权限';
    }
    final bodyText = response.body;
    final truncated = bodyText.length > 100
        ? bodyText.substring(0, 100)
        : bodyText;
    return '连接失败 (HTTP ${response.statusCode}): $truncated';
  }

  String get _maskedKey {
    if (_apiKey.length <= 8) return '***';
    return '${_apiKey.substring(0, 4)}...${_apiKey.substring(_apiKey.length - 4)}';
  }

  /// 构造 chat/completions 非流式请求体。
  Map<String, dynamic> _buildRequestBody({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required String toolChoice,
  }) {
    final bodyJson = <String, dynamic>{
      'model': _model,
      'messages': messages,
      'tools': tools,
      'tool_choice': toolChoice,
      'client_agent_id': _clientAgentId ?? clientAgentIdProvider?.call() ?? '',
      'request_kind': _requestKind,
    };
    if (_proactiveClaimToken?.isNotEmpty == true) {
      bodyJson['proactive_claim_token'] = _proactiveClaimToken;
    }

    if (_thinkingMode) {
      bodyJson['thinking'] = {'type': 'enabled'};
      bodyJson['reasoning_effort'] = 'high';
      bodyJson.remove('temperature');
      bodyJson.remove('top_p');
    } else {
      bodyJson['temperature'] = _temperature;
    }
    return bodyJson;
  }

  Future<void> _ensureClientAgentRegistration() async {
    if (_requestKind == 'utility' || _clientAgentRegistrationEnsured) return;
    final callback = ensureClientAgentRegistered;
    if (callback == null) return;
    final clientAgentId = _clientAgentId ?? clientAgentIdProvider?.call() ?? '';
    if (clientAgentId.isEmpty) {
      throw ApiException('智能体标识缺失，请重新选择智能体后重试');
    }
    await callback(clientAgentId);
    _clientAgentRegistrationEnsured = true;
  }

  Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String toolChoice = 'auto',
  }) async {
    await _ensureClientAgentRegistration();
    final baseUri = Uri.parse(_baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/');
    final url = baseUri.resolve('api/v1/chat/completions').toString();

    debugPrint('══════════════════════════════════════');
    debugPrint('API CALL');
    debugPrint('  URL: $url');
    debugPrint('  Model: $_model');
    debugPrint('  Key: $_maskedKey');

    final bodyJson = _buildRequestBody(
      messages: messages,
      tools: tools,
      toolChoice: toolChoice,
    );

    debugPrint('  Body has tools: ${bodyJson.containsKey('tools')}');
    debugPrint('  Tools count: ${(bodyJson['tools'] as List?)?.length ?? 0}');
    debugPrint('  tool_choice: ${bodyJson['tool_choice'] ?? 'none'}');
    debugPrint('  thinking: ${bodyJson['thinking'] ?? 'none'}');
    debugPrint('  Messages count: ${messages.length}');
    debugPrint(
      '  Last msg role: ${messages.isNotEmpty ? messages.last['role'] : 'N/A'}',
    );
    debugPrint('══════════════════════════════════════');

    var body = jsonEncode(bodyJson);

    try {
      final response = await _postChatCompletions(url, body);

      debugPrint('  HTTP ${response.statusCode}');

      return _handleResponse(response);
    } on ThinkingNotAllowedException catch (_) {
      rethrow;
    } on ModelNotAllowedException catch (_) {
      rethrow;
    } on ApiException catch (e) {
      // 401：静默重登成功后用新 token 重发一次（重发结果不再捕获，防死循环）；
      // 重登失败直接抛出，不再走参数降级
      if (e.statusCode == 401) {
        if (await _tryRestoreUnauthorized()) {
          debugPrint('  ↻ 401 → silent re-auth OK, retrying request');
          final authRetryResponse = await _postChatCompletions(url, body);
          return _handleResponse(authRetryResponse);
        }
        rethrow;
      }
      // tool_choice / thinking 不被支持时降级重试
      final isUnsupportedParameter =
          e.statusCode == 400 ||
          e.message.contains('tool_choice') ||
          e.message.contains('does not support') ||
          e.message.contains('不支持参数');
      if (!isUnsupportedParameter) rethrow;

      var retried = false;
      if (bodyJson.containsKey('tool_choice') &&
          bodyJson['tool_choice'] == 'required' &&
          (e.message.contains('tool_choice') ||
              e.message.contains('does not support'))) {
        bodyJson.remove('tool_choice');
        retried = true;
      }
      if (bodyJson.containsKey('thinking') ||
          bodyJson.containsKey('reasoning_effort')) {
        bodyJson.remove('thinking');
        bodyJson.remove('reasoning_effort');
        retried = true;
      }
      if (retried) {
        debugPrint(
          '  ⚠ Parameter rejected → retrying with: ${bodyJson.keys.where((k) => k != 'messages' && k != 'tools')}',
        );
        body = jsonEncode(bodyJson);
        final retryResponse = await _postChatCompletions(url, body);
        return _handleResponse(retryResponse);
      }
      rethrow;
    } on SocketException catch (e) {
      debugPrint('  ERROR: SocketException - $e');
      throw ApiException(
        '网络连接失败，请检查 Base URL 是否可达',
        responseBody: e.toString(),
      );
    } on TimeoutException catch (e) {
      debugPrint('  ERROR: TimeoutException - $e');
      throw ApiException('请求超时，请检查网络或服务端状态', responseBody: e.toString());
    } on FormatException catch (e) {
      debugPrint('  ERROR: FormatException - $e');
      throw ApiException('响应格式异常，服务端返回了非 JSON 数据', responseBody: e.toString());
    } on HandshakeException catch (e) {
      debugPrint('  ERROR: HandshakeException - $e');
      throw ApiException(
        '安全证书校验失败：收到的证书与服务器域名不符。服务端证书本身有效，通常是当前网络存在代理/VPN/抓包或运营商劫持，请关闭代理或切换 Wi-Fi/流量后重试',
        responseBody: e.toString(),
      );
    } catch (e) {
      debugPrint('  ERROR: unknown - $e');
      throw ApiException('请求失败: $e');
    }
  }

  Future<http.Response> _postChatCompletions(String url, String body) {
    return _client
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            ...ClientProtocol.currentHeaders,
          },
          body: body,
        )
        .timeout(_chatRequestTimeout);
  }

  /// 401 后尝试静默重登并用最新 token 刷新本实例。返回 true=可重发一次。
  Future<bool> _tryRestoreUnauthorized() async {
    final callback = onUnauthorizedRetry;
    if (callback == null) return false;
    final restored = await callback();
    if (!restored) return false;
    final freshKey = apiKeyProvider?.call();
    if (freshKey != null && freshKey.isNotEmpty) {
      _apiKey = freshKey;
    }
    return true;
  }

  /// 非流式获取完整补全后，在客户端本地生成渐进事件。
  ///
  /// 保留 Stream 接口是为了让私聊、群聊与工具组装逻辑继续消费统一事件；
  /// 网络层只访问 `chat/completions`，不会再建立 SSE 连接。
  Stream<ChatStreamEvent> chatCompletionStream({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String toolChoice = 'auto',
  }) async* {
    final response = await chatCompletion(
      messages: messages,
      tools: tools,
      toolChoice: toolChoice,
    );
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw ApiException('服务端返回的补全结果缺少 choices');
    }
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) {
      throw ApiException('服务端返回的补全选项格式异常');
    }
    final message = choice['message'];
    if (message is! Map<String, dynamic>) {
      throw ApiException('服务端返回的补全消息格式异常');
    }

    final content = message['content'];
    if (content is String && content.isNotEmpty) {
      await for (final delta in _localTypingDeltas(content)) {
        yield ChatStreamEvent.content(delta);
      }
    }

    final toolCalls = message['tool_calls'];
    if (toolCalls is List<dynamic>) {
      for (var index = 0; index < toolCalls.length; index++) {
        final rawCall = toolCalls[index];
        if (rawCall is! Map<String, dynamic>) continue;
        final function = rawCall['function'];
        if (function is! Map<String, dynamic>) continue;
        final name = function['name']?.toString() ?? '';
        final rawArguments = function['arguments'];
        final arguments = rawArguments is String
            ? rawArguments
            : jsonEncode(rawArguments ?? <String, dynamic>{});
        final isVisibleChatTool = name == 'chat' || name == 'chatgroup';

        if (!isVisibleChatTool) {
          yield ChatStreamEvent.toolCall(
            index: index,
            id: rawCall['id']?.toString(),
            name: name,
            argumentsDelta: arguments,
          );
          continue;
        }

        var firstDelta = true;
        await for (final delta in _localTypingDeltas(arguments)) {
          yield ChatStreamEvent.toolCall(
            index: index,
            id: firstDelta ? rawCall['id']?.toString() : null,
            name: firstDelta ? name : null,
            argumentsDelta: delta,
          );
          firstDelta = false;
        }
        if (firstDelta) {
          yield ChatStreamEvent.toolCall(
            index: index,
            id: rawCall['id']?.toString(),
            name: name,
            argumentsDelta: '',
          );
        }
      }
    }

    final finishReason = choice['finish_reason'];
    if (finishReason is String && finishReason.isNotEmpty) {
      yield ChatStreamEvent.finish(finishReason);
    }
    final usage = response['usage'];
    if (usage is Map<String, dynamic>) {
      yield ChatStreamEvent.usage(usage, response['model'] as String?);
    }
    final cost = response['cost'];
    if (cost is num) {
      yield ChatStreamEvent.cost(cost.toDouble());
    }
    yield ChatStreamEvent.done;
  }

  Stream<String> _localTypingDeltas(String text) async* {
    final chunks = localTypingChunks(text);
    for (var index = 0; index < chunks.length; index++) {
      yield chunks[index];
      if (index + 1 < chunks.length && _localTypingInterval > Duration.zero) {
        await Future<void>.delayed(_localTypingInterval);
      }
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    String? bodyText;
    Map<String, dynamic>? bodyJson;

    try {
      bodyText = response.body;
      bodyJson = jsonDecode(bodyText) as Map<String, dynamic>;
    } catch (_) {
      bodyText = response.body;
    }

    if (bodyJson != null) {
      final code = bodyJson['code'] as int?;

      if (code == 0) {
        final inner = bodyJson['data'];
        if (inner == null) {
          throw ApiException(
            '服务端返回了空响应',
            statusCode: 200,
            responseBody: bodyText,
          );
        }
        if (inner is Map<String, dynamic>) {
          bodyJson = inner;
        } else {
          throw ApiException(
            '服务端返回了非预期的数据格式',
            statusCode: 200,
            responseBody: bodyText,
          );
        }
      } else if (code != null) {
        final msg = bodyJson['message'] as String? ?? '请求失败';
        switch (code) {
          case 40100:
            throw ApiException(
              '登录已过期，请重新登录',
              statusCode: 401,
              responseBody: bodyText,
            );
          case 40300:
            throw ApiException(msg, statusCode: 403, responseBody: bodyText);
          case 42900:
            throw ApiException(
              '请求过于频繁，请稍后重试',
              statusCode: 429,
              responseBody: bodyText,
            );
          default:
            final inner = bodyJson['data'] as Map<String, dynamic>?;
            final mistake = inner?['mistake'] as String?;

            if (mistake == 'model_not_allowed') {
              final allowed =
                  (inner?['allowed_models'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final thinking = inner?['thinking'] as bool? ?? false;
              throw ModelNotAllowedException(
                msg,
                allowed,
                thinking: thinking,
                statusCode: statusCode,
                responseBody: bodyText,
              );
            }
            if (mistake == 'thinking_not_allowed') {
              final allowed =
                  (inner?['allowed_models'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              throw ThinkingNotAllowedException(
                msg,
                allowed,
                statusCode: statusCode,
                responseBody: bodyText,
              );
            }
            if (mistake == 'balance_insufficient') {
              throw ApiException(
                msg,
                statusCode: statusCode,
                responseBody: bodyText,
              );
            }

            if (msg.contains('不支持模型') || msg.contains('允许的模型')) {
              final allowedModels = _parseAllowedModels(msg);
              throw ModelNotAllowedException(
                msg,
                allowedModels,
                statusCode: statusCode,
                responseBody: bodyText,
              );
            }
            if (msg.contains('不支持思考') ||
                msg.contains('不支持的思考') ||
                msg.contains('思考模式')) {
              throw ThinkingNotAllowedException(
                msg,
                const [],
                statusCode: statusCode,
                responseBody: bodyText,
              );
            }
            throw ApiException(
              '[$code] $msg',
              statusCode: statusCode,
              responseBody: bodyText,
            );
        }
      }
    }

    if (bodyJson == null) {
      throw ApiException(
        '服务端返回了空响应',
        statusCode: statusCode,
        responseBody: bodyText,
      );
    }

    switch (statusCode) {
      case 200:
        final error = bodyJson['error'] as Map<String, dynamic>?;
        if (error != null) {
          final errMsg = error['message'] as String? ?? error.toString();
          throw ApiException(errMsg, statusCode: 200, responseBody: bodyText);
        }
        final choices = bodyJson['choices'] as List?;
        final firstChoice = choices?.first as Map<String, dynamic>?;
        final msg = firstChoice?['message'] as Map<String, dynamic>?;
        debugPrint('  Response choices: ${choices?.length ?? 0}');
        debugPrint('  Has tool_calls: ${msg?['tool_calls'] != null}');
        debugPrint('  Has content: ${msg?['content'] != null}');
        debugPrint(
          '  Content length: ${(msg?['content'] as String?)?.length ?? 0}',
        );
        debugPrint('  Finish reason: ${firstChoice?['finish_reason']}');
        return bodyJson;

      case 401:
        throw ApiException(
          'API Key 无效或已过期',
          statusCode: 401,
          responseBody: bodyText,
        );

      case 403:
        throw ApiException(
          '无权访问，请检查 API Key 权限',
          statusCode: 403,
          responseBody: bodyText,
        );

      case 404:
        final hint =
            ' (响应: ${bodyText.length > 100 ? bodyText.substring(0, 100) : bodyText})';
        throw ApiException(
          'Base URL 不正确或模型 $_model 不存在$hint',
          statusCode: 404,
          responseBody: bodyText,
        );

      case 429:
        throw ApiException(
          '请求过于频繁，请稍后重试',
          statusCode: 429,
          responseBody: bodyText,
        );

      case 400:
        final errMsg = bodyJson['error']?['message'] as String? ?? '请求参数有误';
        throw ApiException(errMsg, statusCode: 400, responseBody: bodyText);

      default:
        if (statusCode >= 500) {
          throw ApiException(
            '服务端错误 ($statusCode)，请稍后重试',
            statusCode: statusCode,
            responseBody: bodyText,
          );
        }
        throw ApiException(
          'HTTP $statusCode: ${bodyText.substring(0, _min(200, bodyText.length))}',
          statusCode: statusCode,
          responseBody: bodyText,
        );
    }
  }

  int _min(int a, int b) => a < b ? a : b;

  static List<Map<String, dynamic>> parseToolCalls(
    Map<String, dynamic> response,
  ) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return [];
    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) return [];
    final toolCalls = message['tool_calls'] as List<dynamic>?;
    if (toolCalls == null || toolCalls.isEmpty) return [];
    return toolCalls.map((tc) {
      final call = tc as Map<String, dynamic>;
      return {
        'id': call['id'] as String? ?? '',
        'name': call['function']?['name'] as String? ?? '',
        'arguments': call['function']?['arguments'] is String
            ? jsonDecode(call['function']['arguments'] as String)
            : (call['function']?['arguments'] ?? {}),
      };
    }).toList();
  }

  static String? parseContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final message = choices[0]['message'] as Map<String, dynamic>?;
    return message?['content'] as String?;
  }

  static String? parseReasoningContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final message = choices[0]['message'] as Map<String, dynamic>?;
    final reasoning = message?['reasoning_content'] as String?;
    if (reasoning == null || reasoning.trim().isEmpty) return null;
    return reasoning;
  }

  static String? parseFinishReason(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    return choices[0]['finish_reason'] as String?;
  }

  static Future<Map<String, dynamic>> visionChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String? text,
    required String imageBase64,
  }) async {
    final baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final url = baseUri.resolve('api/v1/chat/completions').toString();

    final content = <Map<String, dynamic>>[];
    if (text != null && text.isNotEmpty) {
      content.add({'type': 'text', 'text': text});
    }
    content.add({
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'},
    });

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'max_tokens': 2048,
    });

    debugPrint('VISION API CALL: $url model=$model');

    final response = await _sharedClient
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
            ...ClientProtocol.currentHeaders,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final outer = jsonDecode(response.body) as Map<String, dynamic>;
      if (outer['code'] != 0) {
        throw ApiException(
          outer['message'] ?? 'Vision API error (${outer['code']})',
        );
      }
      final data = outer['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw ApiException('Vision API returned empty response');
      }
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final msg = choices.first['message'];
        if (msg != null &&
            msg['content'] is String &&
            (msg['content'] as String).isNotEmpty) {
          return {'content': msg['content'] as String};
        }
      }
      throw ApiException('Vision API returned empty response');
    }
    throw ApiException(
      'Vision API error (${response.statusCode}): ${response.body}',
    );
  }

  static List<Map<String, dynamic>> getToolDefinitions({
    bool isGroupChat = false,
  }) {
    if (isGroupChat) return _getGroupToolDefinitions();
    return _getPrivateToolDefinitions();
  }

  static List<Map<String, dynamic>> _getPrivateToolDefinitions() {
    return [_chatTool(), _planTool()];
  }

  static List<Map<String, dynamic>> getPrivateToolDefinitions({
    List<Map<String, String>> stickers = const [],
  }) {
    return [StickerMessageCodec.buildChatTool(stickers: stickers), _planTool()];
  }

  static List<Map<String, dynamic>> _getGroupToolDefinitions() {
    return [
      _rememberTool(),
      _forgetTool(),
      _chatgroupTool(),
      _planTool(),
      _manageCharacterTool(),
    ];
  }

  static Map<String, dynamic> _rememberTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'remember',
        'description': '创建或更新长期记忆/基础事件记忆。记忆是智能体对用户、自身和情境的持久认知。',
        'parameters': {
          'type': 'object',
          'properties': {
            'memory_type': {
              'type': 'string',
              'enum': ['long_term', 'base'],
              'description': 'long_term=长期记忆（结构化，9 字段之一），base=基础事件记忆。',
            },
            'action': {
              'type': 'string',
              'enum': ['create', 'update'],
              'description': 'create=新建，update=更新现有条目。',
            },
            'target_id': {
              'type': 'string',
              'description': '更新操作的目标记忆 ID（L 开头为长期记忆）。',
            },
            'field': {
              'type': 'string',
              'description':
                  '长期记忆分类字段，取值范围：identity、personality、preferences、goals、relationship、status、knowledge、schedule、other。',
            },
            'content': {'type': 'string', 'description': '记忆内容文本。'},
            'group_scope': {
              'type': 'string',
              'description': '可选，shared 表示写入群聊共享记忆。',
            },
          },
          'required': ['memory_type', 'action', 'content'],
        },
      },
    };
  }

  static Map<String, dynamic> _forgetTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'forget',
        'description': '删除长期记忆条目或基础事件条目。设定类型的基础记忆不可遗忘。',
        'parameters': {
          'type': 'object',
          'properties': {
            'target_ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '要删除的记忆 ID 列表（L 开头为长期记忆，B 开头为基础事件记忆）。',
            },
            'memory_source': {
              'type': 'string',
              'description': '可选，shared 表示删除群聊共享记忆。',
            },
          },
          'required': ['target_ids'],
        },
      },
    };
  }

  static Map<String, dynamic> _planTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'plan',
        'description': '安排一条计划消息在未来发送。send_time 可为相对时间（如 30m、2h）或 ISO 8601 格式。',
        'parameters': {
          'type': 'object',
          'properties': {
            'send_time': {
              'type': 'string',
              'description': '发送时间，例如 "30m"=30 分钟后，"2h"=2 小时后，或 ISO 8601 完整时间。',
            },
            'message': {'type': 'string', 'description': '计划发送的消息内容。'},
          },
          'required': ['send_time', 'message'],
        },
      },
    };
  }

  static Map<String, dynamic> _chatTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'chat',
        'description': '向用户发送自然语言回复。在所有记忆操作完成后，用它来最终回复。',
        'parameters': {
          'type': 'object',
          'properties': {
            'message': {'type': 'string', 'description': '回复给用户的文本。'},
          },
          'required': ['message'],
        },
      },
    };
  }

  static Map<String, dynamic> _chatgroupTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'chatgroup',
        'description': '在群聊中发送一条消息。这是你在群聊中发言的唯一方式。',
        'parameters': {
          'type': 'object',
          'properties': {
            'message': {'type': 'string', 'description': '要发送到群聊中的内容。'},
          },
          'required': ['message'],
        },
      },
    };
  }

  static Map<String, dynamic> _manageCharacterTool() {
    return {
      'type': 'function',
      'function': {
        'name': 'manage_character',
        'description':
            '为故事世界创建或移除 NPC/配角。persona 须包含身份、性格、与世界观的关系。创建后须立即用 chatgroup 定义初次登场。禁止重复创建同名角色。禁止创建：与 user 主角定位重叠的角色。user 自己扮演主角。',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['add', 'remove'],
              'description': 'add 添加角色，remove 移除角色。',
            },
            'name': {'type': 'string', 'description': '角色名称。'},
            'gender': {
              'type': 'string',
              'enum': ['男', '女', '其他'],
              'description': '角色性别，add 时必填。',
            },
            'description': {
              'type': 'string',
              'description': '角色定位描述：ta 在故事中的身份和当前场景中的位置。',
            },
            'persona': {
              'type': 'string',
              'description':
                  '角色完整人设：身份背景、性格特征、说话格式（第一人称+() 表达动作）、在当前场景中的行为动机。必须符合世界观约束。',
            },
            'target': {
              'type': 'string',
              'description': '要移除的角色名称或 ID，remove 时必填。',
            },
          },
          'required': ['action', 'name'],
        },
      },
    };
  }

  static List<String> _parseAllowedModels(String message) {
    final match = RegExp(r'允许的模型[：:]\s*(.+)').firstMatch(message);
    if (match == null) return [];
    return match
        .group(1)!
        .split(RegExp(r'[,，]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
