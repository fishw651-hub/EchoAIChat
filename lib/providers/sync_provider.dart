import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_policy.dart';
import '../services/adaptive_sync_scheduler.dart';
import '../services/sync_service.dart';
import '../services/sync_scope.dart';
import '../services/sync_websocket_service.dart';
import 'auth_provider.dart';
import 'agent_provider.dart';
import 'chat_provider.dart';
import 'group_provider.dart';

class SyncState {
  final bool isUploading;
  final bool isDownloading;
  final DateTime? lastSyncTime;
  final String? error;
  final int? itemsProcessed;
  final bool hasCloudUpdate;
  final bool canUseSync; // 订阅状态
  final bool isLoadingPolicy;
  final bool isRunning;
  final SyncPolicy? policy;
  final SyncPreview? preview;

  const SyncState({
    this.isUploading = false,
    this.isDownloading = false,
    this.lastSyncTime,
    this.error,
    this.itemsProcessed,
    this.hasCloudUpdate = false,
    this.canUseSync = false,
    this.isLoadingPolicy = false,
    this.isRunning = false,
    this.policy,
    this.preview,
  });

  SyncState copyWith({
    bool? isUploading,
    bool? isDownloading,
    DateTime? lastSyncTime,
    String? error,
    int? itemsProcessed,
    bool? hasCloudUpdate,
    bool? canUseSync,
    bool? isLoadingPolicy,
    bool? isRunning,
    SyncPolicy? policy,
    SyncPreview? preview,
    bool clearPreview = false,
  }) {
    return SyncState(
      isUploading: isUploading ?? this.isUploading,
      isDownloading: isDownloading ?? this.isDownloading,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      error: error,
      itemsProcessed: itemsProcessed ?? this.itemsProcessed,
      hasCloudUpdate: hasCloudUpdate ?? this.hasCloudUpdate,
      canUseSync: canUseSync ?? this.canUseSync,
      isLoadingPolicy: isLoadingPolicy ?? this.isLoadingPolicy,
      isRunning: isRunning ?? this.isRunning,
      policy: policy ?? this.policy,
      preview: clearPreview ? null : (preview ?? this.preview),
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  StreamSubscription<AuthState>? _authSub;
  Timer? _realtimeDebounce;
  final AdaptiveSyncScheduler _realtimeScheduler = AdaptiveSyncScheduler();
  bool _realtimePending = false;

  SyncNotifier(this._ref) : super(const SyncState()) {
    _init();
  }

  String? get _token => _ref.read(authProvider).jwtToken;

  Future<void> _init() async {
    SyncWebSocketService.instance.onSyncNotify = (message) {
      _handleRealtimeNotification(message);
    };
    // 回读本地持久化的最近同步时间（sync_service 以毫秒时间戳写入），
    // 避免重启后设置页误显示"从未同步"
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt('last_sync_time');
      if (millis != null) {
        state = state.copyWith(
          lastSyncTime: DateTime.fromMillisecondsSinceEpoch(millis),
        );
      }
    } catch (_) {}
    // 等 AuthNotifier 异步加载完成后再读取订阅状态
    await _ref.read(authProvider.notifier).ready;
    _refreshFromAuth();
    // 监听 authProvider 变化（登录/登出/订阅刷新时自动同步 canUseSync）
    _authSub = _ref.read(authProvider.notifier).stream.listen((auth) {
      final prevCanUse = state.canUseSync;
      _refreshFromAuth();
      // 从不可用变为可用时，自动检查云端更新并连接 WS
      if (!prevCanUse && state.canUseSync) {
        checkCloudUpdate();
      }
    });
    if (state.canUseSync) {
      await loadPolicy();
      await checkCloudUpdate();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _realtimeDebounce?.cancel();
    SyncWebSocketService.instance.onSyncNotify = null;
    super.dispose();
  }

  /// 从 authProvider 同步订阅状态
  /// 订阅满足：已登录 + 有生效订阅（后端已过滤 status==1 且未过期）
  void _refreshFromAuth() {
    final auth = _ref.read(authProvider);
    state = state.copyWith(canUseSync: auth.canUseSync);
  }

  /// 检查订阅状态（兼容外部调用）
  Future<void> checkSubscription() async {
    await _ref.read(authProvider.notifier).refreshSubscription();
    _refreshFromAuth();
  }

  /// 检查云端更新
  Future<void> checkCloudUpdate() async {
    if (!state.canUseSync) return;
    final hasUpdate = await SyncService.instance.checkCloudUpdate(_token);
    state = state.copyWith(hasCloudUpdate: hasUpdate);
  }

  Future<void> loadPolicy() async {
    if (!state.canUseSync) return;
    state = state.copyWith(isLoadingPolicy: true, error: null);
    try {
      final policy = await SyncService.instance.getPolicy(_token);
      state = state.copyWith(isLoadingPolicy: false, policy: policy);
    } catch (error) {
      state = state.copyWith(isLoadingPolicy: false, error: error.toString());
    }
  }

  Future<void> savePolicy(SyncPolicy desired) async {
    if (!state.canUseSync) return;
    state = state.copyWith(isLoadingPolicy: true, error: null);
    try {
      final policy = await SyncService.instance.updatePolicy(_token, desired);
      state = state.copyWith(
        isLoadingPolicy: false,
        policy: policy,
        clearPreview: true,
      );
    } on SyncException catch (error) {
      if (error.isConflict) {
        await loadPolicy();
      } else {
        state = state.copyWith(isLoadingPolicy: false, error: error.message);
      }
    }
  }

  Future<SyncPreview?> previewCurrentScope() async {
    final policy = state.policy;
    if (!state.canUseSync || policy == null) return null;
    return _preparePreview(
      policy: policy,
      scope: SyncScope.accountPolicy(policy),
      mode: 'immediate',
    );
  }

  Future<SyncPreview?> previewOneShot(Set<String> agentIds) async {
    final policy = state.policy;
    if (!state.canUseSync || policy == null) return null;
    return _preparePreview(
      policy: policy,
      scope: SyncScope.oneShot(agentIds),
      mode: 'one_shot',
    );
  }

  Future<SyncPreview?> _preparePreview({
    required SyncPolicy policy,
    required SyncScope scope,
    required String mode,
  }) async {
    state = state.copyWith(isRunning: true, error: null, clearPreview: true);
    try {
      final preview = await SyncService.instance.preview(
        token: _token,
        policy: policy,
        scope: scope,
        mode: mode,
      );
      state = state.copyWith(isRunning: false, preview: preview);
      return preview;
    } catch (error) {
      state = state.copyWith(isRunning: false, error: error.toString());
      return null;
    }
  }

  Future<SyncResult?> runPreparedPreview() async {
    final preview = state.preview;
    if (preview == null) return null;
    state = state.copyWith(isRunning: true, error: null);
    final result = await SyncService.instance.run(_token, preview);
    if (result.success) await _refreshLocalProviders();
    state = state.copyWith(
      isRunning: false,
      lastSyncTime: result.success ? DateTime.now() : null,
      error: result.error,
      itemsProcessed: result.itemsProcessed,
      clearPreview: result.success,
    );
    return result;
  }

  Future<void> _refreshLocalProviders() async {
    try {
      await _ref.read(agentProvider.notifier).refresh();
    } catch (_) {}
    try {
      await _ref.read(groupProvider.notifier).loadGroups();
    } catch (_) {}
  }

  void clearPreview() {
    state = state.copyWith(clearPreview: true);
  }

  Future<void> _handleRealtimeNotification(SyncWSMessage message) async {
    if (!state.canUseSync) return;
    if (message.message == 'sync_policy') {
      await loadPolicy();
      return;
    }
    var policy = state.policy;
    if (policy == null ||
        (message.policyVersion != null &&
            message.policyVersion != policy.version)) {
      await loadPolicy();
      policy = state.policy;
    }
    if (policy == null || !policy.realtimeEnabled) return;
    final scope = SyncScope.accountPolicy(policy);
    if (scope.mode == SyncScopeMode.selected &&
        !scope.allowsAgent(message.agentId ?? '')) {
      return;
    }
    _realtimePending = true;
    _scheduleRealtimeSync();
  }

  bool get _foregroundBusy =>
      _ref.read(chatProvider).isLoading || _ref.read(groupProvider).isLoading;

  void _scheduleRealtimeSync() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(
      _realtimeScheduler.nextDelay(foregroundBusy: _foregroundBusy),
      () {
        _runRealtimeSync();
      },
    );
  }

  Future<void> _runRealtimeSync() async {
    final policy = state.policy;
    if (policy == null || !policy.realtimeEnabled) {
      _realtimePending = false;
      return;
    }
    if (state.isRunning || _foregroundBusy) {
      _scheduleRealtimeSync();
      return;
    }
    _realtimePending = false;
    final stopwatch = Stopwatch()..start();
    state = state.copyWith(isRunning: true, error: null);
    try {
      final preview = await SyncService.instance.preview(
        token: _token,
        policy: policy,
        scope: SyncScope.accountPolicy(policy),
        mode: 'immediate',
      );
      final result = await SyncService.instance.run(_token, preview);
      if (result.success) {
        _realtimeScheduler.recordSuccess(stopwatch.elapsed);
      } else {
        _realtimeScheduler.recordFailure();
      }
      if (result.success) await _refreshLocalProviders();
      state = state.copyWith(
        isRunning: false,
        lastSyncTime: result.success ? DateTime.now() : null,
        error: result.error,
        itemsProcessed: result.itemsProcessed,
      );
    } catch (error) {
      _realtimeScheduler.recordFailure();
      state = state.copyWith(isRunning: false, error: error.toString());
    } finally {
      stopwatch.stop();
      if (_realtimePending) _scheduleRealtimeSync();
    }
  }

  /// 上传所有数据
  Future<void> uploadAll() async {
    if (!state.canUseSync) {
      state = state.copyWith(
        error: 'Current plan does not include multi-device sync',
      );
      return;
    }
    state = state.copyWith(isUploading: true, error: null);
    final result = await SyncService.instance.uploadAll(_token);
    if (result.success) await _refreshLocalProviders();
    state = state.copyWith(
      isUploading: false,
      lastSyncTime: result.success ? DateTime.now() : null,
      error: result.error,
      itemsProcessed: result.itemsProcessed,
    );
  }

  /// 下载所有数据
  Future<void> downloadAll() async {
    if (!state.canUseSync) {
      state = state.copyWith(
        error: 'Current plan does not include multi-device sync',
      );
      return;
    }
    state = state.copyWith(isDownloading: true, error: null);
    final result = await SyncService.instance.downloadAll(_token);
    if (result.success) await _refreshLocalProviders();
    state = state.copyWith(
      isDownloading: false,
      lastSyncTime: result.success ? DateTime.now() : null,
      error: result.error,
      itemsProcessed: result.itemsProcessed,
    );
  }

  Future<SyncResult?> deleteCloudCopy(SyncScope scope) async {
    if (!state.canUseSync) {
      state = state.copyWith(
        error: 'Current plan does not include multi-device sync',
      );
      return null;
    }
    state = state.copyWith(isRunning: true, error: null);
    final result = await SyncService.instance.deleteCloudCopy(
      _token,
      scope: scope,
    );
    state = state.copyWith(
      isRunning: false,
      lastSyncTime: result.success ? DateTime.now() : null,
      error: result.error,
      itemsProcessed: result.itemsProcessed,
    );
    return result;
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});
