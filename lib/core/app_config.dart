class AppConfig {
  AppConfig._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'YOUR_SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );
  static const String gcpCloudProjectNumber = String.fromEnvironment(
    'GCP_CLOUD_PROJECT_NUMBER',
    defaultValue: 'YOUR_GCP_CLOUD_PROJECT_NUMBER',
  );
  static const bool strictIntegrityCheck =
      bool.fromEnvironment('STRICT_INTEGRITY_CHECK', defaultValue: true);

  static const bool isSupabaseConfigured = supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY';

  static int? get cloudProjectNumber => int.tryParse(gcpCloudProjectNumber);
}
