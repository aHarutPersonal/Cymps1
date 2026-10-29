import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/plan_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/cmpys/state/plan_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/backend_plan_widgets.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sunday 25 October 2026, 14:30 local.
final _now = DateTime(2026, 10, 25, 14, 30);

BackendPlanItem _item(
  String id,
  String title, {
  String type = 'project',
  int week = 1,
  int weekEnd = 0,
  String status = 'not_started',
  int progress = 0,
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
  progressPercent: progress,
);

BackendPlan _plan({
  int weeks = 12,
  int? weeklyMinutes = 270,
  int weeklyHours = 5,
  List<BackendPlanItem>? items,
}) => BackendPlan(
  id: 'plan-1',
  durationWeeks: weeks,
  weeklyHours: weeklyHours,
  weeklyMinutes: weeklyMinutes,
  idolName: 'Warren Buffett',
  createdAt: _now.subtract(const Duration(days: 5)),
  items:
      items ??
      [
        _item(
          'm1',
          'Find what the business really earns',
          status: 'in_progress',
          progress: 40,
        ),
        _item('m2', 'Write a one-page owner’s memo'),
        _item('w2', 'Moats: why profits last', week: 2),
        _item('w3', 'Management that thinks like an owner', week: 3),
        _item('h1', 'Read ten pages', type: 'habit', weekEnd: weeks),
        _item('h2', 'One honest sentence', type: 'habit', weekEnd: weeks),
      ],
);

PlanStepDetail _step(
  String id,
  String title, {
  bool content = true,
  int read = 10,
  int practice = 5,
}) => PlanStepDetail(
  id: id,
  title: title,
  readingMinutes: content ? read : null,
  practiceMinutes: content ? practice : null,
  lessonContent: content ? '# $title' : null,
  lessonFormat: 'tutorial_v1',
);

/// Mission 1: two done, one current, one locked (written one ahead) and two
/// upcoming, not written yet.
PlanItemDetailed _detailOne({
  Set<String> completed = const {'s1', 's2'},
}) => PlanItemDetailed(
  item: _item('m1', 'Find what the business really earns'),
  detailsStatus: 'partial',
  jobId: 'job-1',
  lessonFormat: 'tutorial_v1',
  steps: [
    _step('s1', 'Reported earnings are an opinion'),
    _step('s2', 'Cash and accrual on one page'),
    _step('s3', 'Owner earnings, step by step', read: 10, practice: 10),
    _step('s4', 'Maintenance versus growth capex', read: 10, practice: 10),
    _step('s5', 'Working-capital traps', content: false),
    _step('s6', 'Reading the cash-flow statement', content: false),
  ],
  completedStepIds: completed,
);

/// Mission 1 with the learner on tutorial 4: tutorial 5, the next one, is
/// being written.
PlanItemDetailed _detailOneOnFour() =>
    _detailOne(completed: const {'s1', 's2', 's3'});

/// Mission 2: three tutorials, none started.
PlanItemDetailed _detailTwo() => PlanItemDetailed(
  item: _item('m2', 'Write a one-page owner’s memo'),
  detailsStatus: 'available',
  lessonFormat: 'tutorial_v1',
  steps: [
    _step('b1', 'What an owner’s memo is for', read: 10, practice: 10),
    _step('b2', 'One page, four paragraphs', read: 20, practice: 10),
    _step('b3', 'Writing the earnings paragraph', read: 5, practice: 5),
  ],
);

class _Habit {
  _Habit(this.id, this.title, {this.done = false, this.days = const {}});
  final String id;
  final String title;
  bool done;

  /// Days of this week (Monday is 0) the habit itself was done, before today.
  final Set<int> days;
}

class _FakePlanRepository implements PlanRepository {
  _FakePlanRepository(
    this.habits, {
    this.failToggle = false,
    this.failStatus = false,
    this.peekTwo,
    this.readOne,
  });

  final List<_Habit> habits;
  final bool failToggle;
  final bool failStatus;

  /// Replaces mission 2's peeked tutorials.
  final PlanItemDetailed Function()? peekTwo;

  /// Replaces mission 1's tutorials.
  final PlanItemDetailed Function()? readOne;
  int toggles = 0;
  int statusReads = 0;

  /// Mission ids read the normal way, and with `?peek=true`.
  final List<String> normalReads = [];
  final List<String> peekReads = [];

  @override
  Future<TodayView> getTodayView(String planId) async => TodayView(
    items: [
      for (final h in habits)
        TodayTaskItem(
          id: h.id,
          title: h.title,
          type: 'habit',
          estimatedHours: 1,
          sessionMinutes: 10,
          completedToday: h.done,
          dailyInstructions: 'Do ${h.title} today.',
        ),
    ],
    streak: 4,
    completedToday: habits.where((h) => h.done).length,
    totalToday: habits.length,
  );

  @override
  Future<bool> toggleDailyTask(String itemId) async {
    toggles++;
    if (failToggle) throw StateError('offline');
    final habit = habits.firstWhere((h) => h.id == itemId);
    habit.done = !habit.done;
    return habit.done;
  }

  @override
  Future<StreakSummary> getStreak() async => StreakSummary(
    current: 2,
    longest: 9,
    lastActive: DateTime(_now.year, _now.month, _now.day - 1),
  );

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async {
    normalReads.add(itemId);
    return itemId == 'm2' ? _detailTwo() : (readOne ?? _detailOne)();
  }

  @override
  Future<PlanItemDetailed> peekPlanItemDetailed(String itemId) async {
    peekReads.add(itemId);
    return itemId == 'm2' ? (peekTwo ?? _detailTwo)() : _detailOne();
  }

  /// The server's current week is Monday 19 to Sunday 25 October 2026.
  @override
  Future<DailyStatus> getDailyStatus(String itemId) async {
    statusReads++;
    if (failStatus) throw StateError('offline');
    final habit = habits.firstWhere((h) => h.id == itemId);
    return DailyStatus(
      itemId: itemId,
      days: [
        for (var i = 0; i < 7; i++)
          DailyStatusDay(
            date: DateTime.utc(2026, 10, 19 + i),
            completed: i == 6 ? habit.done : habit.days.contains(i),
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanController extends CurrentPlanController {
  _PlanController(PlanRepository repo, CurrentPlanState initial)
    : super(repo: repo, readJobId: () => null) {
    state = initial;
  }

  int retries = 0;
  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<void> retry() async {
    retries++;
  }
}

class _TestStore extends CmpysStore {
  _TestStore({String? blueprint}) {
    state = state.copyWith(
      user: CmpysUser(name: 'Maya Chen', age: 24),
      blueprintMd: blueprint,
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

const _blueprint =
    '## Strategic Verdict\n'
    'You have no written analysis yet, and that is the gap that matters.\n\n'
    'You learn best from worked examples.\n\n'
    '## Twelve-Week Thesis\n'
    'Learn to read a business like an owner before you price it like a '
    'trader. Then write it down.\n\n'
    '## Phase Intent\n'
    '- **Weeks 1-3 — Foundation:** Make owner earnings reliable. Signal: one '
    'worksheet.\n'
    '- **Weeks 4-6 — Core Skills:** Recognise moats. Signal: two cases.\n\n'
    '## Guardrails\n'
    '- Prioritise reading filings.\n'
    '## Mentor’s Closing\n'
    'Write it down.';

class _Harness {
  _Harness({
    CurrentPlanState? initial,
    List<_Habit>? habits,
    this.blueprint,
    bool failToggle = false,
    bool failStatus = false,
    PlanItemDetailed Function()? peekTwo,
    PlanItemDetailed Function()? readOne,
  }) {
    repo = _FakePlanRepository(
      habits ?? [_Habit('h1', 'Read ten pages'), _Habit('h2', 'One sentence')],
      failToggle: failToggle,
      failStatus: failStatus,
      peekTwo: peekTwo,
      readOne: readOne,
    );
    controller = _PlanController(
      repo,
      initial ?? CurrentPlanState(status: CurrentPlanStatus.ready, plan: _plan()),
    );
    store = _TestStore(blueprint: blueprint);
  }

  final String? blueprint;
  late final _FakePlanRepository repo;
  late final _PlanController controller;
  late final _TestStore store;

  Widget build({Widget Function(Widget screen)? wrap}) => ProviderScope(
    overrides: [
      cmpysStoreProvider.overrideWith((ref) => store),
      cmpysBackendSyncProvider.overrideWith((ref) async {}),
      planRepositoryProvider.overrideWithValue(repo),
      currentPlanProvider.overrideWith((ref) => controller),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: (wrap ?? (screen) => screen)(CmpysPlanScreen(clock: () => _now)),
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(430, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // A fresh tree, so a second harness in one test gets its own providers.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(harness.build());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Lets toasts, rises, count-ups and pulses finish their timers.
Future<void> _settleTimers(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('plan data helpers', () {
    test('formatHalfHours shows half hours without a trailing zero', () {
      expect(formatHalfHours(60), '1');
      expect(formatHalfHours(90), '1.5');
      expect(formatHalfHours(240), '4');
      expect(formatHalfHours(270), '4.5');
      expect(formatHalfHours(900), '15');
      // Off-grid minutes round to the nearest half hour.
      expect(formatHalfHours(250), '4');
      expect(formatHalfHours(260), '4.5');
    });

    test('planWeeklyMinutes prefers weeklyMinutes, else whole hours', () {
      expect(planWeeklyMinutes(_plan(weeklyMinutes: 270)), 270);
      expect(planWeeklyMinutes(_plan(weeklyMinutes: null, weeklyHours: 4)), 240);
      expect(planWeeklyMinutes(_plan(weeklyMinutes: 0, weeklyHours: 3)), 180);
    });

    test('planOverallProgress counts required work, not daily habits', () {
      // m1 40%, m2 0, two more untouched: (0.4) / 4 missions = 0.1.
      expect(planOverallProgress(_plan()), closeTo(0.1, 1e-9));
      final done = _plan(
        items: [
          _item('a', 'A', status: 'completed', progress: 100),
          _item('b', 'B', week: 2),
          _item('h', 'Habit', type: 'habit'),
        ],
      );
      expect(planOverallProgress(done), closeTo(0.5, 1e-9));
      // No required work: fall back to the server's figure.
      final habitsOnly = BackendPlan(
        id: 'p',
        durationWeeks: 12,
        weeklyHours: 4,
        overallProgress: 25,
        items: [_item('h', 'Habit', type: 'habit')],
      );
      expect(planOverallProgress(habitsOnly), closeTo(0.25, 1e-9));
    });

    test('tutorialRowStates maps done, current, locked and preparing', () {
      // One ahead: 3 and 4 are written, so 5 and 6 are upcoming.
      expect(tutorialRowStates(_detailOne()), [
        TutorialRowState.done,
        TutorialRowState.done,
        TutorialRowState.current,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
      // On 4, the job writes 5; 6 waits.
      expect(tutorialRowStates(_detailOneOnFour()), [
        TutorialRowState.done,
        TutorialRowState.done,
        TutorialRowState.done,
        TutorialRowState.current,
        TutorialRowState.preparing,
        TutorialRowState.locked,
      ]);
      // A locked mission shows every unfinished tutorial locked.
      expect(
        tutorialRowStates(_detailTwo(), missionLocked: true),
        everyElement(TutorialRowState.locked),
      );
      // When generation stopped, the tutorial in front is "stopped".
      final failed = PlanItemDetailed(
        item: _item('m1', 'M'),
        detailsStatus: 'failed',
        lessonFormat: 'tutorial_v1',
        steps: [_step('a', 'A'), _step('b', 'B', content: false)],
        completedStepIds: const {'a'},
      );
      expect(tutorialRowStates(failed), [
        TutorialRowState.done,
        TutorialRowState.stopped,
      ]);
    });
  });

  group('blueprint', () {
    test('parseBlueprint reads direction, priorities and rationale', () {
      final blueprint = parseBlueprint(_blueprint)!;
      expect(
        blueprint.direction,
        'Learn to read a business like an owner before you price it like a '
        'trader.',
      );
      expect(blueprint.priorities.map((p) => p.title), [
        'Weeks 1-3 — Foundation',
        'Weeks 4-6 — Core Skills',
      ]);
      expect(
        blueprint.priorities.first.detail,
        'Make owner earnings reliable. Signal: one worksheet.',
      );
      expect(
        blueprint.rationale,
        'You have no written analysis yet, and that is the gap that matters.',
      );
    });

    test('parseBlueprint falls back to guardrails, then to nothing', () {
      final guardrails = parseBlueprint(
        '## Twelve-Week Thesis\nRead first.\n\n## Guardrails\n'
        '- Prioritise: reading filings.\n- Avoid: tips.\n',
      )!;
      expect(guardrails.direction, 'Read first.');
      expect(guardrails.priorities.map((p) => p.title), ['Prioritise', 'Avoid']);
      expect(guardrails.priorities.first.detail, 'reading filings.');
      expect(guardrails.rationale, isNull);
    });

    test('parseBlueprint degrades to the raw first paragraph', () {
      final plain = parseBlueprint(
        'Start with evidence. It matters most.\n\nThen price it.',
      )!;
      expect(plain.direction, 'Start with evidence. It matters most.');
      expect(plain.priorities, isEmpty);
      expect(plain.rationale, isNull);
      expect(parseBlueprint(''), isNull);
      expect(parseBlueprint(null), isNull);
    });
  });

  testWidgets('header shows the real week count, mentor and overall ring', (
    tester,
  ) async {
    final harness = _Harness(
      initial: CurrentPlanState(
        status: CurrentPlanStatus.ready,
        plan: _plan(weeks: 10),
      ),
    );
    await _pumpScreen(tester, harness);

    expect(find.text('YOUR PLAN'), findsOneWidget);
    expect(
      find.textContaining('10 weeks', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('with Buffett', findRichText: true), findsOneWidget);
    expect(find.text('Week 1 of 10'), findsOneWidget);
    // 40% of one of four required items: 10%.
    expect(find.text('10%'), findsOneWidget);
    expect(find.byType(V3Seg<int>), findsOneWidget);
    expect(find.text('Roadmap'), findsOneWidget);
    expect(find.text('Daily habits'), findsOneWidget);
    await _settleTimers(tester);
  });

  testWidgets('weekly_minutes_shows_half_hours', (tester) async {
    await _pumpScreen(tester, _Harness());
    expect(find.text('4.5 h / week'), findsOneWidget);
    expect(find.text('About 2.2 h of tutorials · 4.5 h budget'), findsOneWidget);
    await _settleTimers(tester);

    // A server that predates weeklyMinutes: whole hours.
    await _pumpScreen(
      tester,
      _Harness(
        initial: CurrentPlanState(
          status: CurrentPlanStatus.ready,
          plan: _plan(weeklyMinutes: null, weeklyHours: 4),
        ),
      ),
    );
    expect(find.text('4 h / week'), findsOneWidget);
    // That server cannot peek, so only the mission to work on is read and
    // counted (mission 1's 70 minutes).
    expect(find.text('About 1.2 h of tutorials · 4 h budget'), findsOneWidget);
    await _settleTimers(tester);
  });

  group('week strip', () {
    testWidgets('locked weeks toast; the current week opens its mission', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness());

      expect(find.text('WK'), findsNWidgets(12));
      await tester.tap(find.byKey(const Key('plan-week-chip-3')));
      await tester.pump();
      expect(find.text('Week 3 unlocks after week 2'), findsOneWidget);
      await _settleTimers(tester);

      await tester.tap(find.byKey(const Key('plan-week-chip-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PlanItemDetailScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('weeks before the focus week are done and reviewable', (
      tester,
    ) async {
      final plan = _plan(
        items: [
          _item('m1', 'Week one mission', status: 'completed', progress: 100),
          _item('w2', 'Week two mission', week: 2, status: 'in_progress'),
          _item('w3', 'Week three mission', week: 3),
        ],
      );
      await _pumpScreen(
        tester,
        _Harness(
          initial: CurrentPlanState(status: CurrentPlanStatus.ready, plan: plan),
        ),
      );
      expect(find.text('Week 2 of 12'), findsOneWidget);
      expect(planWeekState(plan, 1), PlanWeekState.done);
      expect(planWeekState(plan, 2), PlanWeekState.current);
      expect(planWeekState(plan, 3), PlanWeekState.locked);

      await tester.tap(find.byKey(const Key('plan-week-chip-3')));
      await tester.pump();
      expect(find.text('Week 3 unlocks after week 2'), findsOneWidget);
      await _settleTimers(tester);
    });
  });

  group('blueprint card', () {
    testWidgets('expands to the priorities and "Why this order"', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness(blueprint: _blueprint));

      expect(find.text('STRATEGIC BLUEPRINT'), findsOneWidget);
      expect(
        find.text(
          'Learn to read a business like an owner before you price it like a '
          'trader.',
        ),
        findsOneWidget,
      );
      // Collapsed: the body takes no height.
      expect(
        tester.getSize(find.byKey(const Key('plan-blueprint-body'))).height,
        0,
      );
      expect(find.text('Weeks 1-3 — Foundation'), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-blueprint')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.getSize(find.byKey(const Key('plan-blueprint-body'))).height,
        greaterThan(40),
      );
      expect(find.text('Why this order'), findsOneWidget);
      expect(
        find.text(
          'You have no written analysis yet, and that is the gap that matters.',
        ),
        findsOneWidget,
      );
      expect(find.text('1'), findsWidgets);
      expect(find.text('Read the full blueprint'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('is hidden without a blueprint', (tester) async {
      await _pumpScreen(tester, _Harness());
      expect(find.text('STRATEGIC BLUEPRINT'), findsNothing);
      await _settleTimers(tester);
    });
  });

  group('this week', () {
    testWidgets('summary ring, minutes and the mission cards', (tester) async {
      await _pumpScreen(tester, _Harness());

      expect(
        find.text('WEEK 1 · FIND WHAT THE BUSINESS REALLY EARNS'),
        findsOneWidget,
      );
      expect(find.text('9 tutorials across 2 missions'), findsOneWidget);
      expect(find.text('2/9'), findsOneWidget);
      expect(find.text('MISSION 1'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('MISSION 2'), findsOneWidget);
      expect(find.text('After mission 1'), findsOneWidget);
      expect(
        find.text('Find what the business really earns'),
        findsWidgets,
      );
      await _settleTimers(tester);
    });

    testWidgets('rows show the current tutorial and its neighbours', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness());

      // Current is tutorial 3: one before, two after.
      expect(find.text('Cash and accrual on one page'), findsOneWidget);
      expect(find.text('Owner earnings, step by step'), findsOneWidget);
      expect(find.text('Maintenance versus growth capex'), findsOneWidget);
      expect(find.text('Reported earnings are an opinion'), findsNothing);
      expect(find.text('Reading the cash-flow statement'), findsNothing);
      expect(find.text('Tutorial 2 · 15 min'), findsOneWidget);
      expect(find.text('Tutorial 3 · 20 min'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Show all 6 tutorials'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Reported earnings are an opinion'), findsOneWidget);
      expect(find.text('Show fewer'), findsOneWidget);

      await tester.tap(find.text('Show fewer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Reported earnings are an opinion'), findsNothing);
      await _settleTimers(tester);
    });

    testWidgets('locked_tutorial_shakes_and_toasts', (tester) async {
      await _pumpScreen(tester, _Harness());

      final lock = find.byKey(planTutorialLockKey('m1', 's4'));
      expect(lock, findsOneWidget);
      double tilt() {
        final transform = tester.widget<Transform>(
          find
              .descendant(of: lock, matching: find.byType(Transform))
              .first,
        );
        return transform.transform.entry(0, 1);
      }

      // At rest the lock is upright.
      expect(tilt(), 0);

      await tester.tap(find.byKey(planTutorialRowKey('m1', 's4')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // 100 ms in, the lock is rocking (the design's `shake .5s`).
      expect(tilt().abs(), greaterThan(0.05));
      expect(find.text('Finish tutorial 3 first'), findsOneWidget);

      // It settles back upright once the shake ends.
      await tester.pump(const Duration(milliseconds: 600));
      expect(tilt(), 0);
      await _settleTimers(tester);
    });

    testWidgets('preparing_row_shows_skeleton', (tester) async {
      await _pumpScreen(tester, _Harness(readOne: _detailOneOnFour));
      await tester.tap(find.text('Show all 6 tutorials'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final row = find.byKey(planTutorialRowKey('m1', 's5'));
      expect(row, findsOneWidget);
      // The title is a skeleton, not text, and the row says it is preparing.
      expect(
        find.descendant(of: row, matching: find.byType(V3Skel)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('Working-capital traps'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('Tutorial 5 · preparing'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(V3Spinner)),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pump();
      expect(find.text('Still being prepared and reviewed'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('a tutorial row opens the lesson reader for done and current', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness());
      await tester.tap(find.byKey(planTutorialRowKey('m1', 's3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PlanItemDetailScreen), findsNothing);
      expect(find.text('Finish tutorial 3 first'), findsNothing);
      // The lesson reader opens on the root navigator.
      expect(find.byType(LessonReaderScreen), findsOneWidget);
      // The Plan tab's entry passes the mission week, as the mission does.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^TUTORIAL 3 OF \d+ · WEEK \d').hasMatch(widget.data ?? ''),
        ),
        findsOneWidget,
      );
    });

    testWidgets('coming back to the tab re-reads tutorials still preparing', (
      tester,
    ) async {
      final harness = _Harness(readOne: _detailOneOnFour);
      final onScreen = ValueNotifier<bool>(true);
      addTearDown(onScreen.dispose);
      tester.view.physicalSize = const Size(430, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        harness.build(
          wrap: (screen) => ValueListenableBuilder<bool>(
            valueListenable: onScreen,
            builder: (_, visible, _) =>
                TickerMode(enabled: visible, child: screen),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      // The mission to work on is read normally, the next one is peeked.
      expect(harness.repo.normalReads, ['m1']);
      expect(harness.repo.peekReads, ['m2']);

      onScreen.value = false;
      await tester.pump();
      onScreen.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mission 1 still has tutorials being written, mission 2 has none.
      expect(harness.repo.normalReads, ['m1', 'm1']);
      expect(harness.repo.peekReads, ['m2']);
      await _settleTimers(tester);
    });

    testWidgets('coming back does not re-read a mission written one ahead', (
      tester,
    ) async {
      // Mission 1's window (3 and 4) is written: nothing is preparing.
      final harness = _Harness();
      final onScreen = ValueNotifier<bool>(true);
      addTearDown(onScreen.dispose);
      tester.view.physicalSize = const Size(430, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        harness.build(
          wrap: (screen) => ValueListenableBuilder<bool>(
            valueListenable: onScreen,
            builder: (_, visible, _) =>
                TickerMode(enabled: visible, child: screen),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      onScreen.value = false;
      await tester.pump();
      onScreen.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.repo.normalReads, ['m1']);
      await _settleTimers(tester);
    });

    testWidgets('a server without peek reads only the mission to work on', (
      tester,
    ) async {
      // A plan without weeklyMinutes comes from a server that predates
      // `?peek=true`: it would ignore the flag and start generating, so the
      // other missions are not read at all.
      final harness = _Harness(
        initial: CurrentPlanState(
          status: CurrentPlanStatus.ready,
          plan: _plan(weeklyMinutes: null, weeklyHours: 4),
        ),
      );
      await _pumpScreen(tester, harness);
      expect(harness.repo.normalReads, ['m1']);
      expect(harness.repo.peekReads, isEmpty);

      // Mission 2 shows its header only: no tutorial rows, no bars.
      final card = find.byKey(const Key('plan-mission-m2'));
      expect(
        find.descendant(
          of: card,
          matching: find.text('Write a one-page owner’s memo'),
        ),
        findsOneWidget,
      );
      expect(find.text('What an owner’s memo is for'), findsNothing);

      // Leaving and coming back, or switching views, never reads it either.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Daily habits'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Roadmap'));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pump(const Duration(seconds: 1));
      expect(harness.repo.peekReads, isEmpty);
      expect(harness.repo.normalReads, ['m1']);
      await _settleTimers(tester);
    });

    testWidgets('only the mission to work on is read normally; the rest peek', (
      tester,
    ) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);

      // Mission 1 is the focus; mission 2 is peeked; later weeks are not read.
      expect(harness.repo.normalReads, ['m1']);
      expect(harness.repo.peekReads, ['m2']);

      // Switching between Roadmap and Daily habits does not read them again.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Daily habits'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Roadmap'));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pump(const Duration(seconds: 1));
      expect(harness.repo.normalReads, ['m1']);
      expect(harness.repo.peekReads, ['m2']);
      // Its locked rows still come from the peeked tutorials.
      expect(find.text('What an owner’s memo is for'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('a mission with nothing written shows its header and tag only', (
      tester,
    ) async {
      final harness = _Harness(
        peekTwo: () => PlanItemDetailed(
          item: _item('m2', 'Write a one-page owner’s memo'),
          detailsStatus: 'pending',
        ),
      );
      await _pumpScreen(tester, harness);

      expect(find.text('MISSION 2'), findsOneWidget);
      expect(find.text('After mission 1'), findsOneWidget);
      expect(find.text('Write a one-page owner’s memo'), findsOneWidget);
      expect(find.byKey(planTutorialRowKey('m2', 'b1')), findsNothing);
      // One mission has tutorials: the summary counts only that one.
      expect(find.text('6 tutorials across 1 mission'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('a mission already started is open, never locked', (
      tester,
    ) async {
      // In progress in the plan.
      final started = _plan(
        items: [
          _item('m1', 'First mission', status: 'in_progress', progress: 40),
          _item('m2', 'Second mission', status: 'in_progress', progress: 20),
        ],
      );
      await _pumpScreen(
        tester,
        _Harness(
          initial: CurrentPlanState(
            status: CurrentPlanStatus.ready,
            plan: started,
          ),
        ),
      );
      expect(planMissionStatuses(started, 1), [
        PlanMissionStatus.current,
        PlanMissionStatus.open,
      ]);
      expect(find.text('After mission 1'), findsNothing);
      // Its first tutorial is the current one: it opens the reader.
      await tester.tap(find.byKey(planTutorialRowKey('m2', 'b1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Opens when mission 1 is complete'), findsNothing);
      expect(find.byType(LessonReaderScreen), findsOneWidget);
    });

    testWidgets('a mission with a finished tutorial is open too', (
      tester,
    ) async {
      // Not started as far as the plan says, but a tutorial is done.
      await _pumpScreen(
        tester,
        _Harness(
          peekTwo: () => PlanItemDetailed(
            item: _item('m2', 'Write a one-page owner’s memo'),
            detailsStatus: 'available',
            lessonFormat: 'tutorial_v1',
            steps: [
              _step('b1', 'What an owner’s memo is for'),
              _step('b2', 'One page, four paragraphs'),
            ],
            completedStepIds: const {'b1'},
          ),
        ),
      );
      expect(find.text('After mission 1'), findsNothing);
      await tester.tap(find.byKey(planTutorialRowKey('m2', 'b2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Opens when mission 1 is complete'), findsNothing);
      expect(find.byType(LessonReaderScreen), findsOneWidget);
    });

    testWidgets('the summary says tutorial and mission in the singular', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        _Harness(
          initial: CurrentPlanState(
            status: CurrentPlanStatus.ready,
            plan: _plan(items: [_item('m1', 'Only mission', status: 'in_progress')]),
          ),
          readOne: () => PlanItemDetailed(
            item: _item('m1', 'Only mission'),
            detailsStatus: 'available',
            lessonFormat: 'tutorial_v1',
            steps: [_step('s1', 'The one tutorial')],
          ),
        ),
      );
      expect(find.text('0/1'), findsOneWidget);
      expect(find.text('1 tutorial across 1 mission'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('the next mission is locked until the current one is done', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness());

      final row = find.byKey(planTutorialRowKey('m2', 'b1'));
      expect(row, findsOneWidget);
      expect(find.text('What an owner’s memo is for'), findsOneWidget);
      await tester.tap(row);
      await tester.pump();
      expect(find.text('Opens when mission 1 is complete'), findsOneWidget);
      await _settleTimers(tester);
    });
  });

  group('all weeks', () {
    testWidgets('lists every week with its state and the unlock note', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        _Harness(
          initial: CurrentPlanState(
            status: CurrentPlanStatus.ready,
            plan: _plan(weeks: 4),
          ),
        ),
      );
      expect(find.text('All weeks'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('Moats: why profits last'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(
        find.text(
          'Weeks unlock when the previous week’s required work is complete, '
          'not by calendar date. After week 4 you’ll get a cycle summary and '
          'can start the next plan.',
        ),
        findsOneWidget,
      );
      await _settleTimers(tester);
    });
  });

  group('daily habits', () {
    Future<void> openHabits(WidgetTester tester) async {
      await tester.tap(find.text('Daily habits'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
    }

    testWidgets('shows the intro and a card with a 7-day grid per habit', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness());
      await openHabits(tester);

      expect(
        find.text(
          'Habits repeat daily for this week. Tap one to open it, or check '
          'it off right here. It counts for today only.',
        ),
        findsOneWidget,
      );
      expect(find.text('Read ten pages'), findsOneWidget);
      expect(find.text('One sentence'), findsOneWidget);
      expect(find.text('Do Read ten pages today.'), findsOneWidget);
      // Two habits, each with a Monday-to-Sunday grid ending in "Today".
      expect(find.text('Today'), findsNWidgets(2));
      expect(find.text('M'), findsNWidgets(2));
      await _settleTimers(tester);
    });

    bool dayDone(String habit, int day) => find
        .descendant(
          of: find.byKey(Key('plan-habit-$habit-day-$day')),
          matching: find.byType(V3Icon),
        )
        .evaluate()
        .isNotEmpty;

    testWidgets('each habit shows its own week, not the streak run', (
      tester,
    ) async {
      // The streak run says Friday and Saturday were done (some habit was);
      // h1 was never done and h2 only on Thursday and Friday.
      final harness = _Harness(
        habits: [
          _Habit('h1', 'Read ten pages'),
          _Habit('h2', 'One sentence', days: {3, 4}),
        ],
      );
      await _pumpScreen(tester, harness);
      await openHabits(tester);

      expect([for (var d = 0; d < 7; d++) dayDone('h1', d)], everyElement(isFalse));
      expect([for (var d = 0; d < 7; d++) dayDone('h2', d)], [
        false,
        false,
        false,
        true,
        true,
        false,
        false,
      ]);
      expect(harness.repo.statusReads, 2);
      await _settleTimers(tester);
    });

    testWidgets('the streak run stands in only when the status call fails', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness(failStatus: true));
      await openHabits(tester);
      // The failed read, then the streak read that stands in for it.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Friday and Saturday: the days of the 2-day streak ending yesterday.
      expect([for (var d = 0; d < 7; d++) dayDone('h1', d)], [
        false,
        false,
        false,
        false,
        true,
        true,
        false,
      ]);
      await _settleTimers(tester);
    });

    testWidgets('today follows the live habit and the week is read again', (
      tester,
    ) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await openHabits(tester);
      expect(dayDone('h1', 6), isFalse);
      final readsBefore = harness.repo.statusReads;

      await tester.tap(find.byKey(const ValueKey('toggle-daily-h1')));
      await tester.pump();
      // Optimistic: today's cell is checked before the server answers.
      expect(dayDone('h1', 6), isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      expect(harness.repo.statusReads, greaterThan(readsBefore));
      expect(dayDone('h1', 6), isTrue);
      await _settleTimers(tester);
    });

    testWidgets('checking toasts "Done for today"; unchecking toasts too', (
      tester,
    ) async {
      final harness = _Harness();
      await _pumpScreen(tester, harness);
      await openHabits(tester);

      final firstDot = find.byKey(const ValueKey('toggle-daily-h1'));
      await tester.tap(firstDot);
      await tester.pump();
      // Optimistic: checked before the server answers.
      expect(
        tester.widget<V3CheckDot>(firstDot).done,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Done for today'), findsOneWidget);
      expect(harness.repo.toggles, 1);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(firstDot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Marked not done'), findsOneWidget);
      expect(tester.widget<V3CheckDot>(firstDot).done, isFalse);
      await _settleTimers(tester);
    });

    testWidgets('the last habit of the day celebrates', (tester) async {
      final harness = _Harness(
        habits: [_Habit('h1', 'Read ten pages', done: true), _Habit('h2', 'One sentence')],
      );
      await _pumpScreen(tester, harness);
      await openHabits(tester);

      await tester.tap(find.byKey(const ValueKey('toggle-daily-h2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CelebrationOverlay), findsOneWidget);
      expect(find.text('Done for today'), findsNothing);
      await _settleTimers(tester);
    });

    testWidgets('a failed toggle rolls back with the existing toast', (
      tester,
    ) async {
      await _pumpScreen(tester, _Harness(failToggle: true));
      await openHabits(tester);

      final dot = find.byKey(const ValueKey('toggle-daily-h1'));
      await tester.tap(dot);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<V3CheckDot>(dot).done, isFalse);
      expect(find.text('Couldn’t update — try again.'), findsOneWidget);
      await _settleTimers(tester);
    });

    testWidgets('tapping a habit opens its detail', (tester) async {
      await _pumpScreen(tester, _Harness());
      await openHabits(tester);
      await tester.tap(find.text('Read ten pages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PlanItemDetailScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('plan states', () {
    testWidgets('generating shows live progress', (tester) async {
      await _pumpScreen(
        tester,
        _Harness(
          initial: const CurrentPlanState(
            status: CurrentPlanStatus.generating,
            jobProgress: 42,
            jobLine: 'Writing week 3',
          ),
        ),
      );
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('Writing week 3'), findsOneWidget);
      expect(find.text('Roadmap'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('failed offers a retry; empty offers a re-check', (
      tester,
    ) async {
      final failed = _Harness(
        initial: const CurrentPlanState(status: CurrentPlanStatus.failed),
      );
      await _pumpScreen(tester, failed);
      expect(
        find.text('Couldn’t load your 12-week plan — tap to retry.'),
        findsOneWidget,
      );
      // The controller refreshes once on construction.
      final refreshesBefore = failed.controller.refreshes;
      await tester.tap(find.text('Couldn’t load your 12-week plan — tap to retry.'));
      await tester.pump();
      expect(failed.controller.refreshes, refreshesBefore + 1);
      await tester.pump(const Duration(seconds: 3));

      final empty = _Harness(
        initial: const CurrentPlanState(status: CurrentPlanStatus.empty),
      );
      await _pumpScreen(tester, empty);
      expect(find.text('Your plan with Buffett isn’t ready yet.'), findsOneWidget);
      await tester.tap(find.text('Tap to check again.'));
      await tester.pump();
      expect(empty.controller.retries, 1);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a finished plan offers the cycle summary', (tester) async {
      final plan = _plan(
        items: [
          _item('m1', 'Only mission', status: 'completed', progress: 100),
          _item('h1', 'Read ten pages', type: 'habit', weekEnd: 12),
        ],
      );
      await _pumpScreen(
        tester,
        _Harness(
          initial: CurrentPlanState(status: CurrentPlanStatus.ready, plan: plan),
        ),
      );
      expect(find.text('Plan complete'), findsOneWidget);
      expect(
        find.text('Every mission is complete. Your roadmap is open for review.'),
        findsOneWidget,
      );
      expect(find.text('Week 12 of 12'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('See your cycle summary'), findsOneWidget);
      await _settleTimers(tester);
    });
  });
}
