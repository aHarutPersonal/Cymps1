import 'dart:async';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/app/router.dart';
import 'package:cmpys/features/auth/presentation/auth_screen.dart';
import 'package:go_router/go_router.dart';
import 'support/design_capture.dart';
import 'package:cmpys/features/auth/data/password_recovery_repository.dart';
import 'package:cmpys/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Inert fixtures, accepted only by the in-memory test repository.
final _code = List.filled(43, 'a').join();
const _password = 'FixturePass7!';

class RecoveryRepository extends Fake implements PasswordRecoveryRepository {
  bool available = true;
  Object? availabilityError;
  Object? requestError;
  Object? confirmError;
  Completer<void>? requestGate;
  int checks = 0, requests = 0, confirmations = 0;
  String? requestedEmail;
  String? submittedCode;
  String? submittedPassword;

  @override
  Future<bool> isAvailable() async {
    checks++;
    if (availabilityError != null) throw availabilityError!;
    return available;
  }

  @override
  Future<void> requestCode(String email) async {
    requests++;
    requestedEmail = email;
    if (requestGate != null) await requestGate!.future;
    if (requestError != null) throw requestError!;
  }

  @override
  Future<void> confirm({
    required String token,
    required String password,
  }) async {
    confirmations++;
    submittedCode = token;
    submittedPassword = password;
    if (confirmError != null) throw confirmError!;
  }
}

Future<void> mount(
  WidgetTester tester,
  RecoveryRepository repository, {
  DateTime Function()? now,
  void Function(bool?)? returned,
  double width = 430,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        passwordRecoveryRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ForgotPasswordScreen(now: now),
                  ),
                );
                returned?.call(result);
              },
              child: const Text('Sign in'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
}

Future<void> fillReset(
  WidgetTester tester, {
  String? code,
  String? password,
  String? confirmation,
}) async {
  await enter(tester, 'recovery-code', code ?? _code);
  await enter(tester, 'recovery-password', password ?? _password);
  await enter(
    tester,
    'recovery-confirmation',
    confirmation ?? password ?? _password,
  );
}

void main() {
  setUpAll(prepareDesignCapture);

  testWidgets(
    'successful recovery returns to the real sign-in form without the old password',
    (tester) async {
      final repo = RecoveryRepository();
      final router = GoRouter(
        initialLocation: AppRoutes.auth,
        routes: [
          GoRoute(path: AppRoutes.auth, builder: (_, _) => const AuthScreen()),
          GoRoute(
            path: AppRoutes.forgotPassword,
            builder: (_, _) => const ForgotPasswordScreen(),
          ),
        ],
      );
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            passwordRecoveryRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'I already have an account');
      await tester.enterText(find.byType(TextField).at(0), 'qa@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'OldFixture7!');
      await tap(tester, 'Forgot Password?');
      await tap(tester, 'Enter recovery code');
      await fillReset(tester);
      await tap(tester, 'Update password');
      await tap(tester, 'Back to sign in');
      expect(find.text('Sign In'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.controller?.text, 'qa@example.com');
      expect(fields.last.controller?.text, isEmpty);
    },
  );

  testWidgets('unavailable recovery never claims to send an email', (
    tester,
  ) async {
    final repo = RecoveryRepository()..available = false;
    await mount(tester, repo);
    expect(
      find.text('Password reset by email is not available yet.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(repo.requests, 0);
    expect(find.textContaining('will arrive shortly'), findsNothing);
    expect(find.text('Enter recovery code'), findsOneWidget);
  });

  testWidgets('availability failure can be retried without claiming delivery', (
    tester,
  ) async {
    final repo = RecoveryRepository()..availabilityError = const NetworkError();
    await mount(tester, repo);
    expect(
      find.textContaining('Couldn’t check email recovery'),
      findsOneWidget,
    );
    repo.availabilityError = null;
    await tap(tester, 'Check again');
    expect(repo.checks, 2);
    expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
    expect(repo.requests, 0);
  });

  testWidgets(
    'email validation and accepted request use neutral confirmation',
    (tester) async {
      final repo = RecoveryRepository();
      await mount(tester, repo);
      await enter(tester, 'recovery-email', 'invalid');
      await tap(tester, 'Request recovery code');
      expect(repo.requests, 0);
      await enter(tester, 'recovery-email', ' unknown@example.com ');
      await tap(tester, 'Request recovery code');
      expect(repo.requestedEmail, 'unknown@example.com');
      expect(
        find.text(
          'If an account uses this email, a recovery code will arrive shortly.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recovery-code')), findsOneWidget);
      expect(find.text('Password updated'), findsNothing);
    },
  );

  testWidgets('unavailable request never advances or claims delivery', (
    tester,
  ) async {
    final repo = RecoveryRepository()
      ..requestError = const ApiError(message: 'disabled', statusCode: 503);
    await mount(tester, repo);
    await enter(tester, 'recovery-email', 'qa@example.com');
    await tap(tester, 'Request recovery code');
    expect(find.textContaining('currently unavailable'), findsOneWidget);
    expect(find.textContaining('will arrive shortly'), findsNothing);
    expect(find.byKey(const ValueKey('recovery-code')), findsNothing);
  });

  testWidgets('duplicate requests and resends wait for cooldown', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 4);
    final gate = Completer<void>();
    final repo = RecoveryRepository()..requestGate = gate;
    await mount(tester, repo, now: () => now);
    await enter(tester, 'recovery-email', 'qa@example.com');
    await tap(tester, 'Request recovery code');
    await tap(tester, 'Requesting code…');
    expect(repo.requests, 1);
    gate.complete();
    await tester.pumpAndSettle();
    await tap(tester, 'Request another code in 1:00');
    expect(repo.requests, 1);
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, 'Request another code');
    expect(repo.requests, 2);
  });

  testWidgets('manual code remains usable when sending is unavailable', (
    tester,
  ) async {
    final repo = RecoveryRepository()..available = false;
    bool? returned;
    await mount(tester, repo, returned: (value) => returned = value);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester);
    for (final key in [
      'recovery-code',
      'recovery-password',
      'recovery-confirmation',
    ]) {
      expect(
        tester.widget<TextFormField>(find.byKey(ValueKey(key))).builder,
        isNotNull,
      );
      final field = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).obscureText, isTrue);
    }
    await tap(tester, 'Update password');
    expect(repo.requests, 0);
    expect(repo.confirmations, 1);
    expect(find.text('Password updated'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tap(tester, 'Back to sign in');
    expect(returned, isTrue);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('code and Unicode password rules prevent invalid requests', (
    tester,
  ) async {
    final repo = RecoveryRepository();
    await mount(tester, repo);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester, code: '123456', password: '😀😀😀😀');
    await tap(tester, 'Update password');
    expect(repo.confirmations, 0);
    expect(
      find.text('Paste the complete recovery code from your email.'),
      findsOneWidget,
    );
    expect(find.text('Use at least 8 characters.'), findsWidgets);
    await fillReset(tester, password: List.filled(37, 'é').join());
    await tap(tester, 'Update password');
    expect(repo.confirmations, 0);
    expect(find.textContaining('This password is too long'), findsOneWidget);
    await fillReset(tester, confirmation: 'DifferentPass9!');
    await tap(tester, 'Update password');
    expect(repo.confirmations, 0);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    final boundary = List.filled(36, 'é').join();
    await fillReset(tester, code: ' $_code ', password: boundary);
    await tap(tester, 'Update password');
    expect(repo.submittedCode, _code);
    expect(repo.submittedPassword, boundary);
    expect(repo.confirmations, 1);
  });

  testWidgets('expired code keeps form recoverable without claiming success', (
    tester,
  ) async {
    final repo = RecoveryRepository()
      ..confirmError = const ApiError(
        message: 'invalid or expired',
        statusCode: 400,
      );
    await mount(tester, repo);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester);
    await tap(tester, 'Update password');
    expect(
      find.text(
        'This recovery code is invalid or expired. Request a new code.',
      ),
      findsOneWidget,
    );
    expect(find.text('Password updated'), findsNothing);
    await tap(tester, 'Request a new code or change email');
    expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
  });

  testWidgets('server confirmation limit honors retry interval', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 4);
    final repo = RecoveryRepository()
      ..confirmError = const ApiError(
        message: 'limit',
        statusCode: 429,
        retryAfterSeconds: 90,
      );
    await mount(tester, repo, now: () => now);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester);
    await tap(tester, 'Update password');
    await tap(tester, 'Try again in 1:30');
    expect(repo.confirmations, 1);
    now = now.add(const Duration(seconds: 91));
    await tester.pump(const Duration(seconds: 1));
    repo.confirmError = null;
    await tap(tester, 'Update password');
    expect(repo.confirmations, 2);
    expect(find.text('Password updated'), findsOneWidget);
  });

  testWidgets('server request limit prevents another email request', (
    tester,
  ) async {
    final repo = RecoveryRepository()
      ..requestError = const ApiError(
        message: 'limit',
        statusCode: 429,
        retryAfterSeconds: 900,
      );
    await mount(tester, repo, now: () => DateTime.utc(2026, 10, 4));
    await enter(tester, 'recovery-email', 'qa@example.com');
    await tap(tester, 'Request recovery code');
    await tap(tester, 'Try again in 15:00');
    expect(repo.requests, 1);
    expect(find.textContaining('will arrive shortly'), findsNothing);
  });

  testWidgets('uncertain confirmation remains an error and permits retry', (
    tester,
  ) async {
    final repo = RecoveryRepository()..confirmError = const TimeoutError();
    await mount(tester, repo);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester);
    await tap(tester, 'Update password');
    expect(
      find.textContaining('Couldn’t confirm the password change'),
      findsOneWidget,
    );
    expect(find.text('Password updated'), findsNothing);
    repo.confirmError = null;
    await tap(tester, 'Update password');
    expect(repo.confirmations, 2);
  });

  testWidgets('recovery forms fit narrow screens with large text', (
    tester,
  ) async {
    await mount(tester, RecoveryRepository(), width: 320, scale: 2);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester, code: 'bad', password: 'short');
    await tap(tester, 'Update password');
    expect(tester.takeException(), isNull);
    expect(
      find.text('Paste the complete recovery code from your email.'),
      findsOneWidget,
    );
  });
}
