abstract final class NetworkCopySource {
  static const none = 'none';
  static const owner = 'owner';
  static const downloaded = 'downloaded';
}

bool canUploadNetworkCopy(String source) =>
    source != NetworkCopySource.downloaded;

bool hasRequiredOpeningLine(String? value) =>
    value != null && value.trim().isNotEmpty;

bool shouldOfferNetworkSync(String source, int? networkId) =>
    source == NetworkCopySource.owner && networkId != null;
