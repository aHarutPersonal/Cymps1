import 'package:flutter/foundation.dart';

/// Environment configuration for the CMPYS app.
///
/// ## Usage
///
/// Access the API base URL:
/// ```dart
/// import 'package:cmpys/app/env.dart';
///
/// final url = Env.apiBaseUrl;
/// ```
///
/// ## Override via dart-define
///
/// You can override the API base URL at build time:
/// ```bash
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
/// ```
///
/// ## Platform-specific defaults
///
/// - **iOS Simulator**: Uses `http://localhost:8000` (connects to host machine)
/// - **Android Emulator**: Uses `http://10.0.2.2:8000` (special alias for host)
/// - **Physical devices**: Uses production URL or requires override
///
abstract final class Env {
  /// API base URL from dart-define, or platform-specific default.
  static String get apiBaseUrl {
    const definedUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    return resolveApiBaseUrl(
      definedUrl: definedUrl,
      isRelease: kReleaseMode,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
  }

  /// Resolve the API URL without ever shipping an emulator/development fallback
  /// in a release build. Keeping this pure makes the release guard testable in
  /// the normal debug test runner.
  @visibleForTesting
  static String resolveApiBaseUrl({
    required String definedUrl,
    required bool isRelease,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    final configured = definedUrl.trim();
    if (configured.isNotEmpty) return configured;
    if (isRelease) {
      throw StateError(
        'API_BASE_URL is required for release builds. '
        'Build with --dart-define=API_BASE_URL=https://…',
      );
    }
    if (isWeb) return apiBaseUrlIosSimulator;
    if (platform == TargetPlatform.android) return apiBaseUrlAndroidEmulator;
    return apiBaseUrlProduction;
  }

  /// Development API base URL based on platform.
  ///
  /// - iOS Simulator: localhost points to host machine
  /// - Android Emulator: 10.0.2.2 is special alias for host machine
  /// - Web: localhost works directly
  /// API base URL for iOS Simulator (localhost works directly).
  static const String apiBaseUrlIosSimulator = 'http://localhost:8000/api/v1';

  /// API base URL for Android Emulator (10.0.2.2 maps to host localhost).
  static const String apiBaseUrlAndroidEmulator = 'http://10.0.2.2:8000/api/v1';

  /// Production API base URL.
  static const String apiBaseUrlProduction = 'http://54.158.122.215/api/v1';

  /// Whether the app is running in debug mode.
  static bool get isDebug => kDebugMode;

  /// Whether to enable verbose logging.
  static const bool _loggingRequested = bool.fromEnvironment(
    'ENABLE_LOGGING',
    defaultValue: true,
  );

  /// Diagnostic request logging is compiled out of release/profile builds even
  /// if a stale build script passes ENABLE_LOGGING=true.
  static bool get enableLogging => kDebugMode && _loggingRequested;

  /// App flavor (dev, staging, prod).
  static const String flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  /// Check if running in production.
  static bool get isProduction => flavor == 'prod';

  /// Check if running in staging.
  static bool get isStaging => flavor == 'staging';

  /// Check if running in development.
  static bool get isDevelopment => flavor == 'dev';
}
