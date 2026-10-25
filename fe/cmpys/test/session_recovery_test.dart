import 'package:cmpys/app/env.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/controllers/auth_controller.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/data/auth_repository.dart';
import 'package:cmpys/features/auth/data/me_repository.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileRepo extends MeRepository {
  ProfileRepo(TokenStore store)
    : super(dioClient: DioClient(tokenStore: store));
  bool fail = false;
  int calls = 0;
  @override
  Future<Me> getMe() async {
    calls++;
    if (fail) throw const NetworkError();
    return const Me(id: 'test-user', email: 'test@example.test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      SessionKeys.onboardingComplete: true,
    }),
  );
  test(
    'startup uses stored session even when access expiry has passed',
    () async {
      final store = TokenStore();
      await store.saveTokens(
        accessToken: 'expired',
        refreshToken: 'refresh',
        expiry: DateTime(2020),
        apiBase: Env.apiBaseUrl,
      );
      final repo = ProfileRepo(store);
      final auth = AuthController(
        tokenStore: store,
        authRepository: AuthRepository(
          dioClient: DioClient(tokenStore: store),
          tokenStore: store,
        ),
      );
      final controller = SessionController(
        tokenStore: store,
        meRepository: repo,
        authController: auth,
      );
      await controller.initialize();
      expect(repo.calls, 1);
      expect(controller.state, isA<SessionReady>());
      controller.dispose();
      auth.dispose();
    },
  );
  test(
    'profile outage keeps saved work and can recover without onboarding',
    () async {
      final store = TokenStore();
      await store.saveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        apiBase: Env.apiBaseUrl,
      );
      final repo = ProfileRepo(store)..fail = true;
      final auth = AuthController(
        tokenStore: store,
        authRepository: AuthRepository(
          dioClient: DioClient(tokenStore: store),
          tokenStore: store,
        ),
      );
      final controller = SessionController(
        tokenStore: store,
        meRepository: repo,
        authController: auth,
      );
      await controller.onAuthenticated();
      expect(controller.state, isA<SessionError>());
      expect(await store.readRefreshToken(), 'refresh');
      repo.fail = false;
      await controller.initialize();
      expect(controller.state, isA<SessionReady>());
      controller.dispose();
      auth.dispose();
    },
  );
  test('new token without expiresIn does not inherit old expiry', () async {
    final store = TokenStore();
    await store.saveTokens(accessToken: 'old', expiry: DateTime(2020));
    await store.saveTokens(accessToken: 'new');
    expect(await store.hasValidToken(), isTrue);
    expect(await store.readTokenExpiry(), isNull);
  });
}
