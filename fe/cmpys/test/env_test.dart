import 'package:cmpys/app/env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release configuration requires an explicit API base URL', () {
    expect(
      () => Env.resolveApiBaseUrl(
        definedUrl: '',
        isRelease: true,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      throwsA(isA<StateError>()),
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
      Env.apiBaseUrlIosSimulator,
    );
  });
}
