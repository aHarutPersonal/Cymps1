import 'dart:async';
import 'dart:math' as math;

import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:cmpys/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CMPYS v3 splash (`v3/onboard.jsx` Splash): a night screen with five grey
// mentor portraits orbiting the wordmark (the fallback for the library
// video, which no test platform plays), a tagline that reveals after 1.7 s
// and, for a signed-out visitor, the two entry buttons. Signed-in sessions
// keep their automatic routing and never see the buttons. The video itself
// is covered in splash_video_test.dart.

/// Session stand-in whose `initialize()` lands on [result] once [gate] opens.
class _FakeSession extends StateNotifier<SessionState>
    implements SessionController {
  _FakeSession(this.result, {this.gate}) : super(const SessionInitializing());

  final SessionState result;
  final Completer<void>? gate;

  @override
  Future<void> initialize() async {
    state = const SessionInitializing();
    // The real controller awaits storage first; never change a provider
    // while the splash is still building.
    await Future<void>.value();
    if (gate != null) await gate!.future;
    state = result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _me = Me(id: 'user-1', email: 'qa@example.com');

Future<GoRouter> _mount(
  WidgetTester tester, {
  SessionState session = const SessionUnauthenticated(),
  Completer<void>? gate,
  Size size = const Size(390, 844),
  bool reducedMotion = false,
  bool seenSplash = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (seenSplash) 'cmpys_has_seen_splash': true,
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: AppRoutes.auth,
        builder: (_, state) =>
            Scaffold(body: Text('auth:${state.uri.queryParameters['mode']}')),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: AppRoutes.cmpysOnboarding,
        builder: (_, _) => const Scaffold(body: Text('onboarding')),
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
        sessionControllerProvider.overrideWith(
          (ref) => _FakeSession(session, gate: gate),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// The wordmark ("cmpys", one glyph per letter).
final _wordmark = find.byKey(SplashScreen.wordmarkKey);

/// The tagline line [text] (a `V3BlurWords`).
Finder _tagline(String text) => find.byWidgetPredicate(
  (w) => w is V3BlurWords && w.text == text,
  description: 'tagline "$text"',
);

/// Opacity of the reveal wrapped around [key] (1 once revealed).
double _opacity(WidgetTester tester, Key key) => tester
    .widget<Opacity>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

Future<void> _elapse(WidgetTester tester, Duration total) async {
  // The orbit never settles, so advance in frames instead of pumpAndSettle.
  var left = total;
  while (left > Duration.zero) {
    final step = left > const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : left;
    await tester.pump(step);
    left -= step;
  }
}

void main() {
  testWidgets('copy_appears_after_delay', (tester) async {
    await _mount(tester);

    // Before 1.7 s only the wordmark scene shows: the tagline, the line under
    // it and the buttons are hidden and cannot be tapped.
    await _elapse(tester, const Duration(milliseconds: 1600));
    expect(_wordmark, findsOneWidget);
    expect(find.text('COMPARE YOUR SUCCESS'), findsOneWidget);
    expect(_opacity(tester, SplashScreen.taglineKey), 0);
    expect(_opacity(tester, SplashScreen.introKey), 0);
    expect(_opacity(tester, SplashScreen.buttonsKey), 0);
    expect(find.text('Get started').hitTestable(), findsNothing);

    // Past 1.7 s each reveals (0.8 s on --out, the copy 0.2 s and the
    // buttons 0.3 s behind the tagline).
    await _elapse(tester, const Duration(milliseconds: 2000));
    expect(_opacity(tester, SplashScreen.taglineKey), 1);
    expect(_opacity(tester, SplashScreen.introKey), 1);
    expect(_opacity(tester, SplashScreen.buttonsKey), 1);
    expect(_tagline('Learn from someone you admire.'), findsOneWidget);
    expect(_tagline('Measure yourself honestly.'), findsOneWidget);
    expect(
      find.text(
        'A personal plan of short tutorials and real practice, shaped by a '
        'mentor’s documented methods.',
      ),
      findsOneWidget,
    );
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    expect(
      find.text('I already have an account').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('buttons_route_to_signup_and_signin', (tester) async {
    final router = await _mount(tester);
    await _elapse(tester, const Duration(milliseconds: 3000));

    await tester.tap(find.text('Get started'));
    await _elapse(tester, const Duration(milliseconds: 200));
    expect(find.text('auth:up'), findsOneWidget);

    router.pop();
    await _elapse(tester, const Duration(milliseconds: 500));
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('I already have an account'));
    await _elapse(tester, const Duration(milliseconds: 200));
    expect(find.text('auth:in'), findsOneWidget);
  });

  testWidgets('buttons wait for the session to resolve as signed out', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _mount(tester, gate: gate);
    await _elapse(tester, const Duration(milliseconds: 2500));
    // The tagline is brand copy, but the entry buttons belong to a visitor
    // the app has confirmed is signed out.
    expect(_opacity(tester, SplashScreen.taglineKey), 1);
    expect(_opacity(tester, SplashScreen.buttonsKey), 0);
    expect(find.text('Get started').hitTestable(), findsNothing);

    gate.complete();
    await _elapse(tester, const Duration(milliseconds: 1500));
    expect(_opacity(tester, SplashScreen.buttonsKey), 1);
    expect(find.text('Get started').hitTestable(), findsOneWidget);
  });

  testWidgets('a ready session still routes home without entry buttons', (
    tester,
  ) async {
    await _mount(
      tester,
      session: const SessionReady(user: _me, currentIdolId: ''),
    );
    await _elapse(tester, const Duration(milliseconds: 2500));
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('a session needing onboarding still routes to onboarding', (
    tester,
  ) async {
    await _mount(tester, session: const SessionNeedsOnboarding(user: _me));
    await _elapse(tester, const Duration(milliseconds: 2500));
    expect(find.text('onboarding'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets(
    'a signed-out visitor stays on the splash instead of auto-routing',
    (tester) async {
      await _mount(tester);
      await _elapse(tester, const Duration(seconds: 6));
      expect(_wordmark, findsOneWidget);
      expect(find.textContaining('auth:'), findsNothing);
    },
  );

  testWidgets('orbit uses five grey mentor portraits, the first larger', (
    tester,
  ) async {
    await _mount(tester);
    await _elapse(tester, const Duration(milliseconds: 2500));
    final avatars = tester.widgetList<V3Avatar>(find.byType(V3Avatar)).toList();
    expect(avatars.map((a) => a.size), [74, 54, 54, 54, 54]);
    expect(avatars.every((a) => a.gray), isTrue);
    expect(avatars.map((a) => (a.image as AssetImage).assetName), [
      'assets/images/mentors/wb.png',
      'assets/images/mentors/mc.png',
      'assets/images/mentors/sj.png',
      'assets/images/mentors/jdr.png',
      'assets/images/mentors/em.png',
    ]);
  });

  testWidgets('avatars counter-rotate so they stay upright', (tester) async {
    await _mount(tester);
    await _elapse(tester, const Duration(milliseconds: 2500));
    double turns(RotationTransition t) => t.turns.value;
    final rotations = tester
        .widgetList<RotationTransition>(
          find.descendant(
            of: find.byKey(SplashScreen.orbitKey),
            matching: find.byType(RotationTransition),
          ),
        )
        .toList();
    // One group rotation plus one counter-rotation per avatar; each avatar's
    // turn cancels the group's.
    expect(rotations, hasLength(6));
    await _elapse(tester, const Duration(seconds: 7));
    final group = turns(rotations.first);
    expect(group, greaterThan(0));
    for (final counter in rotations.skip(1)) {
      final sum = group + turns(counter);
      expect((sum - sum.round()).abs(), lessThan(1e-6));
    }
  });

  testWidgets('reduced motion shows the finished scene and holds the orbit', (
    tester,
  ) async {
    await _mount(tester, reducedMotion: true);
    await _elapse(tester, const Duration(milliseconds: 1800));
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    final rotations = tester
        .widgetList<RotationTransition>(
          find.descendant(
            of: find.byKey(SplashScreen.orbitKey),
            matching: find.byType(RotationTransition),
          ),
        )
        .toList();
    expect(rotations, hasLength(6));
    await _elapse(tester, const Duration(seconds: 5));
    for (final r in rotations) {
      expect(r.turns.value, anyOf(0, 1));
    }
  });

  testWidgets('the glow gradient is the design circle, not twice its size', (
    tester,
  ) async {
    await _mount(tester);
    // Past the 0.6 s return-visit gate, so no timer is left pending.
    await _elapse(tester, const Duration(milliseconds: 1000));
    final glow = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient is RadialGradient,
      description: 'the glow',
    );
    final gradient =
        (tester.widget<DecoratedBox>(glow).decoration as BoxDecoration).gradient
            as RadialGradient;
    final box = tester.getSize(glow);
    expect(box.width, box.height);
    // CSS `circle` = farthest-corner: half the box times √2 (367.7 px on the
    // design's 520 px box). Flutter's radius is a fraction of the shortest
    // side, so it must be √2 / 2.
    expect(
      gradient.radius * box.shortestSide,
      closeTo(box.width / 2 * math.sqrt2, 0.5),
    );
    expect(gradient.radius, closeTo(math.sqrt2 / 2, 1e-3));
    // At the box edge the gradient has already faded out, so the circular
    // clip leaves no visible edge: stop `.7` lies inside it.
    final edge = (box.width / 2) / (gradient.radius * box.shortestSide);
    expect(edge, greaterThanOrEqualTo(gradient.stops!.last));
    expect(gradient.colors.last.a, 0);
  });

  testWidgets('hidden buttons cannot be reached with the keyboard', (
    tester,
  ) async {
    await _mount(tester);
    // Whether any focusable node under the buttons can take traversal focus.
    bool reachable() {
      final buttons = tester.element(find.byKey(SplashScreen.buttonsKey));
      return FocusManager.instance.rootScope.traversalDescendants.any((node) {
        final context = node.context;
        if (context == null) return false;
        var inside = false;
        context.visitAncestorElements((ancestor) {
          if (identical(ancestor, buttons)) inside = true;
          return !inside;
        });
        return inside;
      });
    }

    await _elapse(tester, const Duration(milliseconds: 1000));
    expect(reachable(), isFalse);
    await _elapse(tester, const Duration(milliseconds: 2500));
    expect(reachable(), isTrue);
  });

  testWidgets('a small phone keeps the whole screen free of overflow', (
    tester,
  ) async {
    await _mount(tester, size: const Size(320, 568));
    await _elapse(tester, const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(find.text('Get started'), findsOneWidget);
    // The copy scrolls rather than squeezing the scene out.
    expect(_wordmark.hitTestable(), findsOneWidget);
  });
}
