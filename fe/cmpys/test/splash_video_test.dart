// The splash's library video (SPEC §1, `v3/onboard.jsx` Splash): while it
// plays the orbit gives way, the wordmark moves to the top and the
// "Learn with history’s builders" row introduces the copy; when it fails
// (or with reduced motion) the splash is today's orbit design, unchanged.

import 'package:cmpys/app/assets.dart';
import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_video_player_platform.dart';

/// A session that resolves as signed out, so the splash stays.
class _SignedOut extends StateNotifier<SessionState>
    implements SessionController {
  _SignedOut() : super(const SessionInitializing());

  @override
  Future<void> initialize() async {
    await Future<void>.value();
    state = const SessionUnauthenticated();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester, {
  bool reducedMotion = false,
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues({'cmpys_has_seen_splash': true});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: AppRoutes.auth,
        builder: (_, _) => const Scaffold(body: Text('auth')),
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
        sessionControllerProvider.overrideWith((ref) => _SignedOut()),
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
}

/// Advances in 100 ms frames (the orbit and sheen never settle).
Future<void> _elapse(WidgetTester tester, Duration total) async {
  var left = total;
  while (left > Duration.zero) {
    final step = left > const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : left;
    await tester.pump(step);
    left -= step;
  }
}

final _wordmark = find.byKey(SplashScreen.wordmarkKey);
final _avatarRow = find.byKey(SplashScreen.avatarRowKey);

/// The fade around the orbit scene (1 = today's design shows).
double _orbitOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(SplashScreen.orbitKey),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

V3LoopVideo _video(WidgetTester tester) =>
    tester.widget<V3LoopVideo>(find.byKey(SplashScreen.videoKey));

void main() {
  late FakeVideoPlayerPlatform fake;

  setUp(() => fake = FakeVideoPlayerPlatform.install());
  tearDown(() => V3VideoCoordinator.instance.debugReset());

  testWidgets('while the video plays the wordmark moves to the top and the '
      'builders row shows', (tester) async {
    await _mount(tester);
    expect(fake.created, {1: AppAssets.videoSplash});
    // Loading: today's design, wordmark in the middle of the orbit.
    expect(_orbitOpacity(tester), 1);
    expect(_avatarRow, findsNothing);
    final centred = tester.getTopLeft(_wordmark).dy;
    expect(centred, greaterThan(130));
    // vidIn starts blurred and dim.
    expect(_video(tester).blur, 8);
    expect(_video(tester).brightness, 0.6);
    expect(_video(tester).initialScale, 1.08);
    expect(_video(tester).scaleDuration, const Duration(seconds: 14));

    fake.initialize(1);
    await _elapse(tester, const Duration(milliseconds: 300));
    fake.renderFrame(1);
    await _elapse(tester, const Duration(milliseconds: 300));
    expect(_video(tester).blur, 0);
    expect(_video(tester).brightness, 1);

    // Past the 1.2 s move and the 1.7 s reveal.
    await _elapse(tester, const Duration(milliseconds: 2000));
    expect(tester.getTopLeft(_wordmark).dy, closeTo(112, 0.5));
    expect(_orbitOpacity(tester), 0);
    expect(_avatarRow, findsOneWidget);
    expect(find.text('Learn with history’s builders'), findsOneWidget);
    final rowAvatars = tester
        .widgetList<V3Avatar>(
          find.descendant(of: _avatarRow, matching: find.byType(V3Avatar)),
        )
        .toList();
    expect(rowAvatars.map((a) => a.size).toSet(), {34});
    expect(rowAvatars.every((a) => a.gray), isTrue);
    expect(rowAvatars, hasLength(5));
    // The wordmark's letters carry the sheen.
    expect(
      find.descendant(of: _wordmark, matching: find.byType(ShaderMask)),
      findsNWidgets(5),
    );
    expect(find.text('Get started').hitTestable(), findsOneWidget);
  });

  testWidgets('on a small phone the raised wordmark stays clear of the copy', (
    tester,
  ) async {
    await _mount(tester, size: const Size(320, 568));
    fake.initialize(1);
    await _elapse(tester, const Duration(milliseconds: 300));
    fake.renderFrame(1);
    await _elapse(tester, const Duration(milliseconds: 3000));
    expect(tester.takeException(), isNull);
    expect(_avatarRow, findsOneWidget);
    final wordmark = tester.getRect(
      find.ancestor(of: _wordmark, matching: find.byType(Column)).first,
    );
    expect(wordmark.top, greaterThanOrEqualTo(8));
    expect(wordmark.bottom, lessThanOrEqualTo(tester.getRect(_avatarRow).top));
  });

  testWidgets('when the video fails the splash is the orbit design', (
    tester,
  ) async {
    await _mount(tester);
    final centred = tester.getTopLeft(_wordmark).dy;
    fake.fail(1);
    await _elapse(tester, const Duration(milliseconds: 3000));

    expect(fake.disposed, contains(1));
    expect(_orbitOpacity(tester), 1);
    expect(tester.getTopLeft(_wordmark).dy, centred);
    expect(_avatarRow, findsNothing);
    // Only the five orbiting portraits.
    expect(find.byType(V3Avatar), findsNWidgets(5));
    expect(find.byKey(V3LoopVideo.layerKey), findsNothing);
    // The copy and buttons still reveal as before.
    expect(find.text('Get started').hitTestable(), findsOneWidget);
    expect(
      find.text('I already have an account').hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('reduced motion: no video, no sheen, the still orbit design', (
    tester,
  ) async {
    await _mount(tester, reducedMotion: true);
    await _elapse(tester, const Duration(milliseconds: 2500));
    expect(fake.created, isEmpty);
    expect(_avatarRow, findsNothing);
    expect(
      find.descendant(of: _wordmark, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    expect(_orbitOpacity(tester), 1);
    expect(find.text('Get started').hitTestable(), findsOneWidget);
  });

  testWidgets('the wordmark reads as one word', (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    await _elapse(tester, const Duration(milliseconds: 1500));
    // One label for the word (not five letters), merged into the scene.
    expect(find.bySemanticsLabel(RegExp(r'^cmpys\b')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^c\b')), findsNothing);
    semantics.dispose();
  });
}
