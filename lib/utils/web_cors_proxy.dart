import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const webCorsProxyBaseUrl = 'https://cors-anywhere-py9w.onrender.com/';

Uri withWebCorsProxy(Uri uri, {bool? isWeb}) {
  if (!(isWeb ?? kIsWeb) ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host == Uri.parse(webCorsProxyBaseUrl).host ||
      uri.host == 'api.github.com' ||
      uri.host.contains('lrclib.net') ||
      uri.host.contains('chocolatemoo53.com') ||
      uri.host.contains('invidious')) {
    return uri;
  }

  return Uri.parse('$webCorsProxyBaseUrl$uri');
}

Dio createWebAwareDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final requestUri = Uri.tryParse(options.path);
        if (requestUri != null) {
          final proxiedUri = withWebCorsProxy(requestUri);
          if (proxiedUri != requestUri) {
            options.path = proxiedUri.toString();
          }
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}
