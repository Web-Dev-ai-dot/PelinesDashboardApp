import 'package:dio/dio.dart';

import '../config/app_config.dart';

typedef AccessTokenProvider = Future<String?> Function();

class ApiClient {
  ApiClient({Dio? dio, AccessTokenProvider? accessTokenProvider})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.normalizedApiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              headers: const <String, String>{'Accept': 'application/json'},
            ),
          ) {
    if (accessTokenProvider != null) {
      this.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, handler) async {
            final String? token = await accessTokenProvider();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  final Dio dio;
}
