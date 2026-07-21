import 'package:cmpys/app/env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release configuration defaults to the deployed API', () {
    expect(
      Env.resolveApiBaseUrl(
        definedUrl: '',
        isRelease: true,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      Env.apiBaseUrlProduction,
    );

    expect(
      Env.resolveApiBaseUrl(
        definedUrl: ' https://api.cmpys.example/v1 ',
        isRelease: true,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      'https://api.cmpys.example/v1',
    );
  });

  test('debug configuration retains platform development defaults', () {
    expect(
      Env.resolveApiBaseUrl(
        definedUrl: '',
        isRelease: false,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      Env.apiBaseUrlAndroidEmulator,
    );
    expect(
      Env.resolveApiBaseUrl(
        definedUrl: '',
        isRelease: false,
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      Env.apiBaseUrlLocalhost,
    );
    expect(
      Env.resolveApiBaseUrl(
        definedUrl: '',
        isRelease: false,
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      Env.apiBaseUrlProduction,
    );
    expect(
      Env.resolveApiBaseUrl(
        definedUrl: '',
        isRelease: false,
        isWeb: false,
        platform: TargetPlatform.macOS,
      ),
      Env.apiBaseUrlLocalhost,
    );
  });
}
