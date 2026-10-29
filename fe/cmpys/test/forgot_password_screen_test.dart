import 'dart:async';

import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/data/password_recovery_repository.dart';
import 'package:cmpys/features/auth/presentation/auth_screen.dart';
import 'package:cmpys/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/design_capture.dart';

// CMPYS v3 recovery (`v3/onboard.jsx` Recovery + CodeBoxes): a three-step
// sheet opened from "Forgot password?". The steps map onto the real API:
// availability + request (step 1), confirm with the emailed code and the new
// password (step 2), done (step 3). The server's recovery code is a
// 43-character token that the user pastes, not the design's 6 digits, so the
// sheet takes the token in a text field and keeps the design's copy and look
// everywhere the difference does not matter.

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
  String email = '',
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
                final result = await showRecoverySheet(
                  context,
                  email: email,
                  now: now,
                );
                returned?.call(result);
              },
              child: const Text('Open recovery'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open recovery'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Finder input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

String? fieldError(WidgetTester tester, String key) =>
    tester.widget<V3Field>(find.byKey(ValueKey(key))).error;

Future<void> enter(WidgetTester tester, String key, String value) async {
  final field = input(key);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
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

  testWidgets('recovery_sheet_three_steps', (tester) async {
    final repo = RecoveryRepository();
    bool? returned;
    await mount(
      tester,
      repo,
      email: 'ada@example.com',
      returned: (value) => returned = value,
    );

    // Step 1 — Reset your password.
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Email recovery is available'), findsOneWidget);
    expect(find.text('Account email'), findsOneWidget);
    expect(
      tester.widget<TextField>(input('recovery-email')).controller?.text,
      'ada@example.com',
    );
    await tap(tester, 'Send recovery code');
    expect(repo.requests, 1);
    expect(repo.requestedEmail, 'ada@example.com');

    // Step 2 — Check your email.
    expect(find.text('Reset your password'), findsNothing);
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'If an account uses ada@example.com, a recovery code is on its way. '
        'It expires in 20 minutes.',
      ),
      findsOneWidget,
    );
    expect(find.text('Recovery code'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm new password'), findsOneWidget);
    expect(find.text('Resend code'), findsOneWidget);
    await fillReset(tester);
    await tap(tester, 'Update password');
    expect(repo.confirmations, 1);
    expect(repo.submittedCode, _code);
    expect(repo.submittedPassword, _password);

    // Step 3 — Password updated.
    expect(find.text('Check your email'), findsNothing);
    expect(find.text('Password updated'), findsOneWidget);
    expect(find.text('Sign in with your new password.'), findsOneWidget);
    expect(find.byType(V3Burst), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tap(tester, 'Back to sign in');
    expect(returned, isTrue);
    expect(find.text('Password updated'), findsNothing);
  });

  testWidgets('code_boxes_accept_digits_only', (tester) async {
    var value = '';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Padding(
                padding: const EdgeInsets.all(20),
                child: CodeBoxes(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              );
            },
          ),
        ),
      ),
    );
    final field = find.descendant(
      of: find.byType(CodeBoxes),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).keyboardType, TextInputType.number);

    // Letters, punctuation and spaces are dropped; six digits at most.
    await tester.enterText(field, '12a-4 5b6789');
    await tester.pump();
    expect(value, '124567');
    for (final digit in ['1', '2', '4', '5', '6', '7']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.text('8'), findsNothing);
    expect(find.text('9'), findsNothing);

    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(value, '');

    // The active box is the one after the last digit; the others sit on hair.
    await tester.enterText(field, '98');
    await tester.pump();
    expect(value, '98');
    Color border(int i) =>
        ((tester
                            .widget<AnimatedContainer>(
                              find.byKey(ValueKey('code-box-$i')),
                            )
                            .decoration
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(border(2), const Color(0xFF17151A));
    expect(border(0), const Color(0xFFE6E0D6));
    expect(border(3), const Color(0xFFE6E0D6));

    // A parent that clears the value (a resend) clears the hidden input too.
    update(() => value = '');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text, '');
    expect(find.text('9'), findsNothing);
    expect(border(0), const Color(0xFF17151A));
  });

  testWidgets('code boxes expose one labelled input to screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeBoxes(value: '12', onChanged: _ignore),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Recovery code'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the address and the code are never autocorrected', (
    tester,
  ) async {
    final repo = RecoveryRepository();
    await mount(tester, repo);
    TextField field(String key) => tester.widget<TextField>(input(key));
    expect(field('recovery-email').autocorrect, isFalse);
    expect(field('recovery-email').enableSuggestions, isFalse);

    await tap(tester, 'Enter recovery code');
    for (final key in [
      'recovery-code',
      'recovery-password',
      'recovery-confirmation',
    ]) {
      expect(field(key).autocorrect, isFalse, reason: key);
      expect(field(key).enableSuggestions, isFalse, reason: key);
    }
  });

  testWidgets('a tap outside the fields dismisses the keyboard', (
    tester,
  ) async {
    await mount(tester, RecoveryRepository());
    await tap(tester, 'Enter recovery code');
    final code = input('recovery-code');
    await tester.tap(code);
    await tester.pump();
    expect(tester.widget<TextField>(code).focusNode!.hasFocus, isTrue);
    await tester.tap(find.text('Check your email'));
    await tester.pump();
    expect(tester.widget<TextField>(code).focusNode!.hasFocus, isFalse);
  });

  testWidgets('unavailable recovery never claims to send an email', (
    tester,
  ) async {
    final repo = RecoveryRepository()..available = false;
    await mount(tester, repo);
    expect(
      find.text('Password reset by email is not available yet.'),
      findsOneWidget,
    );
    expect(find.text('Email recovery is available'), findsNothing);
    expect(find.byKey(const ValueKey('recovery-email')), findsNothing);
    expect(repo.requests, 0);
    expect(find.textContaining('on its way'), findsNothing);
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
    expect(find.text('Email recovery is available'), findsOneWidget);
    expect(repo.requests, 0);
  });

  testWidgets('send stays disabled until the email looks valid and trims it', (
    tester,
  ) async {
    final repo = RecoveryRepository();
    await mount(tester, repo);
    await enter(tester, 'recovery-email', 'invalid');
    await tester.tap(find.text('Send recovery code'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.requests, 0);
    await enter(tester, 'recovery-email', ' unknown@example.com ');
    await tap(tester, 'Send recovery code');
    expect(repo.requestedEmail, 'unknown@example.com');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Password updated'), findsNothing);
  });

  testWidgets('unavailable request never advances or claims delivery', (
    tester,
  ) async {
    final repo = RecoveryRepository()
      ..requestError = const ApiError(message: 'disabled', statusCode: 503);
    await mount(tester, repo);
    await enter(tester, 'recovery-email', 'qa@example.com');
    await tap(tester, 'Send recovery code');
    expect(find.textContaining('currently unavailable'), findsOneWidget);
    expect(find.textContaining('on its way'), findsNothing);
    expect(find.byKey(const ValueKey('recovery-code')), findsNothing);
    expect(find.text('Reset your password'), findsOneWidget);
  });

  testWidgets('duplicate requests and resends wait for cooldown', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 4);
    final gate = Completer<void>();
    final repo = RecoveryRepository()..requestGate = gate;
    await mount(tester, repo, now: () => now);
    await enter(tester, 'recovery-email', 'qa@example.com');
    await tester.tap(find.text('Send recovery code'));
    await tester.pump();
    // While the request is in flight the button shows progress and ignores
    // taps.
    expect(find.byType(V3Spinner), findsOneWidget);
    await tester.tap(find.byType(V3Spinner), warnIfMissed: false);
    await tester.pump();
    expect(repo.requests, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    // The same address has to wait a minute: the button counts it down and
    // ignores taps until then.
    expect(find.text('1:00'), findsOneWidget);
    await tap(tester, 'Resend code');
    expect(repo.requests, 1);
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, 'Resend code');
    expect(repo.requests, 2);
  });

  testWidgets('resend clears the code and any message', (tester) async {
    var now = DateTime.utc(2026, 10, 4);
    final repo = RecoveryRepository();
    await mount(tester, repo, now: () => now);
    await enter(tester, 'recovery-email', 'qa@example.com');
    await tap(tester, 'Send recovery code');
    await enter(tester, 'recovery-code', 'short');
    await tap(tester, 'Update password');
    expect(fieldError(tester, 'recovery-code'), isNotNull);
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, 'Resend code');
    expect(repo.requests, 2);
    expect(fieldError(tester, 'recovery-code'), isNull);
    expect(
      tester.widget<TextField>(input('recovery-code')).controller?.text,
      '',
    );
  });

  testWidgets('manual code remains usable when sending is unavailable', (
    tester,
  ) async {
    final repo = RecoveryRepository()..available = false;
    bool? returned;
    await mount(tester, repo, returned: (value) => returned = value);
    await tap(tester, 'Enter recovery code');
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'Paste the recovery code from your email. It expires in 20 minutes.',
      ),
      findsOneWidget,
    );
    expect(find.text('Resend code'), findsNothing);
    await fillReset(tester);
    for (final key in ['recovery-password', 'recovery-confirmation']) {
      expect(tester.widget<TextField>(input(key)).obscureText, isTrue);
    }
    await tap(tester, 'Update password');
    expect(repo.requests, 0);
    expect(repo.confirmations, 1);
    expect(find.text('Password updated'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tap(tester, 'Back to sign in');
    expect(returned, isTrue);
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
      fieldError(tester, 'recovery-code'),
      'Paste the complete recovery code from your email.',
    );

    await fillReset(tester, password: '😀😀😀😀');
    await tap(tester, 'Update password');
    expect(repo.confirmations, 0);
    expect(
      fieldError(tester, 'recovery-password'),
      'New password needs 8+ characters',
    );
    // One message at a time, as in the design.
    expect(fieldError(tester, 'recovery-code'), isNull);

    await fillReset(tester, password: List.filled(37, 'é').join());
    await tap(tester, 'Update password');
    expect(repo.confirmations, 0);
    expect(
      fieldError(tester, 'recovery-password'),
      'This password is too long. Use a shorter password.',
    );

    await fillReset(tester, confirmation: 'DifferentPass9!');
    await tap(tester, 'Update password');
    expect(repo.confirmations, 0);
    expect(
      fieldError(tester, 'recovery-confirmation'),
      'Passwords don’t match',
    );

    // Whitespace around a pasted code is dropped and a 72-byte password fits.
    final boundary = List.filled(36, 'é').join();
    await fillReset(tester, code: ' $_code\n', password: boundary);
    await tap(tester, 'Update password');
    expect(repo.submittedCode, _code);
    expect(repo.submittedPassword, boundary);
    expect(repo.confirmations, 1);
  });

  testWidgets('typing clears the message on that field', (tester) async {
    final repo = RecoveryRepository();
    await mount(tester, repo);
    await tap(tester, 'Enter recovery code');
    await fillReset(tester, code: 'bad');
    await tap(tester, 'Update password');
    expect(fieldError(tester, 'recovery-code'), isNotNull);
    await enter(tester, 'recovery-code', _code);
    expect(fieldError(tester, 'recovery-code'), isNull);
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
      fieldError(tester, 'recovery-code'),
      'That code has expired. Request a new one.',
    );
    expect(find.text('Password updated'), findsNothing);
    expect(find.text('Check your email'), findsOneWidget);
    // Manual entry has no email to resend to, so it offers a fresh request.
    await tap(tester, 'Request a new code');
    expect(find.text('Reset your password'), findsOneWidget);
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
    expect(
      fieldError(tester, 'recovery-confirmation'),
      'Too many attempts. Please wait before trying again.',
    );
    await tester.tap(find.text('Try again in 1:30'), warnIfMissed: false);
    await tester.pumpAndSettle();
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
    await tap(tester, 'Send recovery code');
    expect(
      fieldError(tester, 'recovery-email'),
      'Too many attempts. Please wait before trying again.',
    );
    await tester.tap(find.text('Try again in 15:00'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.requests, 1);
    expect(find.textContaining('on its way'), findsNothing);
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
      fieldError(tester, 'recovery-confirmation'),
      contains('Couldn’t confirm the password change'),
    );
    expect(find.text('Password updated'), findsNothing);
    repo.confirmError = null;
    await tap(tester, 'Update password');
    expect(repo.confirmations, 2);
    expect(find.text('Password updated'), findsOneWidget);
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

  testWidgets(
    'successful recovery returns to the real sign-in form without the old password',
    (tester) async {
      final repo = RecoveryRepository();
      final router = GoRouter(
        initialLocation: AppRoutes.forgotPassword,
        routes: [
          GoRoute(
            path: AppRoutes.auth,
            builder: (_, _) => const AuthScreen(initialMode: AuthMode.signIn),
          ),
          // The old deep link keeps working: it opens auth with the sheet.
          GoRoute(
            path: AppRoutes.forgotPassword,
            builder: (_, _) => const AuthScreen(
              initialMode: AuthMode.signIn,
              startRecovery: true,
            ),
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
      // Opened by the deep link: close it, sign in with a stale password,
      // then walk the whole reset from the button.
      expect(find.text('Reset your password'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      semantics.dispose();
      expect(find.text('Reset your password'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is V3Field && w.label == 'Email'),
          matching: find.byType(TextField),
        ),
        'qa@example.com',
      );
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is V3Field && w.label == 'Password',
          ),
          matching: find.byType(TextField),
        ),
        'OldFixture7!',
      );
      await tap(tester, 'Forgot password?');
      await tap(tester, 'Enter recovery code');
      await fillReset(tester);
      await tap(tester, 'Update password');
      await tap(tester, 'Back to sign in');
      expect(find.text('Password updated'), findsNothing);

      expect(find.text('WELCOME BACK'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.controller?.text, 'qa@example.com');
      expect(fields.last.controller?.text, isEmpty);
    },
  );
}

void _ignore(String _) {}
