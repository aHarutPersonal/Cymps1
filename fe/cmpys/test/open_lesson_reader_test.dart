import 'package:cmpys/features/cmpys/state/plan_providers.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/open_lesson_reader.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Today, the Plan tab and the mission screen open the tutorial reader through
// one helper, and every one of them refreshes the same reads afterwards: the
// mission's normal read (Today's), its peek (the Plan tab's) and, after a
// completion, the plan.

const _item = BackendPlanItem(
  id: 'mission-1',
  title: 'Find what the business really earns',
  type: 'project',
  description: '',
  weekStart: 1,
  weekEnd: 1,
  successMetric: '',
  estimatedHours: 2,
  status: 'in_progress',
  progressPercent: 20,
);

const _detail = PlanItemDetailed(
  item: _item,
  detailsStatus: 'available',
  lessonFormat: 'tutorial_v1',
  steps: [
    PlanStepDetail(
      id: 's1',
      title: 'Reported earnings are an opinion',
      lessonContent: '# Reported earnings are an opinion',
      lessonFormat: 'tutorial_v1',
    ),
    PlanStepDetail(
      id: 's2',
      title: 'Cash and accrual on one page',
      lessonContent: '# Cash and accrual on one page',
      lessonFormat: 'tutorial_v1',
    ),
  ],
);

class _Repo extends Fake implements PlanRepository {
  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async => _detail;

  @override
  Future<PlanJobStatus> getPlanDetailJobStatus(String jobId) async =>
      PlanJobStatus(id: jobId, status: 'completed', progressPercent: 100);
}

class _Plan extends CurrentPlanController {
  _Plan(PlanRepository repo) : super(repo: repo, readJobId: () => null) {
    state = const CurrentPlanState(status: CurrentPlanStatus.empty);
  }

  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

/// Counts the reads of the mission behind Today's and the Plan tab's
/// providers, and keeps both alive the way those tabs do.
class _Reads {
  int today = 0;
  int peek = 0;

  List<Override> overrides(PlanRepository repo, _Plan plan) => [
    planRepositoryProvider.overrideWithValue(repo),
    currentPlanProvider.overrideWith((_) => plan),
    todayMissionDetailProvider.overrideWith((ref, id) async {
      today++;
      return _detail;
    }),
    planMissionPeekProvider.overrideWith((ref, id) async {
      peek++;
      return _detail;
    }),
  ];

  Widget keepAlive() => Consumer(
    builder: (context, ref, _) {
      ref.watch(todayMissionDetailProvider(_item.id));
      ref.watch(planMissionPeekProvider(_item.id));
      return const SizedBox.shrink();
    },
  );
}

Future<void> _closeReader(WidgetTester tester, bool? completed) async {
  Navigator.of(tester.element(find.byType(LessonReaderScreen))).pop(completed);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the helper opens the tutorial and refreshes the same reads', (
    tester,
  ) async {
    final repo = _Repo();
    final plan = _Plan(repo);
    final reads = _Reads();
    final results = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: reads.overrides(repo, plan),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Column(
                children: [
                  reads.keepAlive(),
                  TextButton(
                    onPressed: () async => results.add(
                      await openLessonReader(context, ref, _detail, 1),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect((reads.today, reads.peek), (1, 1));
    final refreshesBefore = plan.refreshes;

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final reader = tester.widget<LessonReaderScreen>(
      find.byType(LessonReaderScreen),
    );
    expect(reader.step.id, 's2');
    expect(reader.stepNumber, 2);
    expect(reader.totalSteps, 2);
    expect(reader.nextTitle, '');

    // Backed out: both reads refresh, the plan does not.
    await _closeReader(tester, null);
    expect(results, [false]);
    expect((reads.today, reads.peek), (2, 2));
    expect(plan.refreshes, refreshesBefore);

    // Completed: both reads and the plan refresh.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _closeReader(tester, true);
    expect(results, [false, true]);
    expect((reads.today, reads.peek), (3, 3));
    expect(plan.refreshes, refreshesBefore + 1);
  });

  testWidgets('the reader carries the opener’s shell branch, Plan’s by '
      'default', (tester) async {
    final repo = _Repo();
    final plan = _Plan(repo);
    final reads = _Reads();
    await tester.pumpWidget(
      ProviderScope(
        overrides: reads.overrides(repo, plan),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => openLessonReader(context, ref, _detail, 0),
                    child: const Text('Open from Plan'),
                  ),
                  TextButton(
                    onPressed: () => openLessonReader(
                      context,
                      ref,
                      _detail,
                      0,
                      shellBranchIndex:
                          ActiveBookNarrationResume.todayBranchIndex,
                    ),
                    child: const Text('Open from Today'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final (label, branch) in [
      ('Open from Plan', ActiveBookNarrationResume.planBranchIndex),
      ('Open from Today', ActiveBookNarrationResume.todayBranchIndex),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LessonReaderScreen>(find.byType(LessonReaderScreen))
            .shellBranchIndex,
        branch,
      );
      await _closeReader(tester, null);
    }
  });

  testWidgets('a mission opened from Today opens its tutorials from Today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final plan = _Plan(repo);
    final reads = _Reads();
    await tester.pumpWidget(
      ProviderScope(
        overrides: reads.overrides(repo, plan),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const PlanItemDetailScreen(
            itemId: 'mission-1',
            shellBranchIndex: ActiveBookNarrationResume.todayBranchIndex,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reported earnings are an opinion'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LessonReaderScreen>(find.byType(LessonReaderScreen))
          .shellBranchIndex,
      ActiveBookNarrationResume.todayBranchIndex,
    );
    await _closeReader(tester, null);
  });

  testWidgets('a tutorial finished from the mission screen refreshes Today’s '
      'read and the Plan tab’s peek', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final plan = _Plan(repo);
    final reads = _Reads();
    await tester.pumpWidget(
      ProviderScope(
        overrides: reads.overrides(repo, plan),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Stack(children: [reads.keepAlive(), child!]),
          ),
          home: const PlanItemDetailScreen(itemId: 'mission-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect((reads.today, reads.peek), (1, 1));
    final refreshesBefore = plan.refreshes;

    await tester.tap(find.text('Reported earnings are an opinion'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonReaderScreen), findsOneWidget);
    await _closeReader(tester, true);

    expect((reads.today, reads.peek), (2, 2));
    expect(plan.refreshes, refreshesBefore + 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}
