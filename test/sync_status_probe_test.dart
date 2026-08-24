import 'package:aichat/services/sync_status_probe.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retries one transient connection failure then returns response',
    () async {
      var calls = 0;
      final delays = <Duration>[];
      final probe = SyncStatusProbe(
        get: (uri, {headers}) async {
          calls++;
          if (calls == 1) {
            throw http.ClientException('handshake terminated', uri);
          }
          return http.Response('{"code":0}', 200);
        },
        delay: (duration) async => delays.add(duration),
      );

      final response = await probe.fetch(
        Uri.parse('https://example.com/status'),
      );

      expect(response.statusCode, 200);
      expect(calls, 2);
      expect(delays, const [Duration(milliseconds: 250)]);
    },
  );

  test('stops after the second connection failure', () async {
    var calls = 0;
    final probe = SyncStatusProbe(
      get: (uri, {headers}) async {
        calls++;
        throw http.ClientException('connection closed', uri);
      },
      delay: (_) async {},
    );

    await expectLater(
      probe.fetch(Uri.parse('https://example.com/status')),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 2);
  });

  test('does not retry a completed HTTP error response', () async {
    var calls = 0;
    final probe = SyncStatusProbe(
      get: (uri, {headers}) async {
        calls++;
        return http.Response('unavailable', 503);
      },
    );

    final response = await probe.fetch(Uri.parse('https://example.com/status'));

    expect(response.statusCode, 503);
    expect(calls, 1);
  });
}
