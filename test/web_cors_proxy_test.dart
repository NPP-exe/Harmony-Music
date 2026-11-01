import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/web_cors_proxy.dart';

void main() {
  group('withWebCorsProxy', () {
    test('proxies HTTP URLs when running on web', () {
      expect(
        withWebCorsProxy(
          Uri.parse('https://music.youtube.com/youtubei/v1/search?key=test'),
          isWeb: true,
        ),
        Uri.parse(
          'https://cors-anywhere-py9w.onrender.com/https://music.youtube.com/youtubei/v1/search?key=test',
        ),
      );
    });

    test('leaves URLs unchanged outside web', () {
      final uri = Uri.parse('https://music.youtube.com/');
      expect(withWebCorsProxy(uri, isWeb: false), uri);
    });

    test('does not proxy the proxy endpoint recursively', () {
      final uri = Uri.parse(webCorsProxyBaseUrl);
      expect(withWebCorsProxy(uri, isWeb: true), uri);
    });

    test('does not proxy the GitHub API', () {
      final uri = Uri.parse(
        'https://api.github.com/repos/NPP-exe/Harmony-Music/releases/latest',
      );
      expect(withWebCorsProxy(uri, isWeb: true), uri);
    });
  });
}
