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
    'staging' => AppEnvironment.staging,
    'production' => AppEnvironment.production,
    _ => AppEnvironment.development,
  };

  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void validate() {
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
  }
}
