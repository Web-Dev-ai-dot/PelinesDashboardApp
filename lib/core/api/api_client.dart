import 'package:dio/dio.dart';

import '../config/app_config.dart';

typedef AccessTokenProvider = Future<String?> Function();
typedef TokenRecovery = Future<String?> Function(String rejectedToken);

class ApiClient {
  ApiClient({
    Dio? dio,
    AccessTokenProvider? accessTokenProvider,
    TokenRecovery? recoverToken,
    Object? Function()? sessionScope,
  }) : dio =
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
    if (accessTokenProvider == null) return;
    const scopeKey = 'pelines.sessionScope';
    const retryKey = 'pelines.authRetried';
    const authHeader = 'Authorization';

    bool sameScope(RequestOptions options) =>
        sessionScope == null ||
        (options.extra[scopeKey] != null &&
            options.extra[scopeKey] == sessionScope());
    DioException unavailable(RequestOptions options) => DioException(
      requestOptions: options,
      type: DioExceptionType.cancel,
      message: 'An authenticated session is required.',
    );
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.extra.putIfAbsent(scopeKey, () => sessionScope?.call());
          if (!sameScope(options)) {
            handler.reject(unavailable(options));
            return;
          }
          try {
            final token = await accessTokenProvider();
            if (token == null || token.isEmpty || !sameScope(options)) {
              handler.reject(unavailable(options));
              return;
            }
            options.headers[authHeader] = 'Bearer $token';
            handler.next(options);
          } on Object {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                message:
                    'The session could not be refreshed. Please try again.',
              ),
            );
          }
        },
        onResponse: (response, handler) {
          if (!sameScope(response.requestOptions)) {
            handler.reject(unavailable(response.requestOptions));
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          final header = request.headers[authHeader];
          if (!sameScope(request) ||
              recoverToken == null ||
              error.response?.statusCode != 401 ||
              request.extra[retryKey] == true ||
              header is! String ||
              !header.startsWith('Bearer ')) {
            handler.next(error);
            return;
          }
          final oldToken = header.substring(7);
          String? token;
          try {
            token = await recoverToken(oldToken);
          } on Object {
            // Keep the original failure for writes. A failed refresh never
            // changes the result of a request that already reached the API.
            if (request.method == 'GET' || request.method == 'HEAD') {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionError,
                  message:
                      'The session could not be refreshed. Please try again.',
                ),
              );
              return;
            }
          }
          if (token == null ||
              token == oldToken ||
              !sameScope(request) ||
              (request.method != 'GET' && request.method != 'HEAD')) {
            handler.next(error);
            return;
          }
          final retry = request.copyWith(
            extra: {...request.extra, retryKey: true},
          );
          try {
            final response = await this.dio.fetch<dynamic>(retry);
            handler.resolve(response);
          } on DioException catch (failure) {
            handler.next(failure);
          } on Object {
            handler.next(error);
          }
        },
      ),
    );
  }

  final Dio dio;
}
