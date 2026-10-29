import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/controllers/auth_controller.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/data/auth_repository.dart';
import 'package:cmpys/features/auth/data/me_repository.dart';
import 'package:cmpys/features/auth/models/auth_models.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAuthRepository extends AuthRepository {
  _StubAuthRepository(TokenStore tokenStore)
    : super(
        dioClient: DioClient(tokenStore: tokenStore),
        tokenStore: tokenStore,
      );

  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? fullName,
  }) async => const AuthResponse(accessToken: 'new-account-token');
}

class _StubMeRepository extends MeRepository {
  _StubMeRepository(TokenStore tokenStore)
    : super(dioClient: DioClient(tokenStore: tokenStore));

  @override
  Future<Me> getMe() async => const Me(
    id: 'new-user-id',
    email: 'new@example.com',
    fullName: 'New User',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      SessionKeys.currentIdolId: 'benjamin_franklin',
      SessionKeys.onboardingComplete: true,
    });
  });

  test('registration auth state is marked as a new account', () async {
    final tokenStore = TokenStore();
    final controller = AuthController(
      authRepository: _StubAuthRepository(tokenStore),
      tokenStore: tokenStore,
    );

    await controller.register(
      email: 'new@example.com',
      password: 'secret1',
      fullName: 'New User',
    );

    final state = controller.state;
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).isNewRegistration, isTrue);
  });

  test(
    'new registration starts its own local account before routing',
    () async {
      final tokenStore = TokenStore();
      final authController = AuthController(
        authRepository: _StubAuthRepository(tokenStore),
        tokenStore: tokenStore,
      );
      var localStoreWasReset = false;
      final opened = <(String, String?)>[];
      final controller = SessionController(
        tokenStore: tokenStore,
        meRepository: _StubMeRepository(tokenStore),
        authController: authController,
        resetLocalAccountData: () async => localStoreWasReset = true,
        openLocalAccount: (id, owner) async => opened.add((id, owner)),
        closeLocalAccount: () async {},
      );

      await controller.onAuthenticated(isNewRegistration: true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SessionKeys.onboardingComplete), isNull);
      expect(prefs.getString(SessionKeys.currentIdolId), isNull);
      // The device store is per account (owner decision 2): the new
      // account opens its own, empty store, and an unkeyed store from an
      // older build (no known owner) is never adopted by it. Nothing of
      // another account's is deleted.
      expect(localStoreWasReset, isFalse);
      expect(opened, [('new-user-id', null)]);
      expect(controller.state, isA<SessionNeedsOnboarding>());
    },
  );
}
