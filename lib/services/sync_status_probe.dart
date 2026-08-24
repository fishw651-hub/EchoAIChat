import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef SyncStatusGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

class SyncStatusProbe {
  static final http.Client _sharedClient = http.Client();

  SyncStatusProbe({
    SyncStatusGet? get,
    Future<void> Function(Duration)? delay,
    this.timeout = const Duration(seconds: 12),
    this.retryDelay = const Duration(milliseconds: 250),
  }) : _get = get ?? _sharedClient.get,
       _delay = delay ?? Future<void>.delayed;

  final SyncStatusGet _get;
  final Future<void> Function(Duration) _delay;
  final Duration timeout;
  final Duration retryDelay;

  Future<http.Response> fetch(Uri uri, {Map<String, String>? headers}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _get(uri, headers: headers).timeout(timeout);
      } catch (error) {
        if (attempt == 1) rethrow;
        debugPrint(
          '[Sync] transient status probe failure; retrying once '
          '(${error.runtimeType})',
        );
        await _delay(retryDelay);
      }
    }
    throw StateError('unreachable sync status probe state');
  }
}
