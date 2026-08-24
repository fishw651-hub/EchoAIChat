import 'package:aichat/services/client_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('客户端安全协议固定发送版本和平台头', () {
    expect(ClientProtocol.versionCode, 67);
    expect(ClientProtocol.headers('android'), {
      'X-Client-Version-Code': '67',
      'X-Client-Platform': 'android',
    });
  });
}
