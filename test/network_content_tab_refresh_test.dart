import 'dart:async';
import 'dart:convert';

import 'package:aichat/providers/app_event_provider.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/screens/network_content_tab.dart';
import 'package:aichat/services/network_service.dart';
import 'package:aichat/services/secure_session_store.dart';
import 'package:aichat/services/sync_websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStorage implements SecureStorageBackend {
  _MemorySecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _IdleRealtimeConnection implements RealtimeConnection {
  @override
  bool get hasActiveChannel => false;

  @override
  Future<void> connect({
    required String jwt,
    required String deviceName,
  }) async {}

  @override
  Future<void> disconnect() async {}
}

class _TestAppEventNotifier extends AppEventNotifier {
  _TestAppEventNotifier(super.ref);

  void refreshAgents() {
    state = state.copyWith(
      networkAgentRevision: state.networkAgentRevision + 1,
    );
  }

  void refreshGroups() {
    state = state.copyWith(
      networkGroupRevision: state.networkGroupRevision + 1,
    );
  }
}

http.Response _marketResponse(List<Map<String, dynamic>> list) {
  return http.Response(
    jsonEncode({
      'code': 0,
      'data': {'list': list, 'total': list.length},
    }),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    NetworkService.testClient = null;
  });

  for (final scenario
      in <
        ({
          String type,
          String itemName,
          void Function(_TestAppEventNotifier) refresh,
        })
      >[
        (
          type: 'agent',
          itemName: '已下架智能体',
          refresh: (events) => events.refreshAgents(),
        ),
        (
          type: 'group',
          itemName: '已下架群聊',
          refresh: (events) => events.refreshGroups(),
        ),
      ]) {
    testWidgets('${scenario.type}市场失效事件保留列表直至强制刷新完成', (tester) async {
      SharedPreferences.setMockInitialValues({});
      var requestCount = 0;
      final firstRequest = Completer<http.BaseRequest>();
      final secondRequest = Completer<http.BaseRequest>();
      final secondResponse = Completer<http.Response>();
      NetworkService.testClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          firstRequest.complete(request);
          return _marketResponse([
            {
              'id': 1,
              'name': scenario.itemName,
              'description': '用于验证实时刷新',
              'uploader_name': 'tester',
              'download_count': 0,
            },
          ]);
        }
        secondRequest.complete(request);
        return secondResponse.future;
      });

      late _TestAppEventNotifier appEvents;
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              sessionStore: SecureSessionStore(
                storage: _MemorySecureStorage(<String, String>{}),
              ),
              realtimeConnection: _IdleRealtimeConnection(),
            ),
          ),
          appEventProvider.overrideWith((ref) {
            appEvents = _TestAppEventNotifier(ref);
            return appEvents;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).ready;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: NetworkContentTab(fixedType: scenario.type)),
        ),
      );
      await firstRequest.future.timeout(const Duration(seconds: 2));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text(scenario.itemName), findsOneWidget);

      scenario.refresh(appEvents);
      await tester.pump();
      final request = await secondRequest.future;
      expect(request.url.queryParameters.containsKey('_refresh'), isTrue);
      expect(request.url.path, '/api/v1/network/${scenario.type}s');
      expect(find.text(scenario.itemName), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      secondResponse.complete(_marketResponse(const []));
      await tester.pumpAndSettle();
      expect(find.text(scenario.itemName), findsNothing);
    });
  }
}
