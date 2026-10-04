// Isolated HTTP contract fixture: never sends email or changes any real account.
import 'dart:convert';
import 'dart:io';

import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/data/password_recovery_repository.dart';
import 'package:cmpys/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _FixtureTokens extends TokenStore {
  int clears = 0;
  @override
  Future<void> clear() async {
    clears++;
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(ready(), isTrue);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native recovery against an isolated HTTP contract fixture', (
    tester,
  ) async {
    var available = false;
    var requests = 0;
    var confirmations = 0;
    var returnedToSignIn = false;
    var contractPayloadsValid = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final token = List.filled(43, 'a').join();
    const password = 'FixturePass7!';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/auth/password-reset/availability':
          request.response.write(jsonEncode({'available': available}));
        case '/auth/password-reset/request':
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          contractPayloadsValid &=
              body.length == 1 && body['email'] == 'fixture@example.com';
          requests++;
          request.response.statusCode = 202;
          request.response.write('{"message":"generic"}');
        case '/auth/password-reset/confirm':
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          contractPayloadsValid &=
              body.length == 2 &&
              body['token'] == token &&
              body['password'] == password;
          confirmations++;
          if (confirmations == 1) {
            request.response.statusCode = 400;
            request.response.write('{"detail":"Invalid or expired code"}');
          } else if (confirmations == 2) {
            request.response.statusCode = 429;
            request.response.headers.set('Retry-After', '2');
            request.response.write('{"detail":"Too many attempts"}');
          } else {
            request.response.statusCode = 204;
          }
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final tokens = _FixtureTokens();
    final client = DioClient(tokenStore: tokens);
    client.dio.options.baseUrl = 'http://127.0.0.1:${server.port}';
    addTearDown(() => client.dio.close());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          passwordRecoveryRepositoryProvider.overrideWithValue(
            PasswordRecoveryRepository(client, tokenStore: tokens),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    returnedToSignIn =
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ) ==
                        true;
                  },
                  child: const Text('Sign in'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, 'Sign in');
    await _until(
      tester,
      () => find
          .text('Password reset by email is not available yet.')
          .evaluate()
          .isNotEmpty,
    );
    available = true;
    await _tap(tester, 'Check again');
    await _until(
      tester,
      () => find.byKey(const ValueKey('recovery-email')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-email')),
      'fixture@example.com',
    );
    await _tap(tester, 'Request recovery code');
    await _until(
      tester,
      () => find.byKey(const ValueKey('recovery-code')).evaluate().isNotEmpty,
    );
    for (final entry in {
      'recovery-code': token,
      'recovery-password': password,
      'recovery-confirmation': password,
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, entry.value);
    }
    await _tap(tester, 'Update password');
    await _until(
      tester,
      () => find
          .text('This recovery code is invalid or expired. Request a new code.')
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, 'Update password');
    await _until(
      tester,
      () => find
          .text('Too many attempts. Please wait before trying again.')
          .evaluate()
          .isNotEmpty,
    );
    await _until(
      tester,
      () => find.text('Update password').evaluate().isNotEmpty,
    );
    await _tap(tester, 'Update password');
    await _until(
      tester,
      () => find.text('Password updated').evaluate().isNotEmpty,
    );
    expect(requests, 1);
    expect(contractPayloadsValid, isTrue);
    expect(confirmations, 3);
    expect(tokens.clears, 1);
    await _tap(tester, 'Back to sign in');
    await _until(tester, () => returnedToSignIn);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint(
      'RECOVERY_NATIVE_CONTRACT passed: loopback HTTP only; unavailable, accepted request, invalid code, rate limit, 204 success, sign-in return. No email sent.',
    );
  });
}
