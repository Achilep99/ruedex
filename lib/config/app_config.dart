class AppConfig {
  const AppConfig._();

  /// Dans l'APK du Play Store, ce flag sera compilé à false afin que les
  /// outils de test ne soient pas simplement cachés, mais supprimés du build.
  static const bool developerToolsAvailable = bool.fromEnvironment(
    'RUEDEX_DEV_TOOLS',
    defaultValue: true,
  );
}
