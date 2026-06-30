class AppConfig {
  const AppConfig._();

  /// Dans l'APK du Play Store, ce flag sera compilé à false afin que les
  /// outils de test ne soient pas simplement cachés, mais supprimés du build.
  static const bool developerToolsAvailable = bool.fromEnvironment(
    'RUEDEX_DEV_TOOLS',
    defaultValue: true,
  );

  /// Ces valeurs sont injectées par GitHub Actions avec des Secrets.
  /// Si elles sont vides, RueDex reste en mode local/offline.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get supabaseConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}
