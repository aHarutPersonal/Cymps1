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

    if (definedUrl.isNotEmpty) {
      return definedUrl;
    }

    // Return platform-specific development URL
    return _devApiBaseUrl;
  }

  /// Development API base URL based on platform.
  ///
  /// - iOS Simulator: localhost points to host machine
  /// - Android Emulator: 10.0.2.2 is special alias for host machine
  /// - Web: localhost works directly
  static String get _devApiBaseUrl {
    // Web uses localhost
    if (kIsWeb) {
      return apiBaseUrlIosSimulator;
    }
    // Check target platform for mobile
    if (defaultTargetPlatform == TargetPlatform.android) {
      return apiBaseUrlAndroidEmulator;
    }
    // iOS, macOS, and other platforms use localhost
    return apiBaseUrlIosSimulator;
  }

  /// API base URL for iOS Simulator (localhost works directly).
  static const String apiBaseUrlIosSimulator = 'http://localhost:8000/api/v1';

  /// API base URL for Android Emulator (10.0.2.2 maps to host localhost).
  static const String apiBaseUrlAndroidEmulator = 'http://10.0.2.2:8000/api/v1';

  /// Production API base URL.
  static const String apiBaseUrlProduction = 'https://api.cmpys.app/api/v1';

  /// Whether the app is running in debug mode.
  static const bool isDebug = bool.fromEnvironment('DEBUG', defaultValue: true);

  /// Whether to enable verbose logging.
  static const bool enableLogging = bool.fromEnvironment(
    'ENABLE_LOGGING',
    defaultValue: true,
  );

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
