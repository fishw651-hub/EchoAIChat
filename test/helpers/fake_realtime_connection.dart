import 'package:aichat/services/sync_websocket_service.dart';

/// 测试用实时连接：记录生命周期但不访问网络。
class FakeRealtimeConnection implements RealtimeConnection {
  bool active = false;
  int connectCalls = 0;
  int disconnectCalls = 0;
  String? jwt;
  String? deviceName;

  @override
  bool get hasActiveChannel => active;

  @override
  Future<void> connect({
    required String jwt,
    required String deviceName,
  }) async {
    connectCalls++;
    this.jwt = jwt;
    this.deviceName = deviceName;
    active = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    active = false;
  }
}
