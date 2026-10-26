/// Builds the bounded Cloudflare Images delivery contract.
class ImageUrlHelper {
  /// Standard thumbnail widths to maximize CDN cache hits.
  static const int thumbnailWidth = 300;
  static const int mediumWidth = 600;
  static const int fullWidth = 1200;

  static const Set<String> _imageHosts = {
    'img.festapp.net',
    'a.img.festapp.net',
  };
  static const Set<int> _widths = {thumbnailWidth, mediumWidth, fullWidth};

  /// Returns historical/noncanonical inputs unchanged as originals.
  static String transformImageUrl(
    String originalUrl, {
    int width = thumbnailWidth,
  }) {
    try {
      final uri = Uri.parse(originalUrl);
      final rawPath = originalUrl.split(RegExp(r'[?#]')).first;
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !_imageHosts.contains(uri.host) ||
          !_widths.contains(width) ||
          !uri.path.startsWith('/images/') ||
          rawPath.contains('%') ||
          uri.pathSegments.contains('..') ||
          uri.path.startsWith('/cdn-cgi/image/') ||
          !RegExp(r'\.(jpe?g|png|webp|gif|avif|svg)$', caseSensitive: false)
              .hasMatch(uri.path)) {
        return originalUrl;
      }
      final source = Uri(scheme: 'https', host: uri.host, path: uri.path);
      final options =
          'width=$width,fit=scale-down,format=auto,quality=75,onerror=redirect';
      return 'https://${uri.host}/cdn-cgi/image/$options/$source';
    } catch (_) {
      return originalUrl;
    }
  }
}
