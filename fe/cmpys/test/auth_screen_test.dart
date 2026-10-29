import 'dart:async';

import 'package:cmpys/app/router.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/data/auth_repository.dart';
import 'package:cmpys/features/auth/data/password_recovery_repository.dart';
import 'package:cmpys/features/auth/models/auth_models.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:cmpys/features/auth/presentation/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// CMPYS v3 auth (`v3/onboard.jsx` Auth): a Create account / Sign in segment,
// a name field that collapses in sign-in, inline validation, a show/hide
// password eye, "Forgot password?" opening the recovery sheet and the
// AI-interpretation disclaimer. The login/register wiring is the app's
// existing auth controller.

class _Repo extends AuthRepository {
  _Repo()
    : super(
        dioClient: DioClient(tokenStore: TokenStore()),
        tokenStore: TokenStore(),
      );

  Object? error;
  Completer<void>? gate;
  final calls = <String>[];
  String? email, password, fullName;

  Future<AuthResponse> _respond(String call) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return const AuthResponse(accessToken: 'token');
  }

  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) {
    this.email = email;
    this.password = password;
    return _respond('login');
  }

  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? fullName,
  }) {
    this.email = email;
    this.password = password;
    this.fullName = fullName;
    return _respond('register');
  }
}

class _FakeSession extends StateNotifier<SessionState>
    implements SessionController {
  _FakeSession(this.afterAuth) : super(const SessionUnauthenticated());

  final SessionState afterAuth;
  bool? newRegistration;

  @override
  Future<void> onAuthenticated({bool isNewRegistration = false}) async {
    newRegistration = isNewRegistration;
    state = afterAuth;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery extends Fake implements PasswordRecoveryRepository {
  @override
  Future<bool> isAvailable() async => true;
}

const _me = Me(id: 'user-1', email: 'qa@example.com');

late _Repo _repo;
late _FakeSession _session;

Future<void> _mount(
  WidgetTester tester, {
  AuthMode mode = AuthMode.signUp,
  bool startRecovery = false,
  SessionState afterAuth = const SessionNeedsOnboarding(user: _me),
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool pushed = false,
}) async {
  _repo = _Repo();
  _session = _FakeSession(afterAuth);
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: pushed ? '/launcher' : AppRoutes.auth,
    routes: [
      GoRoute(
        path: '/launcher',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push(AppRoutes.auth),
            child: const Text('Open auth'),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (_, _) =>
            AuthScreen(initialMode: mode, startRecovery: startRecovery),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: AppRoutes.cmpysOnboarding,
        builder: (_, _) => const Scaffold(body: Text('onboarding')),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const Scaffold(body: Text('splash')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_repo),
        sessionControllerProvider.overrideWith((ref) => _session),
        passwordRecoveryRepositoryProvider.overrideWithValue(_Recovery()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        // The real app theme: it styles Material inputs with a filled outline,
        // which a V3Field must not inherit.
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
  }
}

Finder _fieldNamed(String label) => find.byWidgetPredicate(
  (w) => w is V3Field && w.label == label,
  description: 'V3Field "$label"',
);

Future<void> _type(WidgetTester tester, String label, String text) async {
  final input = find.descendant(
    of: _fieldNamed(label),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(input);
  await tester.enterText(input, text);
  await tester.pump();
}

Finder get _submit => find.byWidgetPredicate(
  (w) =>
      w is V3Button &&
      w.full &&
      w.kind == V3ButtonKind.primary &&
      w.size == V3Size.lg,
  description: 'primary submit button',
);

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.pump();
  await tester.tap(_submit);
  await tester.pump();
}

Future<void> _selectMode(WidgetTester tester, String label) async {
  final segment = find.descendant(
    of: find.byType(V3Seg<AuthMode>),
    matching: find.text(label),
  );
  await tester.ensureVisible(segment);
  await tester.pump();
  await tester.tap(segment);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('validation_messages', (tester) async {
    await _mount(tester);

    await _tapSubmit(tester);
    expect(find.text('Tell us your name'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(_repo.calls, isEmpty);

    // Typing into a field clears only that field's message.
    await _type(tester, 'Name', 'Ada');
    expect(find.text('Tell us your name'), findsNothing);
    expect(find.text('Enter a valid email'), findsOneWidget);

    await _type(tester, 'Email', 'ada@');
    await _type(tester, 'Password', '1234567');
    await _tapSubmit(tester);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(_repo.calls, isEmpty);

    await _type(tester, 'Email', 'ada@example.com');
    await _type(tester, 'Password', '12345678');
    await _tapSubmit(tester);
    expect(find.text('Enter a valid email'), findsNothing);
    expect(find.text('At least 8 characters'), findsNothing);
    expect(_repo.calls, ['register']);
  });

  testWidgets('sign in does not ask for a name or lock out short passwords', (
    tester,
  ) async {
    await _mount(tester, mode: AuthMode.signIn);
    await _tapSubmit(tester);
    expect(find.text('Tell us your name'), findsNothing);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);

    // The server accepts any non-empty password on login, so an older
    // account with a shorter password is not blocked on the device.
    await _type(tester, 'Email', 'qa@example.com');
    await _type(tester, 'Password', 'short');
    await _tapSubmit(tester);
    expect(_repo.calls, ['login']);
    expect(_repo.password, 'short');
  });

  testWidgets('segment switches copy and clears messages', (tester) async {
    await _mount(tester);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    expect(find.textContaining('Start with who you'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
    await _tapSubmit(tester);
    expect(find.text('Tell us your name'), findsOneWidget);

    await _selectMode(tester, 'Sign in');
    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.textContaining('Pick up where'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Tell us your name'), findsNothing);
    expect(find.text('Enter a valid email'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(V3Button),
        matching: find.text('Sign in'),
      ),
      findsOneWidget,
    );

    await _selectMode(tester, 'Create account');
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('name field collapses over 450 ms and keeps what was typed', (
    tester,
  ) async {
    await _mount(tester);
    await _type(tester, 'Name', 'Ada');
    final full = tester.getSize(find.byKey(AuthScreen.nameCollapseKey)).height;
    expect(full, greaterThan(60));

    await tester.tap(
      find.descendant(
        of: find.byType(V3Seg<AuthMode>),
        matching: find.text('Sign in'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final partway = tester
        .getSize(find.byKey(AuthScreen.nameCollapseKey))
        .height;
    expect(partway, inInclusiveRange(1, full - 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getSize(find.byKey(AuthScreen.nameCollapseKey)).height, 0);
    // A collapsed field is out of the semantics and the tab order.
    expect(find.text('Name'), findsNothing);

    await _selectMode(tester, 'Create account');
    expect(
      tester.getSize(find.byKey(AuthScreen.nameCollapseKey)).height,
      closeTo(full, 0.5),
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: _fieldNamed('Name'),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'Ada',
    );
  });

  testWidgets('password eye toggles visibility with a spoken label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    TextField password() => tester.widget<TextField>(
      find.descendant(
        of: _fieldNamed('Password'),
        matching: find.byType(TextField),
      ),
    );
    expect(password().obscureText, isTrue);
    expect(find.bySemanticsLabel('Show password'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
    expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    expect(find.bySemanticsLabel('Show password'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Hide password'));
    await tester.pump();
    expect(password().obscureText, isTrue);
    semantics.dispose();
  });

  testWidgets('fields keep the design box under the app theme', (tester) async {
    await _mount(tester);
    for (final label in ['Name', 'Email', 'Password']) {
      final box = find
          .descendant(
            of: _fieldNamed(label),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      // Design: a 52 pt box. The theme's own padding and outline would grow
      // it and draw a second border inside.
      expect(tester.getSize(box).height, 52, reason: label);
      final input = tester.widget<InputDecorator>(
        find.descendant(
          of: _fieldNamed(label),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(input.decoration.enabledBorder, InputBorder.none, reason: label);
      expect(input.decoration.filled, isFalse, reason: label);
    }
  });

  testWidgets('credential fields are never autocorrected or suggested', (
    tester,
  ) async {
    await _mount(tester);
    for (final label in ['Name', 'Email', 'Password']) {
      final input = tester.widget<TextField>(
        find.descendant(
          of: _fieldNamed(label),
          matching: find.byType(TextField),
        ),
      );
      expect(input.autocorrect, isFalse, reason: label);
      expect(input.enableSuggestions, isFalse, reason: label);
    }
    // Showing the password does not turn the keyboard's help back on.
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('Show password'));
    await tester.pump();
    final password = tester.widget<TextField>(
      find.descendant(
        of: _fieldNamed('Password'),
        matching: find.byType(TextField),
      ),
    );
    expect(password.obscureText, isFalse);
    expect(password.autocorrect, isFalse);
    expect(password.enableSuggestions, isFalse);
    semantics.dispose();
  });

  testWidgets('a tap outside the fields dismisses the keyboard', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester, mode: AuthMode.signIn);
    final email = find.descendant(
      of: _fieldNamed('Email'),
      matching: find.byType(TextField),
    );
    bool focused() => tester.widget<TextField>(email).focusNode!.hasFocus;

    await tester.tap(email);
    await tester.pump();
    expect(focused(), isTrue);

    await tester.tap(find.text('WELCOME BACK'));
    await tester.pump();
    expect(focused(), isFalse);

    // The password eye is part of its field: the keyboard stays up.
    final password = find.descendant(
      of: _fieldNamed('Password'),
      matching: find.byType(TextField),
    );
    await tester.tap(password);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).focusNode!.hasFocus, isTrue);
    semantics.dispose();
  });

  testWidgets('disclaimer is shown and the demo fill is gone', (tester) async {
    await _mount(tester);
    const disclaimer =
        'Mentors in CMPYS are AI interpretations of real people’s documented '
        'methods. They are not the people themselves.';
    expect(find.text(disclaimer), findsOneWidget);
    expect(find.text('Fill demo'), findsNothing);
    await _selectMode(tester, 'Sign in');
    expect(find.text(disclaimer), findsOneWidget);
  });

  testWidgets(
    'sign up registers with a trimmed name and email, then onboards',
    (tester) async {
      await _mount(tester);
      await _type(tester, 'Name', '  Ada  ');
      await _type(tester, 'Email', ' ada@example.com ');
      await _type(tester, 'Password', 'compounding');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(_repo.calls, ['register']);
      expect(_repo.fullName, 'Ada');
      expect(_repo.email, 'ada@example.com');
      expect(_repo.password, 'compounding');
      expect(_session.newRegistration, isTrue);
      expect(find.text('onboarding'), findsOneWidget);
    },
  );

  testWidgets('sign in logs in and routes a ready session home', (
    tester,
  ) async {
    await _mount(
      tester,
      mode: AuthMode.signIn,
      afterAuth: const SessionReady(user: _me, currentIdolId: ''),
    );
    await _type(tester, 'Email', 'qa@example.com');
    await _type(tester, 'Password', 'compounding');
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(_repo.calls, ['login']);
    expect(_session.newRegistration, isFalse);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('loading state comes from the real request', (tester) async {
    await _mount(tester, mode: AuthMode.signIn);
    _repo.gate = Completer<void>();
    await _type(tester, 'Email', 'qa@example.com');
    await _type(tester, 'Password', 'compounding');
    expect(find.byType(V3Spinner), findsNothing);

    await _tapSubmit(tester);
    expect(find.byType(V3Spinner), findsOneWidget);
    expect(tester.widget<V3Button>(_submit).loading, isTrue);
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();
    expect(_repo.calls, ['login'], reason: 'a second tap must not resubmit');

    _repo.error = const ApiError(
      message: 'Invalid email or password',
      statusCode: 401,
    );
    _repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(V3Spinner), findsNothing);
    expect(tester.widget<V3Button>(_submit).loading, isFalse);
  });

  testWidgets('wrong credentials show a general error under the button', (
    tester,
  ) async {
    await _mount(tester, mode: AuthMode.signIn);
    _repo.error = const ApiError(
      message: 'Invalid email or password',
      statusCode: 401,
    );
    await _type(tester, 'Email', 'qa@example.com');
    await _type(tester, 'Password', 'compounding');
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    final error = find.text('Invalid email or password');
    expect(error, findsOneWidget);
    expect(
      tester.getTopLeft(error).dy,
      greaterThan(tester.getBottomLeft(_submit).dy),
    );
    // Neither input is flagged: it is not about one field.
    expect(
      tester
          .widgetList<V3Field>(find.byType(V3Field))
          .where((f) => f.error != null),
      isEmpty,
    );

    // Typing again dismisses it.
    await _type(tester, 'Password', 'compounding2');
    expect(find.text('Invalid email or password'), findsNothing);
  });

  testWidgets('an email that is taken is reported on the email field', (
    tester,
  ) async {
    await _mount(tester);
    _repo.error = const ApiError(
      message: 'Email already registered',
      statusCode: 400,
    );
    await _type(tester, 'Name', 'Ada');
    await _type(tester, 'Email', 'ada@example.com');
    await _type(tester, 'Password', 'compounding');
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    final email = tester.widget<V3Field>(_fieldNamed('Email'));
    expect(email.error, 'Email already registered');
    expect(
      tester
          .widgetList<V3Field>(find.byType(V3Field))
          .where((f) => f.error != null),
      hasLength(1),
    );
  });

  group('server validation (422)', () {
    const raw =
        '[{type: value_error, loc: [body, email], msg: value is not a valid '
        'email address}]';

    testWidgets('an email the server rejects is named on the email field', (
      tester,
    ) async {
      await _mount(tester);
      _repo.error = const ApiError(
        message: raw,
        statusCode: 422,
        fieldErrors: [ApiFieldError(field: 'email', type: 'value_error')],
      );
      await _type(tester, 'Name', 'Ari');
      await _type(tester, 'Email', 'v3-live@example.test');
      await _type(tester, 'Password', 'compounding');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        tester.widget<V3Field>(_fieldNamed('Email')).error,
        'Enter a valid email address.',
      );
      expect(find.textContaining('value_error'), findsNothing);
      expect(find.textContaining('loc'), findsNothing);
    });

    testWidgets('sign in maps the same field errors', (tester) async {
      await _mount(tester, mode: AuthMode.signIn);
      _repo.error = const ApiError(
        message: raw,
        statusCode: 422,
        fieldErrors: [ApiFieldError(field: 'email', type: 'value_error')],
      );
      await _type(tester, 'Email', 'qa@example.test');
      await _type(tester, 'Password', 'compounding');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(
        tester.widget<V3Field>(_fieldNamed('Email')).error,
        'Enter a valid email address.',
      );
      expect(find.textContaining('value_error'), findsNothing);
    });

    testWidgets('password and name errors get their own copy', (tester) async {
      await _mount(tester);
      _repo.error = const ApiError(
        message: raw,
        statusCode: 422,
        fieldErrors: [
          ApiFieldError(field: 'password', type: 'string_too_short'),
          ApiFieldError(field: 'full_name', type: 'string_too_long'),
        ],
      );
      await _type(tester, 'Name', 'Ari');
      await _type(tester, 'Email', 'ari@example.com');
      await _type(tester, 'Password', 'compounding');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(
        tester.widget<V3Field>(_fieldNamed('Password')).error,
        'Use at least 8 characters.',
      );
      expect(
        tester.widget<V3Field>(_fieldNamed('Name')).error,
        'Use a shorter name.',
      );
      expect(find.textContaining('string_too'), findsNothing);
    });

    testWidgets('anything else is the general fallback, never the raw text', (
      tester,
    ) async {
      await _mount(tester, mode: AuthMode.signIn);
      // A list detail with no field the form knows, and one with none.
      for (final error in const [
        ApiError(
          message: raw,
          statusCode: 422,
          fieldErrors: [ApiFieldError(field: 'device', type: 'missing')],
        ),
        ApiError(message: raw, statusCode: 422),
      ]) {
        _repo.error = error;
        await _type(tester, 'Email', 'qa@example.com');
        await _type(tester, 'Password', 'compounding');
        await _tapSubmit(tester);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Something in this form isn’t right. Check it and try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('value_error'), findsNothing);
      }
    });
  });

  testWidgets('a dropped connection is a general error and can be retried', (
    tester,
  ) async {
    await _mount(tester, mode: AuthMode.signIn);
    _repo.error = const NetworkError();
    await _type(tester, 'Email', 'qa@example.com');
    await _type(tester, 'Password', 'compounding');
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsOneWidget);

    _repo.error = null;
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(_repo.calls, ['login', 'login']);
  });

  testWidgets('a password over 72 bytes is rejected before the request', (
    tester,
  ) async {
    await _mount(tester, mode: AuthMode.signIn);
    await _type(tester, 'Email', 'qa@example.com');
    await _type(tester, 'Password', List.filled(37, 'é').join());
    await _tapSubmit(tester);
    expect(
      find.text('This password is too long. Use a shorter password.'),
      findsOneWidget,
    );
    expect(_repo.calls, isEmpty);
  });

  testWidgets('forgot password opens the recovery sheet with the email', (
    tester,
  ) async {
    await _mount(tester, mode: AuthMode.signIn);
    await _type(tester, 'Email', 'qa@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Email recovery is available'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('recovery-email')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      'qa@example.com',
    );
  });

  testWidgets('the forgot-password deep link opens auth with the sheet', (
    tester,
  ) async {
    await _mount(tester, mode: AuthMode.signIn, startRecovery: true);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('WELCOME BACK'), findsOneWidget);
  });

  testWidgets('back returns to the splash it was opened from', (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester, pushed: true);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open auth'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('no back button when auth is the only page', (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    semantics.dispose();
  });

  testWidgets('fits a narrow phone at 200% text', (tester) async {
    await _mount(
      tester,
      width: 320,
      height: 568,
      textScale: 2,
      mode: AuthMode.signIn,
    );
    await _tapSubmit(tester);
    expect(tester.takeException(), isNull);
    await _selectMode(tester, 'Create account');
    await _tapSubmit(tester);
    expect(tester.takeException(), isNull);
  });
}
