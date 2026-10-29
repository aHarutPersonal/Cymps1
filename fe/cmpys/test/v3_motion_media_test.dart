// CMPYS v3 motion & media primitives (SPEC "Shared primitives", §8, §9):
// V3LoopVideo and its one-at-a-time coordinator, V3BlurWords, V3Tilt,
// showInkReveal, V3Flame, V3VideoPortrait, the celebration's video layer,
// the "Week unlocked" overlay and its per-account ledger.

import 'package:cmpys/app/assets.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_video_player_platform.dart';

const _a = 'assets/videos/a.mp4';
const _b = 'assets/videos/b.mp4';
const _fallbackKey = ValueKey<String>('fallback');

Widget _fallback([Key key = _fallbackKey]) =>
    ColoredBox(key: key, color: const Color(0xFF000000));

/// Hosts [child] in a 390×844 app, with reduced motion when [reduced].
Future<void> _host(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: app!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

/// Lets player events, futures and the 100 ms position poll run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 110));
  }
}

/// Initialises player [id] and lets it start.
Future<void> _start(
  WidgetTester tester,
  FakeVideoPlayerPlatform fake,
  int id,
) async {
  fake.initialize(id);
  await _settle(tester);
}

double _layerOpacity(WidgetTester tester, [Finder? within]) {
  final finder = within == null
      ? find.byKey(V3LoopVideo.layerKey)
      : find.descendant(of: within, matching: find.byKey(V3LoopVideo.layerKey));
  return tester.widget<AnimatedOpacity>(finder).opacity;
}

void main() {
  late FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = FakeVideoPlayerPlatform.install();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => V3VideoCoordinator.instance.debugReset());

  group('V3LoopVideo', () {
    testWidgets('shows the fallback while loading and fades in only after '
        'a played frame', (tester) async {
      final ready = <bool>[];
      await _host(
        tester,
        V3LoopVideo(asset: _a, fallback: _fallback(), onReady: ready.add),
      );
      await tester.pump();
      expect(fake.created, {1: _a});
      expect(fake.calls, contains('mixWithOthers:true'));
      expect(find.byKey(_fallbackKey), findsOneWidget);

      await _start(tester, fake, 1);
      // Playing, muted and looping, but no frame yet: still the fallback.
      expect(fake.isPlaying(1), isTrue);
      expect(fake.volumes[1], 0);
      expect(fake.looping[1], isTrue);
      expect(_layerOpacity(tester), 0);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(ready, isEmpty);

      fake.renderFrame(1);
      await _settle(tester);
      expect(ready, [true]);
      expect(_layerOpacity(tester), 1);
      // The fade (1.2 s) runs over the fallback, which then goes offstage.
      expect(find.byKey(_fallbackKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.byKey(_fallbackKey), findsNothing);
      expect(find.byKey(_fallbackKey, skipOffstage: false), findsOneWidget);
    });

    testWidgets('keeps the fallback when initialisation errors', (
      tester,
    ) async {
      final ready = <bool>[];
      await _host(
        tester,
        V3LoopVideo(asset: _a, fallback: _fallback(), onReady: ready.add),
      );
      await tester.pump();
      fake.fail(1);
      await _settle(tester);
      expect(ready, [false]);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(find.byKey(V3LoopVideo.layerKey), findsNothing);
      expect(fake.disposed, contains(1));

      // A late "initialized" changes nothing.
      fake.initialize(1);
      await _settle(tester);
      expect(find.byKey(V3LoopVideo.layerKey), findsNothing);
    });

    testWidgets('keeps the fallback when loading times out', (tester) async {
      final ready = <bool>[];
      await _host(
        tester,
        V3LoopVideo(asset: _a, fallback: _fallback(), onReady: ready.add),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(ready, isEmpty);
      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      expect(ready, [false]);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(find.byKey(V3LoopVideo.layerKey), findsNothing);
    });

    testWidgets('gives up when no frame plays within the timeout', (
      tester,
    ) async {
      final ready = <bool>[];
      await _host(
        tester,
        V3LoopVideo(asset: _a, fallback: _fallback(), onReady: ready.add),
      );
      await tester.pump();
      await _start(tester, fake, 1);
      await tester.pump(const Duration(seconds: 6, milliseconds: 100));
      expect(ready, [false]);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(fake.disposed, contains(1));
    });

    testWidgets('reduced motion: never creates or plays a player', (
      tester,
    ) async {
      await _host(
        tester,
        V3LoopVideo(asset: _a, fallback: _fallback()),
        reduced: true,
      );
      await tester.pump(const Duration(seconds: 7));
      expect(fake.created, isEmpty);
      expect(fake.calls.where((c) => c.startsWith('play')), isEmpty);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(find.byKey(V3LoopVideo.layerKey), findsNothing);
    });

    testWidgets('only one video plays: the newest wins, the older resumes '
        'when it goes', (tester) async {
      var showB = false;
      late StateSetter setOuter;
      await _host(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return Column(
              children: [
                SizedBox(
                  height: 200,
                  child: V3LoopVideo(asset: _a, fallback: _fallback()),
                ),
                if (showB)
                  SizedBox(
                    height: 200,
                    child: V3LoopVideo(
                      asset: _b,
                      fallback: _fallback(const ValueKey('b')),
                    ),
                  ),
              ],
            );
          },
        ),
      );
      await tester.pump();
      await _start(tester, fake, 1);
      expect(fake.isPlaying(1), isTrue);

      setOuter(() => showB = true);
      await tester.pump();
      await _start(tester, fake, 2);
      expect(fake.isPlaying(2), isTrue);
      expect(fake.isPlaying(1), isFalse, reason: 'starting B pauses A');

      setOuter(() => showB = false);
      await _settle(tester);
      expect(fake.isPlaying(1), isTrue, reason: 'A is the only one again');
    });

    testWidgets('pauses under a pushed route and resumes when it pops', (
      tester,
    ) async {
      await _host(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              SizedBox(
                height: 200,
                child: V3LoopVideo(asset: _a, fallback: _fallback()),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Next')),
                  ),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await _start(tester, fake, 1);
      expect(fake.isPlaying(1), isTrue);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Next'), findsOneWidget);
      expect(fake.isPlaying(1), isFalse);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await _settle(tester);
      expect(fake.isPlaying(1), isTrue);
    });

    testWidgets('pauses when scrolled out of view and resumes back in it', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _host(
        tester,
        SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              SizedBox(
                height: 300,
                child: V3LoopVideo(asset: _a, fallback: _fallback()),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      );
      await tester.pump();
      await _start(tester, fake, 1);
      expect(fake.isPlaying(1), isTrue);

      controller.jumpTo(600);
      await _settle(tester);
      expect(fake.isPlaying(1), isFalse);

      controller.jumpTo(100);
      await _settle(tester);
      expect(fake.isPlaying(1), isTrue);
    });

    testWidgets('does not play in a tab that isn\'t current (TickerMode)', (
      tester,
    ) async {
      await _host(
        tester,
        TickerMode(
          enabled: false,
          child: V3LoopVideo(asset: _a, fallback: _fallback()),
        ),
      );
      await tester.pump();
      await _start(tester, fake, 1);
      expect(fake.isPlaying(1), isFalse);
    });

    testWidgets('pauses in the background and with playing: false', (
      tester,
    ) async {
      var playing = true;
      late StateSetter setOuter;
      await _host(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return V3LoopVideo(
              asset: _a,
              fallback: _fallback(),
              playing: playing,
            );
          },
        ),
      );
      await tester.pump();
      await _start(tester, fake, 1);
      expect(fake.isPlaying(1), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _settle(tester);
      expect(fake.isPlaying(1), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(fake.isPlaying(1), isTrue);

      setOuter(() => playing = false);
      await _settle(tester);
      expect(fake.isPlaying(1), isFalse);
    });

    testWidgets('disposes its player when removed', (tester) async {
      await _host(tester, V3LoopVideo(asset: _a, fallback: _fallback()));
      await tester.pump();
      await _start(tester, fake, 1);
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(fake.disposed, contains(1));
      expect(V3VideoCoordinator.instance.debugWaiting, 0);
    });
  });

  group('V3BlurWords', () {
    const text = 'Learn from someone you admire.';

    testWidgets('resolves word by word, then every word is sharp', (
      tester,
    ) async {
      await _host(
        tester,
        const V3BlurWords(text: text, delay: Duration(milliseconds: 100)),
      );
      // Before the delay every word is hidden and blurred.
      final opacities = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(V3BlurWords),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity);
      expect(opacities, hasLength(5));
      expect(opacities.every((o) => o == 0), isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      final mid = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(V3BlurWords),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity)
          .toList();
      expect(mid.first, greaterThan(mid.last), reason: 'staggered');

      await tester.pump(const Duration(seconds: 2));
      final filters = tester.widgetList<ImageFiltered>(
        find.descendant(
          of: find.byType(V3BlurWords),
          matching: find.byType(ImageFiltered),
        ),
      );
      expect(filters.every((f) => !f.enabled), isTrue);
    });

    testWidgets('reduced motion: the whole text, no blur or offset', (
      tester,
    ) async {
      await _host(tester, const V3BlurWords(text: text), reduced: true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(text), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(V3BlurWords),
          matching: find.byType(ImageFiltered),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(V3BlurWords),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      final fade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(V3BlurWords),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, 1);
    });

    testWidgets('keeps one accessible label for the whole line', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _host(tester, const V3BlurWords(text: text));
      await tester.pump(const Duration(seconds: 2));
      expect(find.bySemanticsLabel(text), findsOneWidget);
      expect(find.bySemanticsLabel('admire.'), findsNothing);
      expect(find.bySemanticsLabel('Learn'), findsNothing);
      semantics.dispose();
    });
  });

  group('V3Tilt', () {
    Matrix4 matrix(WidgetTester tester) =>
        tester.widget<Transform>(find.byKey(V3Tilt.transformKey)).transform;

    Widget card(VoidCallback onTap) => Center(
      child: V3Tilt(
        child: SizedBox(
          width: 300,
          height: 200,
          child: Center(
            child: TextButton(onPressed: onTap, child: const Text('Go')),
          ),
        ),
      ),
    );

    testWidgets('leans toward the finger and springs back on release', (
      tester,
    ) async {
      await _host(tester, card(() {}));
      final box = tester.getRect(find.byType(V3Tilt));
      final gesture = await tester.startGesture(
        box.topLeft + const Offset(20, 20),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(matrix(tester), isNot(Matrix4.identity()));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(matrix(tester), Matrix4.identity());
    });

    testWidgets('taps reach the buttons inside', (tester) async {
      var taps = 0;
      await _host(tester, card(() => taps++));
      await tester.tap(find.text('Go'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(taps, 1);
    });

    testWidgets('reduced motion: no transform on drag', (tester) async {
      await _host(tester, card(() {}), reduced: true);
      final box = tester.getRect(find.byType(V3Tilt));
      final gesture = await tester.startGesture(
        box.topLeft + const Offset(20, 20),
      );
      await gesture.moveBy(const Offset(200, 120));
      await tester.pump(const Duration(milliseconds: 150));
      expect(matrix(tester), Matrix4.identity());
      await gesture.up();
    });
  });

  group('V3Flame', () {
    testWidgets('lit with motion: embers rise', (tester) async {
      await _host(tester, const Center(child: V3Flame()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(V3Flame.embersKey), findsOneWidget);
    });

    testWidgets('reduced motion or unlit: static, no particles', (
      tester,
    ) async {
      await _host(tester, const Center(child: V3Flame()), reduced: true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(V3Flame.embersKey), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await _host(tester, const Center(child: V3Flame(lit: false)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(V3Flame.embersKey), findsNothing);
    });
  });

  group('showInkReveal', () {
    testWidgets('covers at 480 ms, never blocks taps, is gone by 1.1 s', (
      tester,
    ) async {
      var covered = 0;
      var taps = 0;
      var done = false;
      await _host(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                taps++;
                if (taps == 1) {
                  showInkReveal(
                    context,
                    at: const Offset(195, 400),
                    color: const Color(0xFF141219),
                    onCovered: () => covered++,
                  ).then((_) => done = true);
                }
              },
              child: const Text('Continue'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 470));
      expect(covered, 0);
      // The ink never takes pointer events.
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      expect(taps, 2);
      await tester.pump(const Duration(milliseconds: 20));
      expect(covered, 1);
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, isTrue);
      expect(covered, 1);
    });

    testWidgets('works with a go_router push under the ink', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showInkReveal(
                    context,
                    at: const Offset(10, 10),
                    color: const Color(0xFFF1E7D3),
                    onCovered: () => context.push('/lesson'),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/lesson',
            builder: (context, _) => const Scaffold(body: Text('Lesson')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Lesson'), findsOneWidget);
    });

    testWidgets('reduced motion: a colour fade, covered at 200 ms', (
      tester,
    ) async {
      var covered = false;
      await _host(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showInkReveal(
              context,
              at: Offset.zero,
              color: const Color(0xFF141219),
              onCovered: () => covered = true,
            ),
            child: const Text('Continue'),
          ),
        ),
        reduced: true,
      );
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 210));
      expect(covered, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('V3VideoPortrait', () {
    testWidgets('without a video: today\'s duotone portrait, no player', (
      tester,
    ) async {
      await _host(tester, const V3VideoPortrait(height: 300));
      await tester.pump();
      expect(find.byType(V3Portrait), findsOneWidget);
      expect(fake.created, isEmpty);
    });

    testWidgets('with a video: the duotone until it plays, then the '
        'medallion', (tester) async {
      await _host(
        tester,
        const V3VideoPortrait(video: AppAssets.videoMentorBuffett, height: 300),
      );
      await tester.pump();
      expect(find.byType(V3Portrait), findsOneWidget);
      expect(find.byKey(V3VideoPortrait.medallionKey), findsNothing);

      await _start(tester, fake, 1);
      fake.renderFrame(1);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(V3VideoPortrait.medallionKey), findsOneWidget);
    });

    testWidgets('reduced motion: the duotone portrait, no player', (
      tester,
    ) async {
      await _host(
        tester,
        const V3VideoPortrait(video: AppAssets.videoMentorBuffett, height: 300),
        reduced: true,
      );
      await tester.pump();
      expect(find.byType(V3Portrait), findsOneWidget);
      expect(fake.created, isEmpty);
    });
  });

  group('Celebration video layer', () {
    Future<void> open(
      WidgetTester tester,
      Celebration c, {
      bool reduced = false,
    }) async {
      await _host(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCelebration(context, c),
            child: const Text('Open'),
          ),
        ),
        reduced: reduced,
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('each kind plays its own video, with the vignette', (
      tester,
    ) async {
      await open(tester, Celebration.day(3));
      expect(fake.created.values, [AppAssets.videoCelebrateHabits]);
      expect(find.byKey(CelebrationOverlay.vignetteKey), findsNothing);
      await _start(tester, fake, 1);
      fake.renderFrame(1);
      await _settle(tester);
      expect(find.byKey(CelebrationOverlay.vignetteKey), findsOneWidget);
      expect(_layerOpacity(tester), 0.9);
      // Copy is unchanged.
      expect(find.text('Today’s habits are done.'), findsOneWidget);
    });

    testWidgets('the tutorial kind uses the tutorial video', (tester) async {
      await open(
        tester,
        Celebration.tutorial(completed: 4, total: 8, nextTitle: 'Next'),
      );
      expect(fake.created.values, [AppAssets.videoCelebrateTutorial]);
    });

    testWidgets('reduced motion: no video', (tester) async {
      await open(tester, Celebration.day(3), reduced: true);
      await tester.pump(const Duration(seconds: 1));
      expect(fake.created, isEmpty);
      expect(find.byKey(CelebrationOverlay.haloKey), findsNothing);
    });
  });

  group('Week unlocked', () {
    Future<List<WeekUnlockResult>> open(
      WidgetTester tester, {
      bool missionsReady = true,
      bool reduced = false,
    }) async {
      final results = <WeekUnlockResult>[];
      await _host(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showWeekUnlock(
                context,
                week: 4,
                title: 'Moats and pricing power',
                totalWeeks: 10,
                missionsReady: missionsReady,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
        reduced: reduced,
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      return results;
    }

    testWidgets('copy: pill, kicker with the real week count, honest body', (
      tester,
    ) async {
      await open(tester, missionsReady: false);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Week 4 unlocked'), findsOneWidget);
      expect(find.text('Week 4 of 10'), findsOneWidget);
      expect(
        find.text('Week 3 is complete. Its missions are being prepared.'),
        findsOneWidget,
      );
      expect(find.text('Start week 4'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('copy says the missions are prepared only when ready', (
      tester,
    ) async {
      await open(tester, missionsReady: true);
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.text(
          'Week 3 is complete. Your mentor has prepared the next missions.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('without the video the buttons work from 1.4 s, not before', (
      tester,
    ) async {
      final results = await open(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tap(find.text('Later'), warnIfMissed: false);
      await tester.pump();
      expect(results, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(results, [WeekUnlockResult.later]);
    });

    testWidgets('with the video playing the buttons wait until 2.8 s', (
      tester,
    ) async {
      final results = await open(tester);
      await tester.pump();
      expect(fake.created.values, [AppAssets.videoWeekUnlock]);
      fake
        ..initialize(1)
        ..renderFrame(1);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.tap(find.text('Start week 4'), warnIfMissed: false);
      await tester.pump();
      expect(results, isEmpty);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('Start week 4'));
      await tester.pumpAndSettle();
      expect(results, [WeekUnlockResult.start]);
    });

    testWidgets('reduced motion: no video, still reaches the buttons', (
      tester,
    ) async {
      final results = await open(tester, reduced: true);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 800));
      expect(fake.created, isEmpty);
      expect(find.text('Moats and pricing power'), findsOneWidget);
      await tester.tap(find.text('Start week 4'));
      await tester.pumpAndSettle();
      expect(results, [WeekUnlockResult.start]);
    });
  });

  group('Week-unlock ledger', () {
    test('shows week n once per plan and account, never week 1, and '
        'survives a reload', () async {
      final store = CmpysStore();
      await store.openAccount('acct-1', unkeyedOwner: null);
      expect(store.shouldShowWeekUnlock('plan-a', 1), isFalse);
      expect(store.shouldShowWeekUnlock('plan-a', 2), isTrue);

      await store.markWeekUnlockShown('plan-a', 2);
      expect(store.shouldShowWeekUnlock('plan-a', 2), isFalse);
      expect(store.shouldShowWeekUnlock('plan-a', 3), isTrue);
      expect(store.shouldShowWeekUnlock('plan-b', 2), isTrue);
      store.dispose();

      final reloaded = CmpysStore();
      await reloaded.openAccount('acct-1', unkeyedOwner: null);
      expect(reloaded.shouldShowWeekUnlock('plan-a', 2), isFalse);
      expect(reloaded.shouldShowWeekUnlock('plan-a', 3), isTrue);

      // Another account on this device hasn't seen it.
      await reloaded.openAccount('acct-2', unkeyedOwner: null);
      expect(reloaded.shouldShowWeekUnlock('plan-a', 2), isTrue);
      reloaded.dispose();
    });

    test('says no before an account is open', () {
      final store = CmpysStore();
      expect(store.shouldShowWeekUnlock('plan-a', 2), isFalse);
      store.dispose();
    });

    test('a malformed stored ledger reads what it can', () {
      final ledger = WeekUnlockLedger.parse({
        'p': [2, 'x', 1, 3.0],
        'q': 'nope',
      });
      expect(ledger.shownFor('p'), [2, 3]);
      expect(ledger.shownFor('q'), isEmpty);
    });
  });

  group('Keyframes', () {
    testWidgets('reduced motion: halo and shock draw nothing, fly fades', (
      tester,
    ) async {
      await _host(
        tester,
        const Column(
          children: [
            SizedBox.square(dimension: 40, child: V3HaloRing()),
            SizedBox.square(dimension: 40, child: V3Shock()),
            V3Fly(from: V3FlyFrom.left, child: Text('Me')),
          ],
        ),
        reduced: true,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.descendant(
          of: find.byType(V3HaloRing),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(V3Shock),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(V3Fly),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(V3Fly),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        1,
      );
    });
  });

  testWidgets('frosted presets blur what is behind them', (tester) async {
    await _host(
      tester,
      const Column(
        children: [
          V3Frosted.stage(child: Text('Stage')),
          V3Frosted.secondary(child: Text('Secondary')),
        ],
      ),
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });
}
