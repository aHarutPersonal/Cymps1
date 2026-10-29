// M2 motion & media wiring (SPEC §2, §3, §3b, §8, §9): the mentor lab's
// background video and its states, Buffett's video portrait (and only his),
// the celebrations' per-kind video, and the "Week unlocked" trigger.

import 'package:cmpys/app/assets.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/idol_detail_screen.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/idol_preview_step.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_lab_step.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_video.dart';
import 'package:cmpys/features/cmpys/presentation/plan_screen.dart';
import 'package:cmpys/features/cmpys/presentation/week_unlock_trigger.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_video_player_platform.dart';

void _phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets player events, futures and the 100 ms position poll run.
Future<void> _settle(WidgetTester tester, [int frames = 3]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 110));
  }
}

/// Initialises player [id] and plays a frame of it.
Future<void> _play(
  WidgetTester tester,
  FakeVideoPlayerPlatform fake,
  int id,
) async {
  fake.initialize(id);
  await _settle(tester);
  fake.renderFrame(id);
  await _settle(tester);
}

// ── mentor lab ──────────────────────────────────────────────────────────────

class _NoResults extends Fake implements SessionRepository {
  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) =>
      throw StateError('The lab must not generate results here.');
}

class _LabPlan extends Fake implements PlanRepository {
  _LabPlan(this.status);
  final String status;

  @override
  Future<PlanJobStatus> getJobStatus(String id) async => PlanJobStatus(
    id: id,
    status: status,
    progressPercent: status == 'completed' ? 100 : 40,
    thinkingLine: 'Preparing your first week…',
  );

  @override
  Future<BackendPlan?> getCurrentPlan() async => null;
}

Future<void> _mountLab(
  WidgetTester tester,
  String status, {
  bool reduced = false,
}) async {
  _phone(tester);
  final draft = CmpysOnboardingDraft()
    ..sessionId = 'session-1'
    ..planJobId = 'job-1'
    ..comparisonMd = 'You at 24 have read less, but you write every week.'
    ..blueprintMd = '## Twelve-Week Thesis\nRead like an owner.';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(_NoResults()),
        planRepositoryProvider.overrideWithValue(_LabPlan(status)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: CmpysMentorLabStep(
          idol: cmpysIdols.firstWhere((i) => i.id == 'jobs'),
          draft: draft,
          onDone: () {},
        ),
      ),
    ),
  );
  await _settle(tester);
}

V3LoopVideo _labVideo(WidgetTester tester) =>
    tester.widget<V3LoopVideo>(find.byKey(const Key('mentor-lab-video')));

double _labShade(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const Key('mentor-lab-video-shade')))
    .opacity;

// ── week unlock ─────────────────────────────────────────────────────────────

BackendPlanItem _item(
  String id,
  String title, {
  String type = 'project',
  int week = 1,
  int weekEnd = 0,
  String status = 'not_started',
}) => BackendPlanItem(
  id: id,
  title: title,
  type: type,
  description: '',
  weekStart: week,
  weekEnd: weekEnd == 0 ? week : weekEnd,
  successMetric: '',
  estimatedHours: 2,
  status: status,
  progressPercent: 0,
);

/// A 10-week plan whose current week is [current] (every mission before it
/// is finished).
BackendPlan _plan({int current = 2, String id = 'plan-1'}) => BackendPlan(
  id: id,
  durationWeeks: 10,
  weeklyHours: 5,
  weeklyMinutes: 300,
  items: [
    _item(
      'w1',
      'Find what the business really earns',
      status: current > 1 ? 'completed' : 'not_started',
    ),
    _item(
      'w2',
      'Moats: why profits last',
      week: 2,
      status: current > 2 ? 'completed' : 'not_started',
    ),
    _item('w3', 'Management that thinks like an owner', week: 3),
    _item('h1', 'Read ten pages', type: 'habit', weekEnd: 10),
  ],
);

PlanItemDetailed _detail(String id, {required bool written}) =>
    PlanItemDetailed(
      item: _item(id, 'Mission $id'),
      detailsStatus: written ? 'available' : 'generating',
      lessonFormat: 'tutorial_v1',
      steps: [
        PlanStepDetail(
          id: '$id-s1',
          title: 'First tutorial',
          lessonContent: written ? '# First tutorial' : null,
          readingMinutes: written ? 10 : null,
          practiceMinutes: written ? 5 : null,
          lessonFormat: 'tutorial_v1',
        ),
      ],
    );

class _PlanRepo implements PlanRepository {
  _PlanRepo({this.written = true});
  final bool written;

  @override
  Future<TodayView> getTodayView(String planId) async =>
      const TodayView(items: [], streak: 0, completedToday: 0, totalToday: 0);

  @override
  Future<StreakSummary> getStreak() async =>
      const StreakSummary(current: 0, longest: 0);

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async =>
      _detail(itemId, written: written);

  @override
  Future<PlanItemDetailed> peekPlanItemDetailed(String itemId) async =>
      _detail(itemId, written: false);

  @override
  Future<DailyStatus> getDailyStatus(String itemId) async =>
      DailyStatus(itemId: itemId, days: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plans extends CurrentPlanController {
  _Plans(PlanRepository repo, BackendPlan plan)
    : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(status: CurrentPlanStatus.ready, plan: plan);
  }

  void show(BackendPlan plan) =>
      state = CurrentPlanState(status: CurrentPlanStatus.ready, plan: plan);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> retry() async {}
}

/// An account-backed store whose stored data has loaded.
Future<CmpysStore> _openStore(WidgetTester tester) async {
  final store = CmpysStore();
  await tester.runAsync(() => store.openAccount('acct-1', unkeyedOwner: null));
  return store;
}

Future<_Plans> _mountPlan(
  WidgetTester tester,
  CmpysStore store,
  BackendPlan plan, {
  bool written = true,
  Size size = const Size(430, 1400),
}) async {
  _phone(tester, size: size);
  final repo = _PlanRepo(written: written);
  final plans = _Plans(repo, plan);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => store),
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        planRepositoryProvider.overrideWithValue(repo),
        currentPlanProvider.overrideWith((ref) => plans),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: CmpysPlanScreen(clock: () => DateTime(2026, 10, 25, 14)),
      ),
    ),
  );
  await _settle(tester);
  return plans;
}

/// Past the overlay's phases (no video: buttons from 1.4 s).
Future<void> _toButtons(WidgetTester tester) => _settle(tester, 16);

final _overlay = find.byType(V3WeekUnlockOverlay);

void main() {
  late FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = FakeVideoPlayerPlatform.install();
    SharedPreferences.setMockInitialValues({});
    debugResetWeekUnlockTrigger();
  });
  tearDown(() => V3VideoCoordinator.instance.debugReset());

  group('mentor lab video', () {
    testWidgets('runs at .6 zoomed in, over frosted cards, with its shade', (
      tester,
    ) async {
      await _mountLab(tester, 'running');
      expect(fake.created, {1: AppAssets.videoMentorLab});
      final video = _labVideo(tester);
      expect(video.opacity, 0.6);
      expect(video.scale, 1.1);
      expect(video.saturation, 1);
      expect(video.brightness, 1);
      expect(_labShade(tester), 0);

      await _play(tester, fake, 1);
      expect(_labShade(tester), 1);
      final card = find.byKey(const Key('lab-stage-card'));
      expect(tester.widget(card), isA<V3Frosted>());
      expect(tester.widget<V3Frosted>(card).tint, const Color(0x8C14121C));
      expect(
        find.descendant(
          of: find.byKey(const Key('lab-preview-comparison')),
          matching: find.byType(V3Frosted),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed stage desaturates and dims the video', (
      tester,
    ) async {
      await _mountLab(tester, 'failed');
      await _play(tester, fake, 1);
      expect(find.text('Retry'), findsOneWidget);
      final video = _labVideo(tester);
      expect(video.saturation, 0.3);
      expect(video.brightness, 0.7);
      expect(video.opacity, 0.6);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a ready plan brightens it to .85 and settles the zoom', (
      tester,
    ) async {
      await _mountLab(tester, 'completed');
      await _play(tester, fake, 1);
      expect(find.text('Go to Today'), findsOneWidget);
      final video = _labVideo(tester);
      expect(video.opacity, 0.85);
      expect(video.scale, 1.0);
      expect(video.scaleDuration, const Duration(seconds: 3));
      expect(video.saturation, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('when the video fails the lab keeps today\'s cards', (
      tester,
    ) async {
      await _mountLab(tester, 'running');
      fake.fail(1);
      await _settle(tester);
      expect(_labShade(tester), 0);
      final card = find.byKey(const Key('lab-stage-card'));
      expect(tester.widget(card), isA<Container>());
      expect(find.byType(V3Frosted), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion: no video, today\'s cards', (tester) async {
      await _mountLab(tester, 'running', reduced: true);
      expect(fake.created, isEmpty);
      expect(find.byType(V3Frosted), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('mentor video portrait', () {
    final buffett = cmpysIdols.firstWhere((i) => i.id == 'buffett');
    final curie = cmpysIdols.firstWhere((i) => i.id == 'curie');

    test('only the catalog Buffett has a video', () {
      expect(cmpysIdolVideo(buffett), AppAssets.videoMentorBuffett);
      for (final idol in cmpysIdols.where((i) => i.id != 'buffett')) {
        expect(cmpysIdolVideo(idol), isNull, reason: idol.name);
      }
      // A suggestion for him resolves to the catalog entry.
      expect(
        cmpysIdolVideo(
          cmpysIdolFromSuggestion(
            name: 'Warren Buffett',
            era: '',
            summary: '',
            domains: const [],
            wikidataId: 'Q47213',
          ),
        ),
        AppAssets.videoMentorBuffett,
      );
      // Someone else whose name only looks like his, or whose id reads
      // "buffett", is not him.
      for (final name in ['Buffett', 'Jimmy Buffett', 'Warren E. Buffett']) {
        expect(
          cmpysIdolVideo(
            cmpysIdolFromSuggestion(
              name: name,
              era: '',
              summary: '',
              domains: const [],
            ),
          ),
          isNull,
          reason: name,
        );
      }
      expect(
        cmpysIdolVideo(cmpysIdolFromJson({'id': 'buffett'})),
        AppAssets.videoMentorBuffett,
      );
    });

    Future<void> mountPreview(WidgetTester tester, CmpysIdol idol) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            idolTimelineProvider.overrideWith(
              (ref, name) async => const <IdolTimelineEntry>[],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CmpysIdolPreviewStep(
                idol: idol,
                age: 24,
                onBack: () {},
                onChoose: (_) {},
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    testWidgets('the preview plays the study behind Buffett, with the '
        'medallion and the AI label', (tester) async {
      await mountPreview(tester, buffett);
      expect(fake.created, {1: AppAssets.videoMentorBuffett});
      await _play(tester, fake, 1);
      await _settle(tester, 10);
      expect(find.byKey(V3VideoPortrait.medallionKey), findsOneWidget);
      expect(find.text('AI interpretation · not Buffett'), findsOneWidget);
      expect(find.text('Warren Buffett'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('every other mentor keeps the duotone portrait', (
      tester,
    ) async {
      await mountPreview(tester, curie);
      await _settle(tester, 10);
      expect(fake.created, isEmpty);
      expect(
        tester.widget<V3VideoPortrait>(find.byType(V3VideoPortrait)).video,
        isNull,
      );
      expect(find.byType(V3Portrait), findsOneWidget);
      expect(find.text('AI interpretation · not Curie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the mentor screen: video for Buffett only', (tester) async {
      Future<void> mount(CmpysIdol idol) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              idolTimelineProvider.overrideWith(
                (ref, name) async => const <IdolTimelineEntry>[],
              ),
              cmpysIdeasProvider.overrideWith(
                (ref) async => const <CmpysIdea>[],
              ),
            ],
            child: MaterialApp(home: CmpysIdolDetailScreen(idol: idol)),
          ),
        );
        await _settle(tester);
      }

      _phone(tester);
      await mount(buffett);
      final hero = tester.widget<V3VideoPortrait>(find.byType(V3VideoPortrait));
      expect(hero.video, AppAssets.videoMentorBuffett);
      expect(hero.height, 420);
      expect(hero.tone, buffett.color);
      expect(find.text('AI interpretation · not Buffett'), findsOneWidget);
      expect(
        find.textContaining('They are not messages from Buffett.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await mount(curie);
      expect(
        tester.widget<V3VideoPortrait>(find.byType(V3VideoPortrait)).video,
        isNull,
      );
      expect(fake.created.values, [AppAssets.videoMentorBuffett]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('celebrations', () {
    // The callers build these: the lesson reader `Celebration.tutorial`
    // (practice_workbook_test "finish_shows_celebration") and the habit
    // toggle `Celebration.day` (today_screen_test
    // "all_habits_done_triggers_celebration").
    for (final (name, celebration, asset) in [
      (
        'a finished tutorial plays the tutorial video',
        Celebration.tutorial(completed: 2, total: 6, nextTitle: 'Moats'),
        AppAssets.videoCelebrateTutorial,
      ),
      (
        'finished habits play the habits video',
        Celebration.day(3),
        AppAssets.videoCelebrateHabits,
      ),
    ]) {
      testWidgets(name, (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCelebration(context, celebration),
                child: const Text('celebrate'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('celebrate'));
        await _settle(tester);
        expect(find.byType(CelebrationOverlay), findsOneWidget);
        expect(fake.created.values, [asset]);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('week unlock trigger', () {
    test('is due for the current week after week 1, with week data', () {
      expect(weekUnlockDueWeek(_plan(current: 1)), isNull);
      expect(weekUnlockDueWeek(_plan(current: 2)), 2);
      expect(weekUnlockDueWeek(_plan(current: 3)), 3);
      // An older server without week data puts everything in week 1.
      final flat = BackendPlan(
        id: 'plan-1',
        durationWeeks: 12,
        weeklyHours: 5,
        items: [
          _item('a', 'A', status: 'completed'),
          _item('b', 'B'),
        ],
      );
      expect(weekUnlockDueWeek(flat), isNull);
      // A finished plan unlocks nothing.
      final done = BackendPlan(
        id: 'plan-1',
        durationWeeks: 2,
        weeklyHours: 5,
        items: [
          _item('a', 'A', status: 'completed'),
          _item('b', 'B', week: 2, status: 'completed'),
        ],
      );
      expect(weekUnlockDueWeek(done), isNull);
      // A plan without an id (never saved) neither.
      expect(weekUnlockDueWeek(_plan(id: '')), isNull);
    });

    testWidgets('Plan shows week 2 once: real title and count, ready copy; '
        'Start stays on Plan at this week', (tester) async {
      final store = await _openStore(tester);
      // A short phone, so "This week" starts below the fold.
      await _mountPlan(
        tester,
        store,
        _plan(current: 2),
        size: const Size(390, 520),
      );
      await _toButtons(tester);

      expect(_overlay, findsOneWidget);
      final overlay = tester.widget<V3WeekUnlockOverlay>(_overlay);
      expect(overlay.week, 2);
      expect(overlay.title, 'Moats: why profits last');
      expect(overlay.totalWeeks, 10);
      expect(overlay.missionsReady, isTrue);
      expect(find.text('Week 2 of 10'), findsOneWidget);
      expect(
        find.text(
          'Week 1 is complete. Your mentor has prepared the next missions.',
        ),
        findsOneWidget,
      );
      expect(fake.created.values, contains(AppAssets.videoWeekUnlock));
      expect(store.state.weekUnlocks.shownFor('plan-1'), [2]);

      ScrollPosition position() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CmpysPlanScreen, skipOffstage: false),
                  matching: find.byType(Scrollable, skipOffstage: false),
                )
                .first,
          )
          .position;
      expect(position().pixels, 0);
      await tester.tap(find.text('Start week 2'));
      await _settle(tester, 8);
      expect(_overlay, findsNothing);
      expect(find.byType(CmpysPlanScreen), findsOneWidget);
      // Scrolled so the current week's section is at the top.
      expect(position().pixels, greaterThan(0));
      expect(tester.getTopLeft(find.text('This week')).dy, lessThan(80));

      // Rebuilt and revisited: never again for week 2.
      await _mountPlan(tester, store, _plan(current: 2));
      await _toButtons(tester);
      expect(_overlay, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('missions not yet written: honest copy; Later just closes', (
      tester,
    ) async {
      final store = await _openStore(tester);
      await _mountPlan(tester, store, _plan(current: 2), written: false);
      await _toButtons(tester);
      expect(tester.widget<V3WeekUnlockOverlay>(_overlay).missionsReady, false);
      expect(
        find.text('Week 1 is complete. Its missions are being prepared.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Later'));
      await _settle(tester, 8);
      expect(_overlay, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the next week shows when the plan moves on', (tester) async {
      final store = await _openStore(tester);
      final plans = await _mountPlan(tester, store, _plan(current: 2));
      await _toButtons(tester);
      await tester.tap(find.text('Later'));
      await _settle(tester, 8);
      expect(_overlay, findsNothing);

      plans.show(_plan(current: 3));
      await _toButtons(tester);
      expect(tester.widget<V3WeekUnlockOverlay>(_overlay).week, 3);
      expect(store.state.weekUnlocks.shownFor('plan-1'), [2, 3]);
      await tester.tap(find.text('Later'));
      await _settle(tester, 8);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('never for week 1, nor before the account has loaded', (
      tester,
    ) async {
      final store = await _openStore(tester);
      await _mountPlan(tester, store, _plan(current: 1));
      await _toButtons(tester);
      expect(_overlay, findsNothing);

      // No account open: the ledger can't tell, so nothing shows.
      await _mountPlan(tester, CmpysStore(), _plan(current: 2));
      await _toButtons(tester);
      expect(_overlay, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('not without week data', (tester) async {
      final store = await _openStore(tester);
      await _mountPlan(
        tester,
        store,
        BackendPlan(
          id: 'plan-1',
          durationWeeks: 12,
          weeklyHours: 5,
          items: [
            _item('a', 'A', status: 'completed'),
            _item('b', 'B'),
          ],
        ),
      );
      await _toButtons(tester);
      expect(_overlay, findsNothing);
      expect(store.state.weekUnlocks.isEmpty, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
