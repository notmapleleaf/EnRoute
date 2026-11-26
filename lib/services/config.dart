/// Build-time configuration.
///
/// Run with a key to use the real Google APIs:
///   flutter run --dart-define=GOOGLE_API_KEY=your_key
/// Without a key the app runs on built-in sample data.
class AppConfig {
  const AppConfig._();

  static const String googleApiKey =
      String.fromEnvironment('GOOGLE_API_KEY', defaultValue: '');

  /// Force sample data even when a key is present:
  ///   --dart-define=USE_MOCK=true
  static const bool forceMock = bool.fromEnvironment('USE_MOCK');

  static bool get useMock => forceMock || googleApiKey.isEmpty;
}
