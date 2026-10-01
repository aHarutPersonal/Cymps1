import 'dart:convert';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/controllers/auth_controller.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/data/auth_repository.dart';
import 'package:cmpys/features/auth/data/me_repository.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileRepo extends MeRepository {
  _ProfileRepo(TokenStore store)
    : super(dioClient: DioClient(tokenStore: store));
  bool expired = false;
  @override
  Future<Me> getMe() async {
    if (expired) throw const ApiError(message: 'expired', statusCode: 401);
    return const Me(id: 'account-b', email: 'b@example.test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      SessionKeys.accountId: 'account-a',
      SessionKeys.onboardingComplete: true,
      SessionKeys.currentIdolId: 'old-mentor',
    });
  });

  test(
    'existing account switch clears old local data before routing',
    () async {
      final tokens = TokenStore();
      final auth = AuthController(
        tokenStore: tokens,
        authRepository: AuthRepository(
          dioClient: DioClient(tokenStore: tokens),
          tokenStore: tokens,
        ),
      );
      var resets = 0;
      final controller = SessionController(
        tokenStore: tokens,
        meRepository: _ProfileRepo(tokens),
        authController: auth,
        resetLocalAccountData: () async {
          resets++;
        },
      );
      await controller.onAuthenticated();
      final prefs = await SharedPreferences.getInstance();
      expect(resets, 1);
      expect(prefs.getString(SessionKeys.accountId), 'account-b');
      expect(prefs.getBool(SessionKeys.onboardingComplete), isNull);
      expect(controller.state, isA<SessionNeedsOnboarding>());
      controller.dispose();
      auth.dispose();
    },
  );

  test('expired session clears account data and credentials', () async {
    final tokens = TokenStore();
    await tokens.saveTokens(
      accessToken: 'expired',
      refreshToken: 'expired-refresh',
    );
    final auth = AuthController(
      tokenStore: tokens,
      authRepository: AuthRepository(
        dioClient: DioClient(tokenStore: tokens),
        tokenStore: tokens,
      ),
    );
    var resets = 0;
    final controller = SessionController(
      tokenStore: tokens,
      meRepository: _ProfileRepo(tokens)..expired = true,
      authController: auth,
      resetLocalAccountData: () async {
        resets++;
      },
    );
    await controller.onAuthenticated();
    expect(resets, 1);
    expect(await tokens.readAccessToken(), isNull);
    expect(await tokens.readRefreshToken(), isNull);
    expect(controller.state, isA<SessionUnauthenticated>());
    controller.dispose();
    auth.dispose();
  });

  test('reset during initial hydration cannot restore old notes', () async {
    SharedPreferences.setMockInitialValues({
      'cmpys_store_v1': jsonEncode({
        'notes': [
          {
            'id': 'a',
            'kind': 'read',
            'title': 'Private note',
            'body': 'Account A',
          },
        ],
        'user': {'name': 'Account A'},
      }),
    });
    final store = CmpysStore();
    await store.reset();
    await store.ready;
    expect(store.state.notes, isEmpty);
    expect(store.state.user.name, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cmpys_store_v1'), isNull);
    store.dispose();
  });
}
