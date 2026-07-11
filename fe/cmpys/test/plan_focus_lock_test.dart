import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/backend_plan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets('plan focuses the active week and blocks future week details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final plan = _gatedPlan();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: backendPlanRoadmapBlocks(plan),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('current-week-focus')), findsOneWidget);
    expect(find.text('WEEK 1 · CURRENT FOCUS'), findsOneWidget);
    expect(find.text('Ship the first proof of concept'), findsWidgets);
    expect(find.byKey(const Key('week-1-current')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('week-2-locked')),
      240,
    );
    expect(find.byKey(const Key('week-2-locked')), findsOneWidget);
    expect(find.byKey(const Key('week-3-locked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('week-2-locked')));
    await tester.pumpAndSettle();

    expect(find.text('Week 2 is locked'), findsOneWidget);
    expect(
      find.text(
        'Finish the remaining mission in Week 1. Then this week opens automatically.',
      ),
      findsOneWidget,
    );
    expect(find.text('Interview five early users'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
