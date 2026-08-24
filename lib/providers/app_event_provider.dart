import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_event_debouncer.dart';
import '../services/network_service.dart';
import '../services/quota_service.dart';
import '../services/sync_websocket_service.dart';
import 'auth_provider.dart';

bool isSameReviewSession(
  AuthState current, {
  required String owner,
  required String jwt,
}) {
  return current.isLoggedIn &&
      current.user?.username == owner &&
      current.jwtToken == jwt;
}

class ReviewNotice {
  const ReviewNotice({
    required this.eventId,
    required this.resourceType,
    required this.resourceId,
    required this.name,
    required this.reason,
  });

  final String eventId;
  final String resourceType;
  final int resourceId;
  final String name;
  final String reason;
}

/// 按服务端顺序返回尚未展示的拒绝通知。
List<ReviewNotice> unseenReviewNotices(
  Iterable<Map<String, dynamic>> statuses,
  Set<String> seen,
) {
  final notices = <ReviewNotice>[];
  for (final item in statuses) {
    if (item['status'] != 'rejected') continue;
    final reason = item['reject_reason']?.toString().trim() ?? '';
    final type = item['resource_type']?.toString() ?? '';
    final id = (item['id'] as num?)?.toInt();
    final version = (item['version'] as num?)?.toInt() ?? 0;
    if (reason.isEmpty || type.isEmpty || id == null) continue;
    final reviewedAt = item['reviewed_at']?.toString() ?? '';
    final eventId = 'review:$type:$id:$version:rejected:$reviewedAt';
    if (seen.contains(eventId)) continue;
    notices.add(
      ReviewNotice(
        eventId: eventId,
        resourceType: type,
        resourceId: id,
        name: item['name']?.toString() ?? '',
        reason: reason,
      ),
    );
  }
  return notices;
}

class AppEventState {
  const AppEventState({
    this.networkAgentRevision = 0,
    this.networkGroupRevision = 0,
    this.myUploadsRevision = 0,
    this.quotaRevision = 0,
    this.reviewNotice,
    this.reviewNoticeRevision = 0,
  });

  final int networkAgentRevision;
  final int networkGroupRevision;
  final int myUploadsRevision;
  final int quotaRevision;
  final ReviewNotice? reviewNotice;
  final int reviewNoticeRevision;

  AppEventState copyWith({
    int? networkAgentRevision,
    int? networkGroupRevision,
    int? myUploadsRevision,
    int? quotaRevision,
    ReviewNotice? reviewNotice,
    int? reviewNoticeRevision,
    bool clearReviewNotice = false,
  }) {
    return AppEventState(
      networkAgentRevision: networkAgentRevision ?? this.networkAgentRevision,
      networkGroupRevision: networkGroupRevision ?? this.networkGroupRevision,
      myUploadsRevision: myUploadsRevision ?? this.myUploadsRevision,
      quotaRevision: quotaRevision ?? this.quotaRevision,
      reviewNotice: clearReviewNotice
          ? null
          : (reviewNotice ?? this.reviewNotice),
      reviewNoticeRevision: reviewNoticeRevision ?? this.reviewNoticeRevision,
    );
  }
}

class AppEventNotifier extends StateNotifier<AppEventState> {
  AppEventNotifier(this._ref) : super(const AppEventState()) {
    _debouncer = AppEventDebouncer(
      delay: const Duration(milliseconds: 400),
      onFlush: (scopes) => unawaited(_applyScopes(scopes)),
    );
    _eventSubscription = SyncWebSocketService.instance.appEvents.listen(
      _handleEvent,
    );
    _readySubscription = SyncWebSocketService.instance.readyEvents.listen((_) {
      unawaited(refreshAfterReconnect());
    });
    if (SyncWebSocketService.instance.isConnected) {
      unawaited(refreshAfterReconnect());
    }
  }

  final Ref _ref;
  late final AppEventDebouncer _debouncer;
  StreamSubscription<SyncWSMessage>? _eventSubscription;
  StreamSubscription<void>? _readySubscription;
  bool _reviewFetchRunning = false;
  bool _reviewFetchPending = false;

  void _handleEvent(SyncWSMessage event) {
    final scope = event.scope;
    if (scope == null || scope.isEmpty) return;
    _debouncer.add(scope);
  }

  Future<void> _applyScopes(Set<String> scopes) async {
    if (!mounted) return;
    var next = state;
    if (scopes.contains('network_agents')) {
      next = next.copyWith(networkAgentRevision: next.networkAgentRevision + 1);
    }
    if (scopes.contains('network_groups')) {
      next = next.copyWith(networkGroupRevision: next.networkGroupRevision + 1);
    }
    if (scopes.contains('my_uploads')) {
      next = next.copyWith(myUploadsRevision: next.myUploadsRevision + 1);
    }
    if (scopes.contains('quota') || scopes.contains('subscription')) {
      await QuotaService.instance.invalidateCache();
      next = next.copyWith(quotaRevision: next.quotaRevision + 1);
      unawaited(_ref.read(authProvider.notifier).refreshUserProfile());
    }
    if (mounted) state = next;

    if (scopes.contains('subscription')) {
      await _ref.read(authProvider.notifier).refreshSubscription();
    }
    if (scopes.contains('my_uploads')) {
      await _refreshReviewStatuses();
    }
  }

  Future<void> refreshAfterReconnect() async {
    final auth = _ref.read(authProvider);
    if (!auth.isLoggedIn) return;
    NetworkService().setToken(auth.jwtToken);
    await QuotaService.instance.invalidateCache();
    if (mounted) {
      state = state.copyWith(
        networkAgentRevision: state.networkAgentRevision + 1,
        networkGroupRevision: state.networkGroupRevision + 1,
        myUploadsRevision: state.myUploadsRevision + 1,
        quotaRevision: state.quotaRevision + 1,
      );
    }
    unawaited(_ref.read(authProvider.notifier).refreshUserProfile());
    await _refreshReviewStatuses();
  }

  Future<void> refreshAfterResume() async {
    await _ref.read(authProvider.notifier).ensureRealtimeConnection();
    await refreshAfterReconnect();
  }

  Future<void> _refreshReviewStatuses() async {
    if (_reviewFetchRunning) {
      _reviewFetchPending = true;
      return;
    }
    final auth = _ref.read(authProvider);
    final owner = auth.user?.username;
    final jwt = auth.jwtToken;
    if (!auth.isLoggedIn ||
        owner == null ||
        owner.isEmpty ||
        jwt == null ||
        jwt.isEmpty) {
      return;
    }

    _reviewFetchRunning = true;
    try {
      NetworkService().setToken(jwt);
      final statuses = await NetworkService().listMyReviewStatuses();
      if (!isSameReviewSession(
        _ref.read(authProvider),
        owner: owner,
        jwt: jwt,
      )) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final ownerKey = base64Url.encode(utf8.encode(owner));
      final key = 'network_review_seen_$ownerKey';
      final seen = (prefs.getStringList(key) ?? const <String>[]).toSet();
      final notices = unseenReviewNotices(statuses, seen);
      final newestNotice = notices.isEmpty ? null : notices.first;

      if (newestNotice != null) {
        if (!isSameReviewSession(
          _ref.read(authProvider),
          owner: owner,
          jwt: jwt,
        )) {
          return;
        }
        final retained = <String>[
          newestNotice.eventId,
          ...seen,
        ].take(200).toList();
        await prefs.setStringList(key, retained);
      }
      if (newestNotice != null &&
          mounted &&
          isSameReviewSession(
            _ref.read(authProvider),
            owner: owner,
            jwt: jwt,
          )) {
        state = state.copyWith(
          reviewNotice: newestNotice,
          reviewNoticeRevision: state.reviewNoticeRevision + 1,
        );
      }
    } catch (_) {
      // 断网时保留补取机会，下一次 ready/resume 再试。
    } finally {
      _reviewFetchRunning = false;
      if (_reviewFetchPending) {
        _reviewFetchPending = false;
        unawaited(_refreshReviewStatuses());
      }
    }
  }

  void acknowledgeReviewNotice(String eventId) {
    if (state.reviewNotice?.eventId == eventId) {
      state = state.copyWith(clearReviewNotice: true);
      unawaited(_refreshReviewStatuses());
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _eventSubscription?.cancel();
    _readySubscription?.cancel();
    super.dispose();
  }
}

final appEventProvider = StateNotifierProvider<AppEventNotifier, AppEventState>(
  AppEventNotifier.new,
);
