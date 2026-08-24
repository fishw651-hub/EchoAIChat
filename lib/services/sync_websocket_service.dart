import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/server_config.dart';
import 'device_id_service.dart';
import 'client_protocol.dart';

/// 同步消息（与后端 SyncMessage 对应）
class SyncWSMessage {
  final String type;
  final String? agentId;
  final String? groupId;
  final String? status; // typing / waiting
  final String? deviceId;
  final String? deviceName;
  final int? timestamp;
  final String? message;
  final int? policyVersion;
  final bool syncEnabled;
  final String? scope;
  final String? resourceType;
  final int? resourceId;
  final String? reason;
  final int? version;
  final String? eventId;

  SyncWSMessage({
    required this.type,
    this.agentId,
    this.groupId,
    this.status,
    this.deviceId,
    this.deviceName,
    this.timestamp,
    this.message,
    this.policyVersion,
    this.syncEnabled = false,
    this.scope,
    this.resourceType,
    this.resourceId,
    this.reason,
    this.version,
    this.eventId,
  });

  factory SyncWSMessage.fromJson(Map<String, dynamic> j) => SyncWSMessage(
    type: j['type'] as String? ?? '',
    agentId: j['agent_id'] as String?,
    groupId: j['group_id'] as String?,
    status: j['status'] as String?,
    deviceId: j['device_id'] as String?,
    deviceName: j['device_name'] as String?,
    timestamp: j['timestamp'] as int?,
    message: j['message'] as String?,
    policyVersion: (j['policy_version'] as num?)?.toInt(),
    syncEnabled: j['sync_enabled'] as bool? ?? false,
    scope: j['scope'] as String?,
    resourceType: j['resource_type'] as String?,
    resourceId: (j['resource_id'] as num?)?.toInt(),
    reason: j['reason'] as String?,
    version: (j['version'] as num?)?.toInt(),
    eventId: j['event_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    if (agentId != null) 'agent_id': agentId,
    if (groupId != null) 'group_id': groupId,
    if (status != null) 'status': status,
    if (deviceId != null) 'device_id': deviceId,
    if (deviceName != null) 'device_name': deviceName,
    if (timestamp != null) 'timestamp': timestamp,
    if (message != null) 'message': message,
    if (policyVersion != null) 'policy_version': policyVersion,
    if (syncEnabled) 'sync_enabled': true,
    if (scope != null) 'scope': scope,
    if (resourceType != null) 'resource_type': resourceType,
    if (resourceId != null) 'resource_id': resourceId,
    if (reason != null) 'reason': reason,
    if (version != null) 'version': version,
    if (eventId != null) 'event_id': eventId,
  };
}

/// 聊天锁状态回调
/// [lockedByOther] true=被其他设备锁定，false=锁释放
/// [deviceName] 锁定设备的名称
typedef LockCallback =
    void Function(bool lockedByOther, String? deviceName, String? status);

/// 同步变更通知回调
typedef SyncNotifyCallback = void Function(SyncWSMessage message);

/// 认证层依赖的实时连接最小接口。
///
/// 把连接生命周期抽象出来，避免认证状态和具体 WebSocket 实现强耦合，
/// 也让离线/单元测试可以注入不会访问网络的实现。
abstract interface class RealtimeConnection {
  bool get hasActiveChannel;

  Future<void> connect({required String jwt, required String deviceName});

  Future<void> disconnect();
}

typedef RealtimeChannelFactory =
    WebSocketChannel Function(
      Uri uri, {
      required bool useHeaderToken,
      required String jwt,
    });

WebSocketChannel _openRealtimeChannel(
  Uri uri, {
  required bool useHeaderToken,
  required String jwt,
}) {
  return useHeaderToken
      ? IOWebSocketChannel.connect(
          uri,
          headers: {'Authorization': 'Bearer $jwt'},
        )
      : WebSocketChannel.connect(uri);
}

/// 连接生命周期代际。
///
/// 每次显式连接都会开启新代际，登出/销毁会使旧代际失效。异步设备查询、
/// socket 回调和退避定时器都必须通过 [accepts] 检查后才能触碰当前连接。
@visibleForTesting
class RealtimeConnectionEpoch {
  int _generation = 0;
  bool _enabled = false;

  int begin() {
    _enabled = true;
    return ++_generation;
  }

  void invalidate() {
    _enabled = false;
    _generation++;
  }

  bool accepts(int generation) => _enabled && generation == _generation;
}

/// 等待服务端确认聊天锁，避免把乐观发送误当成已获得锁。
class ChatLockRequestTracker {
  ChatLockRequestTracker({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;
  final Map<String, Completer<bool>> _pending = {};

  Future<bool> begin(String key) {
    final previous = _pending.remove(key);
    if (previous != null && !previous.isCompleted) {
      previous.complete(false);
    }
    final completer = Completer<bool>();
    _pending[key] = completer;
    final result = completer.future.timeout(timeout, onTimeout: () => false);
    return result.whenComplete(() {
      if (identical(_pending[key], completer)) {
        _pending.remove(key);
      }
    });
  }

  void resolve(String key, bool acquired) {
    final completer = _pending[key];
    if (completer == null || completer.isCompleted) return;
    completer.complete(acquired);
  }

  bool isPending(String key) => _pending.containsKey(key);

  void cancelAll() {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete(false);
    }
  }
}

/// 多端同步 WebSocket 客户端
class SyncWebSocketService implements RealtimeConnection {
  SyncWebSocketService._({
    Future<String> Function()? deviceIdLoader,
    RealtimeChannelFactory? channelFactory,
  }) : _deviceIdLoader = deviceIdLoader ?? (() => DeviceIdService.id),
       _channelFactory = channelFactory ?? _openRealtimeChannel;

  @visibleForTesting
  factory SyncWebSocketService.forTesting({
    required Future<String> Function() deviceIdLoader,
    required RealtimeChannelFactory channelFactory,
  }) {
    return SyncWebSocketService._(
      deviceIdLoader: deviceIdLoader,
      channelFactory: channelFactory,
    );
  }

  static final SyncWebSocketService instance = SyncWebSocketService._();

  final Future<String> Function() _deviceIdLoader;
  final RealtimeChannelFactory _channelFactory;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  final RealtimeConnectionEpoch _epoch = RealtimeConnectionEpoch();
  String? _jwt;
  String? _deviceId;
  String? _deviceName;
  bool _ready = false;
  bool _syncEnabled = false;
  final StreamController<SyncWSMessage> _appEventController =
      StreamController<SyncWSMessage>.broadcast();
  final StreamController<void> _readyController =
      StreamController<void>.broadcast();

  // 当前持有的锁（agentId / groupId → status）
  final Map<String, String> _heldLocks = {};
  final ChatLockRequestTracker _lockRequests = ChatLockRequestTracker();

  // 外部回调
  LockCallback? onLockChange;
  SyncNotifyCallback? onSyncNotify;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;

  bool get isConnected => _ready;
  @override
  bool get hasActiveChannel => _channel != null;
  bool get syncEnabled => _ready && _syncEnabled;
  Stream<SyncWSMessage> get appEvents => _appEventController.stream;
  Stream<void> get readyEvents => _readyController.stream;

  /// 初始化并连接（需要 JWT 和设备信息）
  @override
  Future<void> connect({
    required String jwt,
    required String deviceName,
  }) async {
    if (_disposed) return;
    final generation = _epoch.begin();
    _jwt = jwt;
    final deviceId = await _deviceIdLoader();
    // 登出/切换账号可能发生在上面的异步设备 ID 查询期间。
    if (_disposed || !_epoch.accepts(generation) || _jwt != jwt) {
      return;
    }
    _deviceId = deviceId;
    _deviceName = deviceName;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // 显式 connect（登录/切换账号）：重置退避与认证失败计数
    _reconnectAttempts = 0;
    _authFailures = 0;
    unawaited(_doConnect(generation));
  }

  Future<void> _doConnect(int generation) async {
    final expectedGeneration = generation;
    if (_disposed ||
        !_epoch.accepts(expectedGeneration) ||
        _jwt == null ||
        _deviceId == null) {
      return;
    }
    _cleanupChannel();

    final base = ServerConfig.baseUrl;
    // http(s)://host:port → ws(s)://host:port
    final wsBase = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final baseUri = Uri.parse(wsBase);
    // JWT 优先走 Authorization 头（URL query 会进 CDN/反代访问日志导致 token 落盘）。
    // Web 端浏览器 WS API 不支持自定义头，回退 query 参数。
    final useHeaderToken = !kIsWeb;
    String? browserTicket;
    if (kIsWeb) {
      final ticketUri = baseUri.replace(
        path: '${baseUri.path}/api/v1/sync/ws/ticket'.replaceAll('//', '/'),
      );
      final ticketResponse = await http.get(
        ticketUri,
        headers: {
          'Authorization': 'Bearer ${_jwt!}',
          ...ClientProtocol.currentHeaders,
        },
      );
      if (ticketResponse.statusCode != 200) {
        _onDisconnect(
          'WS ticket failed: HTTP ${ticketResponse.statusCode}',
          expectedGeneration,
        );
        return;
      }
      final ticketBody =
          jsonDecode(ticketResponse.body) as Map<String, dynamic>;
      browserTicket = ((ticketBody['data'] as Map?)?['ticket'])?.toString();
      if (browserTicket == null || browserTicket.isEmpty) {
        _onDisconnect('WS ticket missing', expectedGeneration);
        return;
      }
    }
    final uri = baseUri.replace(
      path: '${baseUri.path}/api/v1/sync/ws'.replaceAll('//', '/'),
      queryParameters: {
        if (!useHeaderToken) 'ticket': browserTicket!,
        'device_id': _deviceId!,
        'device_name': _deviceName ?? '',
      },
    );

    try {
      // IO 实现才支持自定义头；Web 端浏览器 API 无此能力（上面已回退 query token）
      _channel = _channelFactory(
        uri,
        useHeaderToken: useHeaderToken,
        jwt: _jwt!,
      );
      _sub = _channel!.stream.listen(
        _onData,
        onError: (e) => _onDisconnect('WS error: $e', expectedGeneration),
        onDone: () => _onDisconnect('WS closed', expectedGeneration),
      );
    } catch (e) {
      _onDisconnect('WS connect failed: $e', expectedGeneration);
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    try {
      final j = jsonDecode(data) as Map<String, dynamic>;
      final msg = SyncWSMessage.fromJson(j);
      switch (msg.type) {
        case 'ready':
          _ready = true;
          _syncEnabled = msg.syncEnabled;
          _reconnectAttempts = 0;
          _authFailures = 0;
          _startHeartbeat();
          onConnected?.call();
          _readyController.add(null);
          break;
        case 'app_event':
          _appEventController.add(msg);
          break;
        case 'lock_status':
          _handleLockStatus(msg);
          break;
        case 'sync_notify':
          onSyncNotify?.call(msg);
          break;
        case 'pong':
          break; // 心跳响应
        case 'error':
          final key = _lockKey(msg.agentId, msg.groupId);
          if (key.isNotEmpty) {
            _heldLocks.remove(key);
            _lockRequests.resolve(key, false);
            onLockChange?.call(true, msg.deviceName, msg.status);
          }
          break;
      }
    } catch (e) {
      debugPrint('[SyncWS] parse error: $e');
    }
  }

  void _handleLockStatus(SyncWSMessage msg) {
    if (msg.message == 'released') {
      // 锁释放
      onLockChange?.call(false, null, null);
    } else if (msg.deviceId == _deviceId) {
      final key = _lockKey(msg.agentId, msg.groupId);
      if (key.isNotEmpty) _lockRequests.resolve(key, true);
    } else if (msg.deviceId != null && msg.deviceId != _deviceId) {
      // 被其他设备锁定
      onLockChange?.call(true, msg.deviceName, msg.status);
    }
  }

  /// 生成 _heldLocks 的 key（带前缀，避免 agentId 与 groupId 碰撞）
  String _lockKey(String? agentId, String? groupId) {
    if (groupId != null) return 'g:$groupId';
    if (agentId != null) return 'a:$agentId';
    return '';
  }

  /// 发送聊天锁请求（输入中 / 等待回复）
  /// [agentId] 私聊智能体 ID（与 groupId 二选一）
  /// [groupId] 群聊 ID
  /// [status] "typing" 或 "waiting"
  /// 返回 true=获取锁成功，false=被其他设备占用
  ///
  /// 发送聊天锁请求并等待服务端确认。
  Future<bool> acquireLock({
    String? agentId,
    String? groupId,
    required String status,
  }) async {
    if (!syncEnabled) return true; // 事件连接或未连接均不启用多端聊天锁
    final key = _lockKey(agentId, groupId);
    if (key.isEmpty) return true;
    if (_channel == null) return false;
    _heldLocks[key] = status;
    final result = _lockRequests.begin(key);
    final sent = _send(
      SyncWSMessage(
        type: 'chat_lock',
        agentId: agentId,
        groupId: groupId,
        status: status,
        deviceId: _deviceId,
        deviceName: _deviceName,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    if (!sent) _lockRequests.resolve(key, false);
    final acquired = await result;
    if (!acquired && !_lockRequests.isPending(key)) {
      _heldLocks.remove(key);
    }
    return acquired;
  }

  /// 释放聊天锁
  Future<void> releaseLock({String? agentId, String? groupId}) async {
    final key = _lockKey(agentId, groupId);
    _heldLocks.remove(key);
    _lockRequests.resolve(key, false);
    if (!syncEnabled) return;
    _send(
      SyncWSMessage(
        type: 'chat_unlock',
        agentId: agentId,
        groupId: groupId,
        deviceId: _deviceId,
      ),
    );
  }

  bool _send(SyncWSMessage msg) {
    if (_channel == null) return false;
    try {
      _channel!.sink.add(jsonEncode(msg.toJson()));
      return true;
    } catch (e) {
      debugPrint('[SyncWS] send failed: $e');
      return false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send(
        SyncWSMessage(
          type: 'ping',
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );
    });
  }

  void _onDisconnect(String reason, int generation) {
    if (_disposed || !_epoch.accepts(generation)) {
      return;
    }
    debugPrint('[SyncWS] $reason');
    _cleanupChannel();
    onDisconnected?.call();
    // 认证失败（token 过期/失效）不停重试打服务器——连续失败后停手，
    // 等待下次登录重新 connect()（connect 会重置计数）
    if (reason.contains('401') || reason.contains('Unauthorized')) {
      _authFailures++;
      if (_authFailures >= 3) {
        debugPrint('[SyncWS] 连续认证失败，停止重连');
        return;
      }
    } else {
      _authFailures = 0;
    }
    // 指数退避：5s → 10s → 20s → ... 封顶 5 分钟
    _reconnectAttempts++;
    final seconds = (5 * (1 << (_reconnectAttempts - 1).clamp(0, 7))).clamp(
      5,
      300,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      () => _doConnect(generation),
    );
  }

  int _reconnectAttempts = 0;
  int _authFailures = 0;

  void _cleanupChannel() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _lockRequests.cancelAll();
    _ready = false;
    _syncEnabled = false;
  }

  /// 断开并释放所有锁
  @override
  Future<void> disconnect() async {
    // 先撤销连接意图并推进代际；等待中的 connect() 或旧 socket 回调
    // 此后都不能重新建立连接。
    _epoch.invalidate();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // 在同一同步临界段内发送解锁，避免逐个 await 时新账号连接穿插进来，
    // 最后被旧账号的 cleanup 误关。
    final keys = _heldLocks.keys.toList();
    if (_ready && _syncEnabled && _channel != null) {
      for (final key in keys) {
        _send(
          SyncWSMessage(
            type: 'chat_unlock',
            agentId: key.startsWith('a:') ? key.substring(2) : null,
            groupId: key.startsWith('g:') ? key.substring(2) : null,
            deviceId: _deviceId,
          ),
        );
      }
    }
    _heldLocks.clear();
    _jwt = null;
    _deviceId = null;
    _deviceName = null;
    _cleanupChannel();
  }

  /// 永久销毁
  void dispose() {
    _disposed = true;
    disconnect();
  }
}
