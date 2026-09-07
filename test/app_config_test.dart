import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/config/app_config.dart';

void main() {
  test('production accepts complete HTTPS configuration', () {
    expect(
      () => AppConfig.validateValues(
        environment: AppEnvironment.production,
        apiBaseUrl: 'https://pelines-api.aiwithtalha.com/v1',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'sb_publishable_example_client_key',
      ),
      returnsNormally,
    );
  });

  for (final String unsafeUrl in <String>[
    'http://pelines-api.example.com/v1',
    'http://localhost:3000/v1',
    'https://127.0.0.1/v1',
    'https://10.0.2.2/v1',
  ]) {
    test('production rejects unsafe API URL $unsafeUrl', () {
      expect(
        () => AppConfig.validateValues(
          environment: AppEnvironment.production,
          apiBaseUrl: unsafeUrl,
          supabaseUrl: 'https://example.supabase.co',
          supabaseAnonKey: 'sb_publishable_example_client_key',
        ),
        throwsStateError,
      );
    });
  }

  test('development still accepts local HTTPS-independent configuration', () {
    expect(
      () => AppConfig.validateValues(
        environment: AppEnvironment.development,
        apiBaseUrl: 'http://localhost:3000/v1',
        supabaseUrl: 'http://localhost:54321',
        supabaseAnonKey: 'local-client-key',
      ),
      returnsNormally,
    );
  });

  test('production rejects placeholder Supabase keys', () {
    expect(
      () => AppConfig.validateValues(
        environment: AppEnvironment.production,
        apiBaseUrl: 'https://pelines-api.aiwithtalha.com/v1',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'replace-me',
      ),
      throwsStateError,
    );
  });

  test('missing client configuration fails clearly', () {
    expect(
      () => AppConfig.validateValues(
        environment: AppEnvironment.production,
        apiBaseUrl: '',
        supabaseUrl: '',
        supabaseAnonKey: '',
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message.toString(),
          'message',
          contains('API_BASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY'),
        ),
      ),
    );
  });
}
