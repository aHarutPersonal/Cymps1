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

/// Answers /me as whichever account [id] names, or 401 while [expired].
class _SwitchingRepo extends MeRepository {
  _SwitchingRepo(TokenStore store)
    : super(dioClient: DioClient(tokenStore: store));
  String id = 'account-a';
  bool expired = false;
  @override
  Future<Me> getMe() async {
    if (expired) throw const ApiError(message: 'expired', statusCode: 401);
    return Me(id: id, email: '$id@example.test');
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

  AuthController authFor(TokenStore tokens) => AuthController(
    tokenStore: tokens,
    authRepository: AuthRepository(
      dioClient: DioClient(tokenStore: tokens),
      tokenStore: tokens,
    ),
  );

  test('an account switch opens the new account and keeps the old one’s '
      'data (owner decision 2)', () async {
    final tokens = TokenStore();
    final auth = authFor(tokens);
    var resets = 0;
    var closes = 0;
    final opened = <(String, String?)>[];
    final controller = SessionController(
      tokenStore: tokens,
      meRepository: _ProfileRepo(tokens),
      authController: auth,
      resetLocalAccountData: () async => resets++,
      openLocalAccount: (id, owner) async => opened.add((id, owner)),
      closeLocalAccount: () async => closes++,
    );
    await controller.onAuthenticated();
    final prefs = await SharedPreferences.getInstance();
    // Nothing is deleted: account A's data stays keyed under A, and an
    // unkeyed store from an older build belongs to A, who was signed in.
    expect(resets, 0);
    expect(opened, [('account-b', 'account-a')]);
    expect(prefs.getString(SessionKeys.accountId), 'account-b');
    // A's device flags don't carry over to B.
    expect(prefs.getBool(SessionKeys.onboardingComplete), isNull);
    expect(prefs.getString(SessionKeys.currentIdolId), isNull);
    expect(controller.state, isA<SessionNeedsOnboarding>());
    controller.dispose();
    auth.dispose();
  });

  test('an expired session (401 at start) keeps the account’s data on the '
      'device and clears the credentials', () async {
    final tokens = TokenStore();
    await tokens.saveTokens(
      accessToken: 'expired',
      refreshToken: 'expired-refresh',
    );
    final auth = authFor(tokens);
    var resets = 0;
    var closes = 0;
    final controller = SessionController(
      tokenStore: tokens,
      meRepository: _ProfileRepo(tokens)..expired = true,
      authController: auth,
      resetLocalAccountData: () async => resets++,
      openLocalAccount: (id, owner) async {},
      closeLocalAccount: () async => closes++,
    );
    await controller.onAuthenticated();
    expect(resets, 0);
    expect(closes, 1);
    expect(await tokens.readAccessToken(), isNull);
    expect(await tokens.readRefreshToken(), isNull);
    expect(controller.state, isA<SessionUnauthenticated>());
    // Whose data is on the device stays known, with its flags.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionKeys.accountId), 'account-a');
    expect(prefs.getBool(SessionKeys.onboardingComplete), isTrue);
    controller.dispose();
    auth.dispose();
  });

  test('a deliberate logout clears the account’s data', () async {
    final tokens = TokenStore();
    final auth = authFor(tokens);
    var resets = 0;
    var closes = 0;
    final controller = SessionController(
      tokenStore: tokens,
      meRepository: _ProfileRepo(tokens),
      authController: auth,
      resetLocalAccountData: () async => resets++,
      openLocalAccount: (id, owner) async {},
      closeLocalAccount: () async => closes++,
    );
    await controller.onLogout();
    expect(resets, 1);
    expect(closes, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionKeys.accountId), isNull);
    expect(prefs.getBool(SessionKeys.onboardingComplete), isNull);
    expect(controller.state, isA<SessionUnauthenticated>());
    controller.dispose();
    auth.dispose();
  });

  test('the same account signing back in after an expired session gets its '
      'data back; another account never sees it', () async {
    SharedPreferences.setMockInitialValues({});
    final tokens = TokenStore();
    final auth = authFor(tokens);
    final store = CmpysStore();
    final repo = _SwitchingRepo(tokens);
    final controller = SessionController(
      tokenStore: tokens,
      meRepository: repo,
      authController: auth,
      resetLocalAccountData: store.reset,
      openLocalAccount: (id, owner) =>
          store.openAccount(id, unkeyedOwner: owner),
      closeLocalAccount: store.closeAccount,
    );

    repo.id = 'account-a';
    await controller.onAuthenticated();
    store.saveNote(kind: 'read', title: 'A’s note', body: 'Private');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // The session expires (401 at start).
    repo.expired = true;
    await controller.refreshUser();
    expect(controller.state, isA<SessionUnauthenticated>());
    expect(store.state.notes, isEmpty);

    // Another account signs in: none of A's notes.
    repo
      ..expired = false
      ..id = 'account-b';
    await controller.onAuthenticated();
    expect(store.state.notes, isEmpty);
    await controller.onLogout();

    // A signs back in: A's notes are back.
    repo.id = 'account-a';
    await controller.onAuthenticated();
    expect(store.state.notes.single.title, 'A’s note');

    controller.dispose();
    auth.dispose();
    store.dispose();
  });

  test('reset during initial hydration cannot restore old notes', () async {
    SharedPreferences.setMockInitialValues({
      'cmpys_store_v1:account-a': jsonEncode({
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
    final opening = store.openAccount('account-a', unkeyedOwner: 'account-a');
    await store.reset();
    await opening;
    await store.ready;
    expect(store.state.notes, isEmpty);
    expect(store.state.user.name, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cmpys_store_v1:account-a'), isNull);
    store.dispose();
  });
}
