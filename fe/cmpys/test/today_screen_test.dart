import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/today_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/material_web_screen.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_web_platforms.dart';

/// Sunday 25 October 2026, 14:30 local.
final _now = DateTime(2026, 10, 25, 14, 30);

BackendPlanItem _mission() => const BackendPlanItem(
  id: 'mission-1',
  title: 'Find what the business really earns',
  type: 'project',
  description: '',
  weekStart: 1,
  weekEnd: 1,
  successMetric: '',
  estimatedHours: 2,
  status: 'in_progress',
  progressPercent: 30,
);

BackendPlanItem _habitItem(String id) => BackendPlanItem(
  id: id,
  title: 'Habit $id',
  type: 'habit',
  description: '',
  weekStart: 1,
  weekEnd: 12,
  successMetric: '',
  estimatedHours: 1,
  status: 'in_progress',
  progressPercent: 0,
);

BackendPlan _plan() => BackendPlan(
  id: 'plan-1',
  durationWeeks: 12,
  weeklyHours: 4,
  idolName: 'Warren Buffett',
  createdAt: _now.subtract(const Duration(days: 15)),
  items: [_mission(), _habitItem('h1'), _habitItem('h2')],
);

PlanItemDetailed _missionDetail() => PlanItemDetailed(
  item: _mission(),
  detailsStatus: 'available',
  lessonFormat: 'tutorial_v1',
  steps: const [
    PlanStepDetail(
      id: 's1',
      title: 'Reported earnings are an opinion',
      readingMinutes: 4,
      practiceMinutes: 3,
      lessonContent: '# One',
      lessonFormat: 'tutorial_v1',
    ),
    PlanStepDetail(
      id: 's2',
      title: 'Owner earnings, step by step',
      readingMinutes: 4,
      practiceMinutes: 5,
      lessonContent: '# Two',
      lessonFormat: 'tutorial_v1',
    ),
    PlanStepDetail(
      id: 's3',
      title: 'Maintenance versus growth capex',
      lessonFormat: 'tutorial_v1',
    ),
  ],
  completedStepIds: const {'s1'},
);

class _Habit {
  _Habit(
    this.id,
    this.title, {
    this.minutes = 70,
    this.session,
    this.done = false,
  });
  final String id;
  final String title;
  final int minutes;
  final int? session;
  bool done;
}

/// Tutorials still being written: no readable current step, job running.
PlanItemDetailed _preparingDetail() => PlanItemDetailed(
  item: _mission(),
  detailsStatus: 'generating',
  lessonFormat: 'tutorial_v1',
  jobId: 'job-1',
  steps: const [
    PlanStepDetail(id: 's1', title: 'One', lessonFormat: 'tutorial_v1'),
    PlanStepDetail(id: 's2', title: 'Two', lessonFormat: 'tutorial_v1'),
  ],
);

class _FakePlanRepository implements PlanRepository {
  _FakePlanRepository(this.habits, {this.streak = 4, this.detail});

  final List<_Habit> habits;
  final int streak;
  PlanItemDetailed Function()? detail;
  int todayLoads = 0;
  int detailLoads = 0;
  int toggles = 0;
  bool failToday = false;
  bool failDetail = false;

  @override
  Future<TodayView> getTodayView(String planId) async {
    todayLoads++;
    if (failToday) throw StateError('today failed');
    final items = [
      for (final h in habits)
        TodayTaskItem(
          id: h.id,
          title: h.title,
          type: 'habit',
          estimatedHours: 2,
          estimatedMinutes: h.minutes,
          sessionMinutes: h.session,
          completedToday: h.done,
          dailyInstructions: 'Instructions for ${h.title}.',
        ),
    ];
    return TodayView(
      items: items,
      streak: streak,
      completedToday: habits.where((h) => h.done).length,
      totalToday: habits.length,
    );
  }

  @override
  Future<bool> toggleDailyTask(String itemId) async {
    toggles++;
    final habit = habits.firstWhere((h) => h.id == itemId);
    habit.done = !habit.done;
    return habit.done;
  }

  @override
  Future<StreakSummary> getStreak() async => StreakSummary(
    current: streak,
    longest: 9,
    lastActive: DateTime(_now.year, _now.month, _now.day - 1),
  );

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async {
    detailLoads++;
    if (failDetail) throw StateError('detail failed');
    return (detail ?? _missionDetail)();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeContentResources implements ContentResourcesRepository {
  _FakeContentResources({this.resume});

  final ContentResource? resume;

  @override
  Future<ContentResource?> getContinueReading() async => resume;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanController extends CurrentPlanController {
  _PlanController(PlanRepository repo, CurrentPlanState initial)
    : super(repo: repo, readJobId: () => null) {
    state = initial;
  }

  int retries = 0;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> retry() async {
    retries++;
    state = CurrentPlanState(status: CurrentPlanStatus.ready, plan: _plan());
  }
}

class _TestStore extends CmpysStore {
  _TestStore() {
    state = state.copyWith(
      user: CmpysUser(name: 'Maya Chen', age: 24),
      idol: const CmpysIdol(
        id: 'buffett',
        slug: '__llm__',
        name: 'Warren Buffett',
        short: 'Buffett',
        initials: 'WB',
        title: 'Investor',
        era: '',
        field: 'Investing',
        color: AppColors.iris,
        tint: AppColors.irisSoft,
        tag: '',
        blurb: '',
        quote: '',
      ),
    );
  }
}

const _idea = CmpysIdea(
  id: 'idea-1',
  text: 'Price is what you pay; value is what you get.',
  author: 'Warren Buffett',
  tag: 'Investing',
  tone: AppColors.iris,
  likes: 0,
);

/// A narration session on [book] that is playing.
class _NarratingRemote extends BookNarrationRemoteController {
  _NarratingRemote(this.book);

  final String book;
  int toggles = 0;

  @override
  bool get active => true;

  @override
  String? get resourceId => book;

  @override
  bool get playing => true;

  @override
  Future<void> toggle() async => toggles++;
}

class _Harness {
  _Harness({
    required this.repo,
    required CurrentPlanState initial,
    _TestStore? store,
    this.resume,
    this.remote,
  }) : store = store ?? _TestStore() {
    controller = _PlanController(repo, initial);
  }

  /// The continue-reading entry the content repository returns.
  final ContentResource? resume;

  /// The narration session, when a test sets one.
  final BookNarrationRemoteController? remote;
  final _FakePlanRepository repo;
  final _TestStore store;
  late final _PlanController controller;

  Widget build({
    Widget Function(Widget screen)? wrap,
    GlobalKey<NavigatorState>? navigatorKey,
  }) => ProviderScope(
    overrides: [
      cmpysStoreProvider.overrideWith((ref) => store),
      cmpysBackendSyncProvider.overrideWith((ref) async {}),
      cmpysIdeasProvider.overrideWith((ref) async => const [_idea]),
      planRepositoryProvider.overrideWithValue(repo),
      contentResourcesRepositoryProvider.overrideWithValue(
        _FakeContentResources(resume: resume),
      ),
      currentPlanProvider.overrideWith((ref) => controller),
      if (remote case final remote?)
        bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      navigatorKey: navigatorKey,
      home: (wrap ?? (screen) => screen)(CmpysTodayScreen(clock: () => _now)),
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

/// Lets toasts, rises and count-ups finish so no timer outlives the test.
Future<void> _settleTimers(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

CurrentPlanState _ready() =>
    CurrentPlanState(status: CurrentPlanStatus.ready, plan: _plan());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('greeting', () {
    test('greeting_by_local_hour', () {
      expect(greetingForHour(4), 'Good evening,');
      expect(greetingForHour(5), 'Good morning,');
      expect(greetingForHour(11), 'Good morning,');
      expect(greetingForHour(12), 'Good afternoon,');
      expect(greetingForHour(17), 'Good afternoon,');
      expect(greetingForHour(18), 'Good evening,');
      expect(greetingForHour(23), 'Good evening,');
      expect(greetingForHour(0), 'Good evening,');
    });

    testWidgets('header shows the date kicker, greeting by hour and tags', (
      tester,
    ) async {
      final harness = _Harness(
        repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
        initial: _ready(),
      );
      await _pumpScreen(tester, harness.build());

      expect(find.text('SUNDAY · 25 OCTOBER'), findsOneWidget);
      // The greeting resolves word by word (`BlurWords`), then the name.
      Finder blurWords(String text) =>
          find.byWidgetPredicate((w) => w is V3BlurWords && w.text == text);
      expect(blurWords('Good afternoon,'), findsOneWidget);
      expect(blurWords('Maya.'), findsOneWidget);
      expect(
        tester.widget<V3BlurWords>(blurWords('Maya.')).delay,
        const Duration(milliseconds: 160),
      );
      expect(find.text('Day 16 of 84'), findsOneWidget);
      expect(find.text('Week 1 · Buffett'), findsOneWidget);
      // NextUp: the first unfinished tutorial of the current mission.
      expect(find.text('Up next · Tutorial 2 of 3'), findsOneWidget);
      expect(find.text('Owner earnings, step by step'), findsOneWidget);
      expect(
        find.text('Mission · Find what the business really earns'),
        findsOneWidget,
      );
      expect(find.text('4 min read · 5 min practice'), findsOneWidget);
      expect(find.text('Idea for today'), findsOneWidget);
      // Today's open streak day is a full-width dashed cell, not a hairline.
      final todayCell = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_DashedRRectPainter',
      );
      expect(todayCell, findsOneWidget);
      expect(tester.getSize(todayCell).width, greaterThan(8));
      expect(tester.getSize(todayCell).height, 18);
      await _settleTimers(tester);
    });
  });

  group('book-aware Listen', () {
    const resume = ContentResource(
      id: 'r1',
      kind: 'llm_book_summary',
      canonicalKey: 'book:essays',
      title: 'The Essays of Warren Buffett',
      authorOrCreator: 'Lawrence Cunningham',
      licenseStatus: 'llm_summary',
      isSaved: false,
      progressPercent: 40,
    );
    Finder listenButton(String label) => find.byWidgetPredicate(
      (widget) => widget is V3Pressable && widget.semanticLabel == label,
    );

    testWidgets('the card shows waves while its own book plays', (
      tester,
    ) async {
      final remote = _NarratingRemote('r1');
      final harness = _Harness(
        repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
        initial: _ready(),
        resume: resume,
        remote: remote,
      );
      await _pumpScreen(tester, harness.build());
      expect(listenButton('Listening'), findsOneWidget);
      expect(
        find.descendant(
          of: listenButton('Listening'),
          matching: find.byType(BookNarrationWaves),
        ),
        findsOneWidget,
      );
      // Listen on the book already playing toggles it in place.
      await tester.tap(listenButton('Listening'));
      await tester.pump();
      expect(remote.toggles, 1);
      expect(find.byType(BookReaderScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _settleTimers(tester);
    });

    testWidgets('another book playing: Listen opens this one and starts it', (
      tester,
    ) async {
      final remote = _NarratingRemote('other-book');
      final harness = _Harness(
        repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
        initial: _ready(),
        resume: resume,
        remote: remote,
      );
      await _pumpScreen(tester, harness.build());
      expect(listenButton('Listen'), findsOneWidget);
      expect(find.byType(BookNarrationWaves), findsNothing);
      await tester.tap(listenButton('Listen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(remote.toggles, 0);
      final reader = tester.widget<BookReaderScreen>(
        find.byType(BookReaderScreen),
      );
      expect(reader.resourceId, 'r1');
      expect(reader.startNarrationOnOpen, isTrue);
      // Pushed in Today's branch, so its player and resume say Today.
      expect(
        reader.shellBranchIndex,
        ActiveBookNarrationResume.todayBranchIndex,
      );
      await tester.pumpWidget(const SizedBox());
      await _settleTimers(tester);
    });
  });

  testWidgets('one book gets one cover on the continue card and the shelf', (
    tester,
  ) async {
    const title = 'The Essays of Warren Buffett: Lessons for Investors';
    const resume = ContentResource(
      id: 'r1',
      kind: 'llm_book_summary',
      canonicalKey: 'book:essays',
      title: title,
      authorOrCreator: 'Lawrence Cunningham',
      licenseStatus: 'llm_summary',
      isSaved: false,
      progressPercent: 40,
    );
    final base = _missionDetail();
    final repo = _FakePlanRepository(
      [_Habit('h1', 'Read ten pages')],
      detail: () => PlanItemDetailed(
        item: base.item,
        detailsStatus: base.detailsStatus,
        lessonFormat: base.lessonFormat,
        steps: base.steps,
        completedStepIds: base.completedStepIds,
        materials: const [
          // An earlier shelf book comes first, so position 0 is not r1's.
          PlanMaterialDetail(
            title: 'Poor Charlie’s Almanack, Third Edition',
            type: 'book',
            contentResourceId: 'r0',
            authorOrCreator: 'Charles Munger',
          ),
          PlanMaterialDetail(
            title: title,
            type: 'book',
            contentResourceId: 'r1',
            authorOrCreator: 'Lawrence Cunningham',
          ),
        ],
      ),
    );
    final harness = _Harness(repo: repo, initial: _ready(), resume: resume);
    await _pumpScreen(tester, harness.build());

    final covers = tester.widgetList<V3Cover>(find.byType(V3Cover)).toList();
    // The continue card (64 wide) and the two shelf covers (118 wide).
    final card = covers.singleWhere((c) => c.width == 64);
    final shelf = covers.where((c) => c.width == 118).toList();
    expect(shelf, hasLength(2));
    final essays = shelf.singleWhere((c) => c.author == 'Lawrence Cunningham');
    expect(card.background, v3CoverGround('r1'));
    expect(essays.background, card.background);
    expect(essays.foreground, card.foreground);
    // Both cut the subtitle; the comma title is kept whole.
    expect(card.title, 'The Essays of Warren Buffett');
    expect(essays.title, card.title);
    expect(
      shelf.singleWhere((c) => c.author == 'Charles Munger').title,
      'Poor Charlie’s Almanack, Third Edition',
    );
    await _settleTimers(tester);
  });

  testWidgets('a web material opens the web viewer as a web source', (
    tester,
  ) async {
    // The web viewer builds on a fake platform (a test has no web view);
    // the previous platform is restored when the test ends.
    useFakeWebViewPlatform();
    final base = _missionDetail();
    final repo = _FakePlanRepository(
      [_Habit('h1', 'Read ten pages')],
      detail: () => PlanItemDetailed(
        item: base.item,
        detailsStatus: base.detailsStatus,
        lessonFormat: base.lessonFormat,
        steps: base.steps,
        completedStepIds: base.completedStepIds,
        materials: const [
          PlanMaterialDetail(
            title: 'Owner earnings',
            type: 'article',
            url: 'https://example.org/owner-earnings',
          ),
        ],
      ),
    );
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    await tester.tap(find.byType(V3Cover));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final screen = tester.widget<MaterialWebScreen>(
      find.byType(MaterialWebScreen),
    );
    expect(screen.url, 'https://example.org/owner-earnings');
    expect(screen.access, AccessType.web);
    await _settleTimers(tester);
  });

  testWidgets('failed_state_retry_reloads', (tester) async {
    final repo = _FakePlanRepository([_Habit('h1', 'Read ten pages')]);
    final harness = _Harness(
      repo: repo,
      initial: const CurrentPlanState(
        status: CurrentPlanStatus.failed,
        error: 'boom',
      ),
    );
    await _pumpScreen(tester, harness.build());

    expect(find.text('We couldn’t load your plan'), findsOneWidget);
    expect(
      find.text(
        'Nothing was lost. Your progress is saved on the server; this screen '
        'just failed to read it.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(harness.controller.retries, 1);
    expect(find.text('We couldn’t load your plan'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Read ten pages'), findsOneWidget);
    expect(repo.todayLoads, greaterThanOrEqualTo(1));
    await _settleTimers(tester);
  });

  testWidgets('a failed habits load shows Try again, which refetches it', (
    tester,
  ) async {
    final repo = _FakePlanRepository([_Habit('h1', 'Read ten pages')])
      ..failToday = true;
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    expect(find.text('We couldn’t load your plan'), findsOneWidget);
    final loadsBefore = repo.todayLoads;
    repo.failToday = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(repo.todayLoads, loadsBefore + 1);
    expect(find.text('We couldn’t load your plan'), findsNothing);
    expect(find.text('Read ten pages'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('all_habits_done_triggers_celebration', (tester) async {
    // One habit already done today, so the server streak (4) already counts
    // today: the celebration gets 3 as the streak before today and shows 4.
    final repo = _FakePlanRepository([
      _Habit('h1', 'Read ten pages', done: true),
      _Habit('h2', 'One honest sentence'),
    ], streak: 4);
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    expect(find.text('1/2'), findsOneWidget);
    final undone = find.byWidgetPredicate((w) => w is V3CheckDot && !w.done);
    expect(undone, findsOneWidget);
    await tester.tap(undone);
    await tester.pump();

    // Optimistic: checked and struck through at once, before the server.
    expect(
      find.byWidgetPredicate((w) => w is V3CheckDot && !w.done),
      findsNothing,
    );
    expect(find.text('All done. Counted for today only.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 500));

    expect(repo.toggles, 1);
    expect(find.byType(CelebrationOverlay), findsOneWidget);
    expect(find.text('Today’s habits are done.'), findsOneWidget);
    final overlay = tester.widget<CelebrationOverlay>(
      find.byType(CelebrationOverlay),
    );
    expect(overlay.celebration.kind, CelebrationKind.day);
    expect(overlay.celebration.stat, 4);
    expect(find.text('Done for today'), findsNothing);
    await _settleTimers(tester);
  });

  group('motion (SPEC §4)', () {
    Widget reduced(Widget screen) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: screen,
      ),
    );

    /// The ink layer's painter (the reveal's growing circle), if any.
    Finder ink() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint && w.painter.runtimeType.toString() == '_InkPainter',
    );

    double fill(WidgetTester tester) => tester
        .widget<Transform>(find.byKey(todayStreakFillKey))
        .transform
        .entry(1, 1);

    Finder dashed() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_DashedRRectPainter',
    );

    testWidgets('Continue: the ink in the reader colour opens the tutorial '
        'once it covers', (tester) async {
      final harness = _Harness(
        repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
        initial: _ready(),
      );
      harness.store.setReadTheme('sepia');
      await _pumpScreen(tester, harness.build());

      final play = find.byWidgetPredicate(
        (w) => w is V3Pressable && w.semanticLabel == 'Continue tutorial',
      );
      final centre = tester.getCenter(play);
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Growing from the button, in the sepia page colour; nothing opened.
      expect(ink(), findsOneWidget);
      final painter = tester.widget<CustomPaint>(ink()).painter! as dynamic;
      expect(painter.color, const Color(0xFFF1E7D3));
      expect(painter.at, centre);
      expect(find.byType(LessonReaderScreen), findsNothing);

      // 480 ms: covered, the tutorial opens underneath.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(LessonReaderScreen), findsOneWidget);
      expect(
        tester
            .widget<LessonReaderScreen>(find.byType(LessonReaderScreen))
            .step
            .id,
        's2',
      );
      // Gone by 1.1 s.
      await tester.pump(const Duration(milliseconds: 700));
      expect(ink(), findsNothing);
      Navigator.of(tester.element(find.byType(LessonReaderScreen))).pop();
      await _settleTimers(tester);
    });

    testWidgets('the Up next card tilts under the finger and its buttons '
        'still work', (tester) async {
      final harness = _Harness(
        repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
        initial: _ready(),
      );
      await _pumpScreen(tester, harness.build());
      final tilt = find.byKey(V3Tilt.transformKey);
      expect(tilt, findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.text('Owner earnings, step by step')) +
            const Offset(4, 4),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.widget<Transform>(tilt).transform,
        isNot(Matrix4.identity()),
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.widget<Transform>(tilt).transform, Matrix4.identity());

      // "Up next" still opens the mission.
      await tester.tap(find.text('Up next · Tutorial 2 of 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PlanItemDetailScreen), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('the streak flame flickers beside the count', (tester) async {
      final harness = _Harness(
        repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
        initial: _ready(),
      );
      await _pumpScreen(tester, harness.build());
      final flame = tester.widget<V3Flame>(find.byType(V3Flame));
      expect(flame.size, 22);
      expect(find.byKey(V3Flame.embersKey), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('today’s cell fills by habits done, with a crest while '
        'partly full', (tester) async {
      final repo = _FakePlanRepository([
        _Habit('h1', 'Read ten pages', done: true),
        _Habit('h2', 'One honest sentence'),
        _Habit('h3', 'Walk'),
      ]);
      final harness = _Harness(repo: repo, initial: _ready());
      await _pumpScreen(tester, harness.build());
      await tester.pump(const Duration(milliseconds: 1000));
      expect(fill(tester), closeTo(1 / 3, 1e-9));
      expect(find.byKey(todayStreakCrestKey), findsOneWidget);
      expect(dashed(), findsOneWidget);

      // A second habit: the fill springs up over .9 s.
      await tester.tap(
        find.byWidgetPredicate((w) => w is V3CheckDot && !w.done).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fill(tester), inExclusiveRange(1 / 3, 2 / 3 + .1));
      await tester.pump(const Duration(milliseconds: 900));
      expect(fill(tester), closeTo(2 / 3, 1e-9));
      expect(find.byKey(todayStreakCrestKey), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('all habits done: a full cell, no dashes, no crest', (
      tester,
    ) async {
      final repo = _FakePlanRepository([
        _Habit('h1', 'Read ten pages', done: true),
        _Habit('h2', 'One honest sentence', done: true),
      ]);
      final harness = _Harness(repo: repo, initial: _ready());
      await _pumpScreen(tester, harness.build());
      await tester.pump(const Duration(milliseconds: 1000));
      expect(fill(tester), 1);
      expect(find.byKey(todayStreakCrestKey), findsNothing);
      expect(dashed(), findsNothing);
      await _settleTimers(tester);
    });

    testWidgets('reduced motion: plain greeting, no tilt, static flame, the '
        'fill jumps, no crest, and the reveal is a fade', (tester) async {
      final repo = _FakePlanRepository([
        _Habit('h1', 'Read ten pages', done: true),
        _Habit('h2', 'One honest sentence'),
      ]);
      final harness = _Harness(repo: repo, initial: _ready());
      await _pumpScreen(tester, harness.build(wrap: reduced));

      // BlurWords fall back to one plain text each.
      expect(find.text('Good afternoon,'), findsOneWidget);
      expect(find.text('Maya.'), findsOneWidget);
      expect(find.byKey(V3Flame.embersKey), findsNothing);
      expect(fill(tester), .5);
      expect(find.byKey(todayStreakCrestKey), findsNothing);

      final tilt = find.byKey(V3Tilt.transformKey);
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.text('Owner earnings, step by step')) +
            const Offset(4, 4),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<Transform>(tilt).transform, Matrix4.identity());
      await gesture.up();
      await tester.pump();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is V3Pressable && w.semanticLabel == 'Continue tutorial',
        ),
      );
      await tester.pump();
      // No growing circle: a colour fade, covered at 200 ms.
      expect(ink(), findsNothing);
      await tester.pump(const Duration(milliseconds: 210));
      await tester.pump();
      expect(find.byType(LessonReaderScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      Navigator.of(tester.element(find.byType(LessonReaderScreen))).pop();
      await _settleTimers(tester);
    });
  });

  testWidgets('habit minutes are the server’s session minutes', (tester) async {
    final repo = _FakePlanRepository([
      _Habit('h1', 'Set a 5-minute timer and read', minutes: 15, session: 5),
      _Habit('h2', 'One honest sentence', minutes: 48, session: 12),
    ]);
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('About 17 minutes left'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('a habit that is not the last shows the toast, no celebration', (
    tester,
  ) async {
    final repo = _FakePlanRepository([
      _Habit('h1', 'Read ten pages', minutes: 70),
      _Habit('h2', 'One honest sentence', minutes: 21),
    ]);
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    // An older server sends only weekly minutes: a seventh, 70 → 10, 21 → 3.
    expect(find.text('About 13 minutes left'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate((w) => w is V3CheckDot && !w.done).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Done for today'), findsOneWidget);
    expect(find.byType(CelebrationOverlay), findsNothing);
    expect(find.text('About 3 minutes left'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('a failed toggle rolls the check back', (tester) async {
    final repo = _ThrowingToggleRepository([_Habit('h1', 'Read ten pages')]);
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    await tester.tap(find.byWidgetPredicate((w) => w is V3CheckDot && !w.done));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byWidgetPredicate((w) => w is V3CheckDot && !w.done),
      findsOneWidget,
    );
    expect(find.byType(CelebrationOverlay), findsNothing);
    expect(find.text('Couldn’t update — try again.'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('reflection_autosaves', (tester) async {
    final harness = _Harness(
      repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
      initial: _ready(),
    );
    await _pumpScreen(tester, harness.build());

    expect(
      find.text('Which number in today’s reading did you not trust, and why?'),
      findsOneWidget,
    );
    final field = find.byKey(CmpysTodayScreen.reflectionFieldKey);
    await tester.enterText(field, 'The capex split.');
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Saving'), findsOneWidget);
    expect(harness.store.state.reflections, isEmpty);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Saved for today'), findsOneWidget);
    expect(harness.store.state.reflections, {
      reflectionDateKey(_now): 'The capex split.',
    });

    await _settleTimers(tester);
  });

  testWidgets('a reflection saved today shows on open as saved', (
    tester,
  ) async {
    final store = _TestStore();
    store.setReflection(reflectionDateKey(_now), 'The capex split.');
    final harness = _Harness(
      repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
      initial: _ready(),
      store: store,
    );
    await _pumpScreen(tester, harness.build());

    expect(find.text('The capex split.'), findsOneWidget);
    expect(find.text('Saved for today'), findsOneWidget);
    expect(find.text('Unsaved'), findsNothing);
    await _settleTimers(tester);
  });

  testWidgets('a reflection hydrated after the first build fills the field', (
    tester,
  ) async {
    final harness = _Harness(
      repo: _FakePlanRepository([_Habit('h1', 'Read ten pages')]),
      initial: _ready(),
    );
    await _pumpScreen(tester, harness.build());
    expect(find.text('Saved for today'), findsNothing);

    // The store loads from the device after the screen first builds.
    harness.store.setReflection(reflectionDateKey(_now), 'Loaded later.');
    await tester.pump();

    expect(find.text('Loaded later.'), findsOneWidget);
    expect(find.text('Saved for today'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('a failed lesson generation offers the mission, not a reload', (
    tester,
  ) async {
    final cases = <(PlanItemDetailed, String, String)>[
      (
        PlanItemDetailed(
          item: _mission(),
          detailsStatus: 'failed',
          detailsError: 'This lesson could not be prepared.',
          lessonFormat: 'tutorial_v1',
          steps: const [
            PlanStepDetail(id: 's1', title: 'One', lessonFormat: 'tutorial_v1'),
          ],
        ),
        'This lesson could not be prepared.',
        'Please generate it again.',
      ),
      (
        PlanItemDetailed(
          item: _mission(),
          detailsStatus: 'failed',
          detailsStep: 'catalog_not_available',
          lessonFormat: 'tutorial_v1',
        ),
        'This lesson isn’t available yet.',
        'The learning materials and practice for this task aren’t ready. '
            'Retrying now won’t prepare them. Your completed work is saved.',
      ),
      (
        // Partial with an error, after the ready tutorials are done.
        PlanItemDetailed(
          item: _mission(),
          detailsStatus: 'partial',
          detailsError: 'Some lessons are not ready yet.',
          lessonFormat: 'tutorial_v1',
          steps: const [
            PlanStepDetail(
              id: 's1',
              title: 'One',
              lessonContent: '# One',
              lessonFormat: 'tutorial_v1',
            ),
            PlanStepDetail(id: 's2', title: 'Two', lessonFormat: 'tutorial_v1'),
          ],
          completedStepIds: const {'s1'},
        ),
        'Some lessons could not be prepared.',
        'Your ready lessons and progress are saved.',
      ),
    ];
    for (final (detail, title, body) in cases) {
      final repo = _FakePlanRepository([
        _Habit('h1', 'Read ten pages'),
      ], detail: () => detail);
      final harness = _Harness(repo: repo, initial: _ready());
      await _pumpScreen(tester, harness.build());

      expect(find.text(title), findsOneWidget);
      expect(find.text(body), findsOneWidget);
      expect(find.text('We couldn’t load your plan'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Preparing this week’s tutorials'), findsNothing);
      // Habits stay usable below.
      expect(find.text('Read ten pages'), findsOneWidget);

      final loads = repo.detailLoads;
      await tester.pump(const Duration(seconds: 40));
      expect(repo.detailLoads, loads, reason: 'a stopped job is not polled');
      await tester.pumpWidget(const SizedBox());
    }

    // "Open mission" opens the mission screen, where "Generate again" is.
    final repo = _FakePlanRepository([
      _Habit('h1', 'Read ten pages'),
    ], detail: () => cases.first.$1);
    await _pumpScreen(tester, _Harness(repo: repo, initial: _ready()).build());
    await tester.tap(find.text('Open mission'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PlanItemDetailScreen), findsOneWidget);
    // Opened from Today, so its books say Today and resume into Today.
    expect(
      tester
          .widget<PlanItemDetailScreen>(find.byType(PlanItemDetailScreen))
          .shellBranchIndex,
      ActiveBookNarrationResume.todayBranchIndex,
    );
    await _settleTimers(tester);
  });

  testWidgets('a failed mission load keeps the reload card, which refetches', (
    tester,
  ) async {
    final repo = _FakePlanRepository([_Habit('h1', 'Read ten pages')])
      ..failDetail = true;
    final harness = _Harness(repo: repo, initial: _ready());
    await _pumpScreen(tester, harness.build());

    expect(find.text('We couldn’t load your plan'), findsOneWidget);
    expect(find.text('Open mission'), findsNothing);
    final loads = repo.detailLoads;
    repo.failDetail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(repo.detailLoads, loads + 1);
    expect(find.text('We couldn’t load your plan'), findsNothing);
    expect(find.text('Up next · Tutorial 2 of 3'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('the preparing poll pauses offstage, under a route and in the '
      'background, and re-reads once on return', (tester) async {
    final repo = _FakePlanRepository([
      _Habit('h1', 'Read ten pages'),
    ], detail: _preparingDetail);
    final harness = _Harness(repo: repo, initial: _ready());
    final onTab = ValueNotifier<bool>(true);
    addTearDown(onTab.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await _pumpScreen(
      tester,
      harness.build(
        navigatorKey: navigator,
        wrap: (screen) => ValueListenableBuilder<bool>(
          valueListenable: onTab,
          builder: (context, on, child) =>
              TickerMode(enabled: on, child: child!),
          child: screen,
        ),
      ),
    );
    expect(find.text('Preparing this week’s tutorials'), findsOneWidget);
    expect(repo.detailLoads, 1);

    Future<void> wait(int seconds) async {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }

    // On screen: one read every 15 s.
    await wait(15);
    expect(repo.detailLoads, 2);

    // Another tab (the shell turns TickerMode off): no reads.
    onTab.value = false;
    await tester.pump();
    await wait(60);
    expect(repo.detailLoads, 2);

    // Back on the tab: one read at once, then every 15 s again.
    onTab.value = true;
    await tester.pump();
    await tester.pump();
    expect(repo.detailLoads, 3);
    await wait(15);
    expect(repo.detailLoads, 4);

    // A page pushed over Today: no reads until it pops.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await wait(60);
    expect(repo.detailLoads, 4);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.detailLoads, 5);

    // App in the background: no reads; foreground again re-reads once.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await wait(60);
    expect(repo.detailLoads, 5);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump();
    expect(repo.detailLoads, 6);
    await _settleTimers(tester);
  });

  group('today data helpers', () {
    test('the streak week marks the known run and leaves today open', () {
      // Sunday 25 Oct; a 3-day run ending Saturday → Thu, Fri, Sat done.
      final week = streakWeek(
        StreakSummary(
          current: 3,
          longest: 9,
          lastActive: DateTime(2026, 10, 24),
        ),
        _now,
      );
      expect(week, [false, false, false, true, true, true, null]);
      expect(streakWeek(null, _now), [
        false,
        false,
        false,
        false,
        false,
        false,
        null,
      ]);
    });

    test('materials map to access types', () {
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Essays',
            type: 'book',
            contentResourceId: 'r1',
          ),
        ),
        AccessType.guide,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Letter',
            type: 'article',
            url: 'https://www.berkshirehathaway.com/letters/1986.html',
          ),
        ),
        AccessType.web,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Lecture',
            type: 'video',
            url: 'https://www.youtube.com/watch?v=abc',
          ),
        ),
        AccessType.video,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(title: 'Almanack', type: 'book'),
        ),
        AccessType.none,
      );
      // One mapping with the mission screen: a book's own link wins over an
      // unresolved guide key, because that link is what opens.
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Poor Charlie’s Almanack',
            type: 'book',
            canonicalKey: 'book:munger:almanack',
            url: 'https://www.stripe.press/poor-charlies-almanack',
          ),
        ),
        AccessType.web,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Poor Charlie’s Almanack',
            type: 'book',
            canonicalKey: 'book:munger:almanack',
          ),
        ),
        AccessType.guide,
      );
      // Only a YouTube link plays in the in-app video viewer.
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Talk',
            type: 'video',
            url: 'https://vimeo.com/123456',
          ),
        ),
        AccessType.web,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(title: 'Talk', type: 'video'),
        ),
        AccessType.none,
      );
    });

    test(
      'session minutes come from the server, else a seventh of the week',
      () {
        final item = TodayTaskItem.fromJson({
          'id': 'h1',
          'title': 'Read',
          'estimated_hours': 1,
          'estimated_minutes': 15,
          'session_minutes': 5,
          'completed_today': false,
        });
        expect(item.sessionMinutes, 5);
        expect(habitSessionMinutes(item), 5);
        final old = TodayTaskItem.fromJson({
          'id': 'h1',
          'title': 'Read',
          'estimated_hours': 2,
          'completed_today': false,
        });
        expect(old.sessionMinutes, isNull);
        expect(habitSessionMinutes(old), 17); // 120 / 7
      },
    );

    test('comparable dimensions count only status comparable', () {
      expect(
        comparableDimensions({
          'version': 3,
          'dimensions': [
            {'id': 'knowledge', 'status': 'comparable'},
            {'id': 'practice', 'status': 'comparable'},
            {'id': 'capital', 'status': 'different_basis'},
            {'id': 'network', 'status': 'insufficient_user_evidence'},
            {'id': 'judgment', 'status': 'insufficient_idol_evidence'},
          ],
        }),
        (comparable: 2, total: 5),
      );
      expect(comparableDimensions(null), isNull);
      expect(
        comparableDimensions({
          'dimensions': [
            {'id': 'x', 'status': 'comparable'},
          ],
        }),
        isNull,
      );
    });
  });
}

class _ThrowingToggleRepository extends _FakePlanRepository {
  _ThrowingToggleRepository(super.habits);

  @override
  Future<bool> toggleDailyTask(String itemId) async {
    toggles++;
    throw StateError('offline');
  }
}
