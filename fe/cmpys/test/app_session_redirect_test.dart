import 'dart:async';

import 'package:cmpys/app/app.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The app root sends a visitor to auth whenever the session ends, except on a
// cold start: a launch that resolves signed out stays on the splash, which
// offers "Get started" and "I already have an account".

class _FakeSession extends StateNotifier<SessionState>
    implements SessionController {
  _FakeSession({this.result, this.gate}) : super(const SessionInitializing());

  /// Where `initialize()` lands, once [gate] (if any) opens.
  final SessionState? result;
  final Completer<void>? gate;

  void emit(SessionState next) => state = next;

  @override
  Future<void> initialize() async {
    await Future<void>.value();
    if (gate != null) await gate!.future;
    if (result != null) state = result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _launch(WidgetTester tester, _FakeSession session) async {
  SharedPreferences.setMockInitialValues({'cmpys_has_seen_splash': true});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionControllerProvider.overrideWith((ref) => session)],
      child: const App(),
    ),
  );
}

Future<void> _elapse(WidgetTester tester, Duration total) async {
  // The splash orbit never settles, so advance in frames.
  for (
    var left = total;
    left > Duration.zero;
    left -= const Duration(milliseconds: 100)
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a cold start that resolves signed out stays on the splash', (
    tester,
  ) async {
    await _launch(tester, _FakeSession(result: const SessionUnauthenticated()));
    await _elapse(tester, const Duration(seconds: 4));
    expect(find.text('cmpys'), findsOneWidget);
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    expect(find.text('WELCOME BACK'), findsNothing);
    expect(find.text('CREATE ACCOUNT'), findsNothing);
  });

  testWidgets('a session that ends later still goes to auth', (tester) async {
    final session = _FakeSession(gate: Completer<void>());
    await _launch(tester, session);
    await _elapse(tester, const Duration(seconds: 1));
    session.emit(
      const SessionReady(
        user: Me(id: 'user-1', email: 'qa@example.com'),
        currentIdolId: '',
      ),
    );
    await _elapse(tester, const Duration(milliseconds: 500));
    expect(find.text('cmpys'), findsOneWidget);

    session.emit(const SessionUnauthenticated());
    await _elapse(tester, const Duration(seconds: 2));
    expect(find.text('WELCOME BACK'), findsOneWidget);
  });
}
