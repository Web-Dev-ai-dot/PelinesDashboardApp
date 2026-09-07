enum AppEnvironment { development, staging, production }

abstract final class AppConfig {
  static const String _environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static String get normalizedApiBaseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl : '$apiBaseUrl/';

  static AppEnvironment get environment => switch (_environment) {
    'development' => AppEnvironment.development,
    'staging' => AppEnvironment.staging,
    'production' => AppEnvironment.production,
    _ => throw StateError('Invalid APP_ENV: $_environment'),
  };

  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void validate() {
    validateValues(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
    );
  }

  static void validateValues({
    required AppEnvironment environment,
    required String apiBaseUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) {
    final List<String> missing = <String>[
      if (apiBaseUrl.isEmpty) 'API_BASE_URL',
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define values: ${missing.join(', ')}',
      );
    }
    if (environment == AppEnvironment.production) {
      _requireProductionHttps('API_BASE_URL', apiBaseUrl);
      _requireProductionHttps('SUPABASE_URL', supabaseUrl);
      final bool looksLikeClientKey =
          supabaseAnonKey.startsWith('eyJ') ||
          supabaseAnonKey.startsWith('sb_publishable_');
      if (!looksLikeClientKey || supabaseAnonKey.length < 24) {
        throw StateError(
          'SUPABASE_ANON_KEY must be a valid client anon/publishable key in production.',
        );
      }
    }
  }

  static void _requireProductionHttps(String name, String value) {
    final Uri? uri = Uri.tryParse(value);
    final String host = uri?.host.toLowerCase() ?? '';
    final bool local =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' ||
        host.endsWith('.local');
    if (uri?.scheme != 'https' || host.isEmpty || local) {
      throw StateError('$name must use a non-local HTTPS URL in production.');
    }
  }
}
