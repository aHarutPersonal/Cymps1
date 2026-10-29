import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmpys/core/ui/narration_dock_page.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/habit_detail_view.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';

/// A habit whose week holds [minutes] (the server's `estimated_minutes`, the
/// WEEKLY allocation) and whose one session is [sessionMinutes] (the
/// server's `session_minutes`; null from servers that predate it).
PlanItemDetailed _habit({
  bool doneToday = false,
  int? minutes = 14,
  int? sessionMinutes = 2,
  String reflection = '',
}) => PlanItemDetailed(
  item: BackendPlanItem(
    id: 'h1',
    title: 'Write 200 words',
    type: 'habit',
    description: 'Write without editing.',
    weekStart: 3,
    weekEnd: 3,
    successMetric: 'Daily reps feed this week’s draft.',
    estimatedHours: 1,
    estimatedMinutes: minutes,
    status: 'in_progress',
    progressPercent: 0,
  ),
  sessionMinutes: sessionMinutes,
  detailsStatus: 'available',
  dailyInstructions: 'Open a blank page and write for the whole timer.',
  dailyReflection: reflection,
  completedToday: doneToday,
);

class _HabitRepo extends Fake implements PlanRepository {
  _HabitRepo({this.doneToday = false, this.statusFails = false});

  bool doneToday;
  final bool statusFails;
  int toggles = 0;
  final saved = <String>[];
  bool failSaves = false;
  bool failToggle = false;
  Completer<void>? toggleGate;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async =>
      _habit(doneToday: doneToday);

  @override
  Future<bool> toggleDailyTask(String itemId) async {
    toggles++;
    final gate = toggleGate;
    if (gate != null) await gate.future;
    if (failToggle) throw Exception('offline');
    doneToday = !doneToday;
    return doneToday;
  }

  @override
  Future<void> saveDailyReflection(String itemId, String text) async {
    if (failSaves) throw Exception('offline');
    saved.add(text);
  }

  @override
  Future<DailyStatus> getDailyStatus(String itemId) async {
    if (statusFails) throw Exception('offline');
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return DailyStatus(
      itemId: itemId,
      days: [
        for (var i = 0; i < 7; i++)
          DailyStatusDay(date: monday.add(Duration(days: i)), completed: false),
      ],
    );
  }

  TodayView todayView() => TodayView(
    items: [
      TodayTaskItem(
        id: 'h1',
        title: 'Write 200 words',
        type: 'habit',
        estimatedHours: 1,
        completedToday: doneToday,
        estimatedMinutes: 2,
      ),
      const TodayTaskItem(
        id: 'h2',
        title: 'Read 10 pages',
        type: 'habit',
        estimatedHours: 1,
        completedToday: false,
      ),
    ],
    streak: 0,
    completedToday: doneToday ? 1 : 0,
    totalToday: 2,
  );
}

List<Override> _overrides(_HabitRepo repo, {bool inToday = true}) => [
  planRepositoryProvider.overrideWithValue(repo),
  todayViewProvider.overrideWith(
    (ref) async => inToday ? repo.todayView() : null,
  ),
  todayStreakProvider.overrideWith((ref) async => null),
];

Widget _screen(_HabitRepo repo, {bool inToday = true}) => ProviderScope(
  overrides: _overrides(repo, inToday: inToday),
  child: const MaterialApp(home: PlanItemDetailScreen(itemId: 'h1')),
);

/// A screen tall enough that the whole habit page is built at once.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('timer_counts_down_and_resets', (tester) async {
    final repo = _HabitRepo();
    var now = DateTime(2026, 10, 27, 9);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          home: HabitDetailView(
            detailed: _habit(),
            onReload: () async {},
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2:00'), findsOneWidget);
    expect(find.text('Focus timer'), findsOneWidget);
    expect(find.text('Reset'), findsNothing);

    await tester.tap(find.text('Start timer'));
    await tester.pump();
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    // The countdown follows the wall clock, not the number of ticks.
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1:57'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:57'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('2:00'), findsOneWidget);
    expect(find.text('Start timer'), findsOneWidget);
    expect(find.text('Reset'), findsNothing);

    // Running out shows "Time’s up".
    await tester.tap(find.text('Start timer'));
    await tester.pump();
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('Time’s up'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mark_done_toggles_daily_toggle_api', (tester) async {
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    expect(find.text('DAILY HABIT 1 OF 2 · WEEK 3'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('2 min'), findsOneWidget);

    await tester.tap(find.text('Mark done for today'));
    await tester.pumpAndSettle();
    expect(repo.toggles, 1);
    expect(find.text('Mark as not done'), findsOneWidget);
    expect(find.text('Done today'), findsOneWidget);
    expect(
      find.text('Counted for today. It’ll be back tomorrow.'),
      findsOneWidget,
    );
    expect(find.text('Start timer'), findsNothing);

    await tester.tap(find.text('Mark as not done'));
    await tester.pumpAndSettle();
    expect(repo.toggles, 2);
    expect(find.text('Mark done for today'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a habit outside today’s view still toggles through the API', (
    tester,
  ) async {
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo, inToday: false));
    await tester.pumpAndSettle();

    expect(find.text('DAILY HABIT · WEEK 3'), findsOneWidget);
    await tester.tap(find.text('Mark done for today'));
    await tester.pumpAndSettle();
    expect(repo.toggles, 1);
    expect(find.text('Mark as not done'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a never-done habit shows no checks in its week', (tester) async {
    _tallScreen(tester);
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('habit-day-done')), findsNothing);
    expect(find.byKey(const ValueKey('habit-day-today')), findsOneWidget);
    expect(find.text('of 7 days done'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('the reflection autosaves after a pause in typing', (
    tester,
  ) async {
    _tallScreen(tester);
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    expect(find.text('Saved with today’s entry'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Wrote 240 words.');
    await tester.pump();
    expect(find.text('Saving'), findsOneWidget);
    expect(repo.saved, isEmpty);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(repo.saved, ['Wrote 240 words.']);
    expect(find.text('Saved for today'), findsOneWidget);
  });

  testWidgets('the why panel shows the success metric', (tester) async {
    _tallScreen(tester);
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    expect(find.text('Why it matters this week'), findsOneWidget);
    expect(find.text('Daily reps feed this week’s draft.'), findsOneWidget);
    expect(
      find.text('Open a blank page and write for the whole timer.'),
      findsOneWidget,
    );
  });

  testWidgets('a habit done today opens counted, without timer controls', (
    tester,
  ) async {
    _tallScreen(tester);
    final repo = _HabitRepo(doneToday: true);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('Mark as not done'), findsOneWidget);
    expect(find.text('Start timer'), findsNothing);
    expect(find.byKey(const ValueKey('habit-day-done')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a failed week read still shows the grid', (tester) async {
    _tallScreen(tester);
    final repo = _HabitRepo(statusFails: true);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    expect(find.text('of 7 days done'), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-day-today')), findsOneWidget);
  });

  testWidgets('marking done bursts and stops the timer', (tester) async {
    final repo = _HabitRepo();
    var now = DateTime(2026, 10, 27, 9);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          home: HabitDetailView(
            detailed: _habit(),
            onReload: () async {},
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start timer'));
    await tester.pump();
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1:57'), findsOneWidget);

    await tester.tap(find.text('Mark done for today'));
    await tester.pump();
    expect(find.byType(V3Burst), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Mark as not done'), findsOneWidget);

    now = now.add(const Duration(seconds: 30));
    await tester.tap(find.text('Mark as not done'));
    await tester.pumpAndSettle();
    expect(find.text('1:57'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the screen while the timer runs stops it', (
    tester,
  ) async {
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start timer'));
    await tester.pump(const Duration(seconds: 1));
    // A ticker left running would fail the test as a pending timer.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a second tap while a toggle is in flight is ignored', (
    tester,
  ) async {
    final repo = _HabitRepo()..toggleGate = Completer<void>();
    await tester.pumpWidget(_screen(repo, inToday: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark done for today'));
    await tester.pump();
    expect(find.text('Mark as not done'), findsOneWidget);
    await tester.tap(find.text('Mark as not done'));
    await tester.pump();
    expect(repo.toggles, 1);
    expect(find.text('Mark as not done'), findsOneWidget);

    repo.toggleGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.toggles, 1);
    expect(find.text('Mark as not done'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed toggle outside today rolls back with a toast', (
    tester,
  ) async {
    final repo = _HabitRepo()..failToggle = true;
    await tester.pumpWidget(_screen(repo, inToday: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark done for today'));
    await tester.pumpAndSettle();
    expect(repo.toggles, 1);
    expect(find.text('Couldn’t update — try again.'), findsOneWidget);
    expect(find.text('Mark done for today'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed save offers a retry that saves the text', (
    tester,
  ) async {
    _tallScreen(tester);
    final repo = _HabitRepo()..failSaves = true;
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Wrote 240 words.');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(
      find.text('Couldn’t save. Your text is still here; please retry.'),
      findsOneWidget,
    );
    expect(repo.saved, isEmpty);

    repo.failSaves = false;
    await tester.tap(find.byKey(const Key('habit-note-retry')));
    await tester.pump();
    expect(repo.saved, ['Wrote 240 words.']);
    expect(find.text('Saved for today'), findsOneWidget);
  });

  testWidgets('leaving before the pause ends still saves the note', (
    tester,
  ) async {
    _tallScreen(tester);
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Short entry.');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repo.saved, ['Short entry.']);
  });

  testWidgets('the narration dock leaves a mission page that turns out to be '
      'a habit', (tester) async {
    _tallScreen(tester);
    final repo = _HabitRepo();
    await tester.pumpWidget(_screen(repo));
    final route = ModalRoute.of(
      tester.element(find.byType(PlanItemDetailScreen)),
    )!;
    // Loading builds the mission page, which carries the dock.
    expect(find.byType(HabitDetailView), findsNothing);
    expect(NarrationDockPage.allows(route), isTrue);
    await tester.pumpAndSettle();
    // The item is a daily habit: the habit page has no dock.
    expect(find.byType(HabitDetailView), findsOneWidget);
    expect(NarrationDockPage.allows(route), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('the timer and tag use the server’s session minutes', (
    tester,
  ) async {
    final repo = _HabitRepo();
    // 70 minutes a week, 10 a session: the session is what one sitting is.
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          home: HabitDetailView(
            detailed: _habit(minutes: 70, sessionMinutes: 10),
            onReload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('70 min'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an older server’s habit shows a seventh of its week', (
    tester,
  ) async {
    Future<void> show(int weekly) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(_HabitRepo()),
          child: MaterialApp(
            home: HabitDetailView(
              detailed: _habit(minutes: weekly, sessionMinutes: null),
              onReload: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Exactly what Today and Plan show (habitSessionMinutes).
    await show(70);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    // At least one minute.
    await show(2);
    expect(find.text('1 min'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a toggle that lands after the habit screen closes still '
      'refreshes Today', (tester) async {
    final repo = _HabitRepo()..toggleGate = Completer<void>();
    var todayReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(repo),
          todayViewProvider.overrideWith((ref) async {
            todayReads++;
            return repo.todayView();
          }),
          todayStreakProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final view = ref.watch(todayViewProvider).valueOrNull;
              final done = view?.items.first.completedToday ?? false;
              return Scaffold(
                body: Column(
                  children: [
                    Text(done ? 'Today: done' : 'Today: not done'),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const PlanItemDetailScreen(itemId: 'h1'),
                        ),
                      ),
                      child: const Text('Open habit'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today: not done'), findsOneWidget);
    await tester.tap(find.text('Open habit'));
    await tester.pumpAndSettle();

    // The toggle is in flight when the learner closes the screen.
    await tester.tap(find.text('Mark done for today'));
    await tester.pump();
    final readsBefore = todayReads;
    Navigator.of(tester.element(find.byType(HabitDetailView))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailView), findsNothing);

    repo.toggleGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.toggles, 1);
    expect(todayReads, greaterThan(readsBefore));
    expect(find.text('Today: done'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
