import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/account/data/account_repository.dart';
import 'package:pelines_admin_app/features/auth/data/auth_repository.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

Session _session({
  bool expired = false,
  String id = 'staff-a',
  int revision = 0,
}) {
  final expires = DateTime.now().add(Duration(hours: expired ? -1 : 1));
  final claims = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': expires.millisecondsSinceEpoch ~/ 1000,
            'revision': revision,
          }),
        ),
      )
      .replaceAll('=', '');
  return Session(
    accessToken: 'test.$claims.signature',
    refreshToken: 'refresh-fixture',
    tokenType: 'bearer',
    user: User(
      id: id,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    ),
  );
}

class _Auth extends GoTrueClient {
  _Auth() : super(autoRefreshToken: false);
  Session? session = _session();
  final events = StreamController<AuthState>.broadcast();
  Future<void> Function()? beforeRefresh;
  bool revoked = false;
  bool offline = false;
  int refreshes = 0;

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async {
    refreshes++;
    final previous = session;
    await beforeRefresh?.call();
    if (offline) {
      final error = AuthRetryableFetchException();
      events.addError(error);
      throw error;
    }
    if (revoked) {
      session = null;
      events.add(const AuthState(AuthChangeEvent.signedOut, null));
      throw const AuthException(
        'Session revoked',
        code: 'refresh_token_not_found',
      );
    }
    if (identical(previous, session)) {
      session = _session(id: previous!.user.id, revision: refreshes);
      events.add(AuthState(AuthChangeEvent.tokenRefreshed, session));
    }
    return AuthResponse(session: session);
  }
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int Function(RequestOptions)? status;
  Future<void> Function()? beforeResponse;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? data,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await beforeResponse?.call();
    return ResponseBody.fromString(
      '{"id":"staff-a","role":"admin","createdAt":"2026-01-01","updatedAt":"2026-01-01"}',
      status?.call(options) ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Auth auth;
  late SupabaseAuthRepository repository;
  late _Adapter adapter;
  late Dio dio;
  late ApiClient client;

  setUp(() {
    auth = _Auth();
    repository = SupabaseAuthRepository.withAuth(auth);
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
      ..httpClientAdapter = adapter;
    client = ApiClient(
      dio: dio,
      accessTokenProvider: repository.getAccessToken,
      recoverToken: repository.recoverRejectedToken,
      sessionScope: () => auth.session?.user.id,
    );
  });

  tearDown(() async {
    dio.close();
    await auth.events.close();
    auth.dispose();
  });

  test(
    'expired restored session holds concurrent API requests for one refresh',
    () async {
      auth.session = _session(expired: true);
      final restoration = Completer<void>();
      final started = Completer<void>();
      auth.beforeRefresh = () {
        started.complete();
        return restoration.future;
      };
      final reads = Future.wait([
        dio.get<dynamic>('me'),
        dio.get<dynamic>('locations'),
      ]);
      await started.future;
      expect(adapter.requests, isEmpty);
      restoration.complete();
      await reads;
      expect(auth.refreshes, 1);
      expect(adapter.requests.length, 2);
      final sentCurrent = adapter.requests.every(
        (request) =>
            request.headers['Authorization'] ==
            'Bearer ${auth.session!.accessToken}',
      );
      expect(sentCurrent, isTrue);
    },
  );

  test(
    'concurrent 401 reads recover once, PATCH protocol never replays',
    () async {
      final old = auth.session!.accessToken;
      adapter.status = (request) =>
          request.headers['Authorization'] == 'Bearer $old' ? 401 : 200;
      final write = expectLater(
        dio.patch<dynamic>('orders/1/status'),
        throwsA(isA<DioException>()),
      );
      await Future.wait([
        dio.get<dynamic>('me'),
        dio.get<dynamic>('orders'),
        write,
      ]);
      expect(auth.refreshes, 1);
      expect(
        adapter.requests.where((request) => request.method == 'PATCH').length,
        1,
      );
      expect(
        adapter.requests.where((request) => request.method == 'GET').length,
        4,
      );
      expect(auth.session, isNotNull);
    },
  );

  test('rejected fresh token stops at one retry without logout', () async {
    adapter.status = (_) => 401;
    for (var i = 0; i < 2; i++) {
      await expectLater(
        dio.get<dynamic>('orders'),
        throwsA(isA<DioException>()),
      );
    }
    expect(auth.refreshes, 1);
    expect(adapter.requests.length, 3);
    expect(auth.session, isNotNull);
  });

  test('403 and server 500 do not refresh or clear the session', () async {
    for (final code in [403, 500]) {
      adapter.status = (_) => code;
      await expectLater(
        dio.get<dynamic>('orders'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            code,
          ),
        ),
      );
    }
    expect(auth.refreshes, 0);
    expect(auth.session, isNotNull);
  });

  test('transient failure retains session and next read recovers', () async {
    auth.session = _session(expired: true);
    auth.offline = true;
    // The production AuthController consumes this SDK stream error.
    final subscription = auth.events.stream.listen(
      (_) {},
      onError: (Object _) {},
    );
    addTearDown(subscription.cancel);
    await expectLater(
      dio.get<dynamic>('orders'),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.connectionError,
        ),
      ),
    );
    expect(auth.session, isNotNull);
    expect(adapter.requests, isEmpty);
    auth.offline = false;
    expect((await dio.get<dynamic>('orders')).statusCode, 200);
  });

  test(
    'definitive expiry clears admin state and stops protected requests',
    () async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          accountRepositoryProvider.overrideWithValue(
            ApiAccountRepository(client),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(authControllerProvider.future), isNotNull);
      auth.revoked = true;
      adapter.status = (_) => 401;
      await expectLater(
        dio.get<dynamic>('orders'),
        throwsA(isA<DioException>()),
      );
      await container.pump();
      expect(container.read(authControllerProvider).value, isNull);
      expect(auth.session, isNull);
      final count = adapter.requests.length;
      await expectLater(
        dio.get<dynamic>('orders'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests.length, count);
    },
  );

  test(
    'bootstrap error clears after tokenRefreshed without another sign-in',
    () async {
      auth.session = _session(expired: true);
      auth.offline = true;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          accountRepositoryProvider.overrideWithValue(
            ApiAccountRepository(client),
          ),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(authControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(auth.session, isNotNull);
      expect(adapter.requests, isEmpty);
      auth.offline = false;
      await auth.refreshSession();
      await container.pump();
      expect(await container.read(authControllerProvider.future), isNotNull);
      expect(container.read(authControllerProvider).hasError, isFalse);
      expect(adapter.requests.length, 1);
    },
  );

  test(
    '401 for old account cannot refresh or retry under a different account',
    () async {
      final send = Completer<void>();
      final entered = Completer<void>();
      adapter.status = (_) => 401;
      adapter.beforeResponse = () {
        entered.complete();
        return send.future;
      };
      final read = expectLater(
        dio.get<dynamic>('orders'),
        throwsA(isA<DioException>()),
      );
      await entered.future;
      auth.session = _session(id: 'staff-b', revision: 2);
      send.complete();
      await read;
      expect(auth.refreshes, 0);
      expect(adapter.requests.length, 1);
    },
  );
}
