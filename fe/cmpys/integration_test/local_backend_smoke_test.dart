// Opt-in smoke against a running loopback backend. Creates a synthetic local
// account and stores its session in the simulator Keychain. Makes no LLM calls.
import 'dart:math';

import 'package:cmpys/app/app.dart';
import 'package:cmpys/app/env.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/data/auth_repository.dart';
import 'package:cmpys/features/auth/data/me_repository.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'local API authentication and native app onboarding',
    (tester) async {
      final base = Uri.parse(Env.apiBaseUrl);
      expect(['127.0.0.1', 'localhost'], contains(base.host));
      expect(Env.enableLogging, isFalse);
      final tokens = TokenStore();
      await tokens.ensureTokenBoundTo(Env.apiBaseUrl);
      final client = DioClient(tokenStore: tokens);
      addTearDown(() => client.dio.close());
      final auth = AuthRepository(dioClient: client, tokenStore: tokens);
      final email =
          'cmpys-local-smoke-${DateTime.now().microsecondsSinceEpoch}@example.com';
      final random = Random.secure();
      final nonce = List.generate(
        32,
        (_) => random.nextInt(36).toRadixString(36),
      ).join();
      final password = 'Local7!$nonce';
      await auth.register(
        email: email,
        password: password,
        fullName: 'Local QA',
      );
      await auth.login(email: email, password: password);
      await auth.refreshToken();
      final me = await MeRepository(dioClient: client).getMe();
      expect(me.email == email, isTrue);
      expect(await PlanRepository(dioClient: client).getCurrentPlan(), isNull);
      final availability = await client.get(
        '/auth/password-reset/availability',
      );
      expect(availability.statusCode, 200);
      await tester.pumpWidget(const ProviderScope(child: App()));
      final clock = Stopwatch()..start();
      final basics = find.text('What should we call you?');
      while (basics.evaluate().isEmpty &&
          clock.elapsed < const Duration(seconds: 20)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(basics, findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint(
        'LOCAL_API_NATIVE_SMOKE passed: register, login, refresh, profile, '
        'current plan, recovery availability and real app onboarding. No LLM calls.',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    skip: !const bool.fromEnvironment('LOCAL_BACKEND_PROBE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
