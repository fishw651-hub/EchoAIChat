import 'package:aichat/services/network_copy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloaded copies cannot upload', () {
    expect(canUploadNetworkCopy(NetworkCopySource.downloaded), isFalse);
    expect(canUploadNetworkCopy(NetworkCopySource.none), isTrue);
    expect(canUploadNetworkCopy(NetworkCopySource.owner), isTrue);
  });

  test('opening line rejects null empty and whitespace', () {
    expect(hasRequiredOpeningLine(null), isFalse);
    expect(hasRequiredOpeningLine(''), isFalse);
    expect(hasRequiredOpeningLine('  '), isFalse);
    expect(hasRequiredOpeningLine('你好'), isTrue);
  });

  test('only an owned bound copy should offer network sync', () {
    expect(
      shouldOfferNetworkSync(NetworkCopySource.owner, 7),
      isTrue,
    );
    expect(
      shouldOfferNetworkSync(NetworkCopySource.owner, null),
      isFalse,
    );
    expect(
      shouldOfferNetworkSync(NetworkCopySource.none, null),
      isFalse,
    );
    expect(
      shouldOfferNetworkSync(NetworkCopySource.downloaded, 7),
      isFalse,
    );
  });
}
