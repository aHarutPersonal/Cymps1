import 'package:cmpys/app/theme.dart';
import 'package:cmpys/features/cmpys/presentation/plan_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackendPlan _gatedPlan() => BackendPlan(
  id: 'plan-gated',
  durationWeeks: 3,
  weeklyHours: 6,
  totalItems: 3,
  completedItems: 0,
  overallProgress: 0,
  items: const [
    BackendPlanItem(
      id: 'week-1-mission',
      title: 'Ship the first proof of concept',
      type: 'project',
      description: 'Build one small working version and document the result.',
      weekStart: 1,
      weekEnd: 1,
      successMetric: 'The prototype runs.',
      estimatedHours: 3,
      status: 'in_progress',
      progressPercent: 40,
    ),
    BackendPlanItem(
      id: 'week-2-mission',
      title: 'Interview five early users',
      type: 'project',
      description: 'Test the proof of concept with real users.',
      weekStart: 2,
      weekEnd: 2,
      successMetric: 'Five interviews recorded.',
      estimatedHours: 2,
      status: 'not_started',
      progressPercent: 0,
    ),
    BackendPlanItem(
      id: 'week-3-mission',
      title: 'Synthesize the evidence',
      type: 'reflection',
      description: 'Turn the interviews into a decision.',
      weekStart: 3,
      weekEnd: 3,
      successMetric: 'Decision memo written.',
      estimatedHours: 1,
      status: 'not_started',
      progressPercent: 0,
    ),
  ],
);

class _Controller extends CurrentPlanController {
  _Controller(PlanRepository repo)
    : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(
      status: CurrentPlanStatus.ready,
      plan: _gatedPlan(),
    );
  }

  @override
  Future<void> refresh() async {}
}

class _Repo implements PlanRepository {
  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async =>
      PlanItemDetailed(
        item: _gatedPlan().items.firstWhere((i) => i.id == itemId),
        detailsStatus: 'available',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('plan focuses the active week and blocks future week details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    final repo = _Repo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysBackendSyncProvider.overrideWith((ref) async {}),
          planRepositoryProvider.overrideWithValue(repo),
          currentPlanProvider.overrideWith((ref) => _Controller(repo)),
          todayViewProvider.overrideWith((ref) async => null),
          todayStreakProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CmpysPlanScreen(),
        ),
      ),
    );
    // Step through the entrance: rises are hidden to semantics until they
    // start, so one long pump would leave most of the page unannounced.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The active week's mission is the one open card.
    expect(find.byKey(const Key('plan-mission-week-1-mission')), findsOneWidget);
    expect(find.text('Ship the first proof of concept'), findsWidgets);
    expect(
      find.byKey(const Key('plan-mission-week-2-mission')),
      findsNothing,
    );

    // Future weeks are locked chips; their missions show only as titles in
    // the all-weeks list, never their details.
    expect(find.bySemanticsLabel('Week 2, locked'), findsOneWidget);
    expect(find.bySemanticsLabel('Week 3, locked'), findsOneWidget);
    expect(find.text('Interview five early users'), findsOneWidget);
    expect(find.text('Test the proof of concept with real users.'), findsNothing);

    await tester.tap(find.byKey(const Key('plan-week-chip-2')));
    await tester.pump();
    expect(find.text('Week 2 unlocks after week 1'), findsOneWidget);
    expect(find.text('Test the proof of concept with real users.'), findsNothing);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    semantics.dispose();
  });
}
