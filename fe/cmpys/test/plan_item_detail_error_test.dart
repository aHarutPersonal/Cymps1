import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';

/// Scripted repository: returns each queued result (value or error) in order,
/// repeating the last one when the queue runs out.
class _ScriptedRepo extends Fake implements PlanRepository {
  _ScriptedRepo(this._script, {List<Object>? jobScript})
    : _jobScript = jobScript ?? const [];
  final List<Object> _script; // PlanItemDetailed | Exception
  final List<Object> _jobScript; // PlanJobStatus | Exception
  int _calls = 0;
  int _jobCalls = 0;
  int retries = 0;
  int dailyToggles = 0;

  int get calls => _calls;
  int get jobCalls => _jobCalls;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async {
    final step = _script[_calls.clamp(0, _script.length - 1)];
    _calls++;
    if (step is Exception) throw step;
    return step as PlanItemDetailed;
  }

  @override
  Future<PlanJobStatus> getPlanDetailJobStatus(String jobId) async {
    final step = _jobScript[_jobCalls.clamp(0, _jobScript.length - 1)];
    _jobCalls++;
    if (step is Exception) throw step;
    return step as PlanJobStatus;
  }

  @override
  Future<String> regeneratePlanItemDetails(String itemId) async {
    retries++;
    return 'retry-job';
  }

  @override
  Future<bool> toggleDailyTask(String itemId) async {
    dailyToggles++;
    return true;
  }
}

PlanItemDetailed _pendingItem({bool completed = false, String? jobId}) =>
    PlanItemDetailed(
      item: BackendPlanItem.fromJson(const {'id': 'x', 'title': 'Read a book'}),
      detailsStatus: 'pending',
      completed: completed,
      jobId: jobId,
    );

PlanItemDetailed _availableItem() => PlanItemDetailed(
  item: BackendPlanItem.fromJson(const {'id': 'x', 'title': 'Read a book'}),
  detailsStatus: 'available',
);

const _runningJob = PlanJobStatus(
  id: 'detail-job',
  status: 'running',
  progressPercent: 60,
  step: 'generating_curriculum',
);

const _completedJob = PlanJobStatus(
  id: 'detail-job',
  status: 'completed',
  progressPercent: 100,
  step: 'done',
);

PlanItemDetailed _failedItem() => PlanItemDetailed(
  item: BackendPlanItem.fromJson(const {
    'id': 'x',
    'title': 'Build the prototype',
    'description': 'Ship a working prototype.',
  }),
  detailsStatus: 'failed',
  detailsError: 'This lesson could not be prepared.',
);

PlanItemDetailed _dailyItem({bool completed = false}) => PlanItemDetailed(
  item: BackendPlanItem.fromJson(const {
    'id': 'x',
    'title': 'Deliberate practice',
    'type': 'practice',
    'description': 'Practice the core skill every day.',
  }),
  detailsStatus: 'available',
  dailyInstructions: 'Run one focused drill and write down the result.',
  completedToday: completed,
);

Widget _app(PlanRepository repo) => ProviderScope(
  overrides: [planRepositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: PlanItemDetailScreen(itemId: 'x')),
);

void main() {
  testWidgets('network failure shows the connection error copy', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_ScriptedRepo([const TimeoutError()])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
  });

  testWidgets(
    'non-network failure shows a generic error, not connection copy',
    (tester) async {
      await tester.pumpWidget(
        _app(_ScriptedRepo([Exception('parse failure')])),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Check your connection'), findsNothing);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    },
  );

  testWidgets('a failed background poll keeps the loaded content on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_ScriptedRepo([_pendingItem(), const TimeoutError()])),
    );
    // Discrete pumps: the pending-details state animates a spinner, so
    // pumpAndSettle would never settle.
    await tester.pump();
    await tester.pump();
    expect(find.text('Read a book'), findsOneWidget);

    // First poll tick (4s) fails — content must survive, no error screen.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Read a book'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);

    // Dispose the screen so the retry poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed detail generation stops loading and offers retry', (
    tester,
  ) async {
    final repo = _ScriptedRepo([_failedItem(), _pendingItem()]);
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();

    expect(find.text('This lesson could not be prepared.'), findsOneWidget);
    expect(find.text('Generate again'), findsOneWidget);

    await tester.tap(find.text('Generate again'));
    await tester.pump();
    await tester.pump();
    expect(repo.retries, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed legacy mission never enters the lesson polling loop', (
    tester,
  ) async {
    final repo = _ScriptedRepo([_pendingItem(completed: true)]);
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('nothing left to load'), findsOneWidget);
    expect(find.textContaining('Writing your lesson'), findsNothing);
    expect(repo.calls, 1);

    await tester.pump(const Duration(seconds: 12));
    expect(repo.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('detail job completion refetches once and stops polling', (
    tester,
  ) async {
    final repo = _ScriptedRepo(
      [_pendingItem(jobId: 'detail-job'), _availableItem()],
      jobScript: const [_completedJob],
    );
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(repo.jobCalls, 1);
    expect(repo.calls, 2);
    expect(find.textContaining('Writing your lesson'), findsNothing);

    await tester.pump(const Duration(seconds: 12));
    expect(repo.jobCalls, 1);
    expect(repo.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('permanently pending job reaches a bounded background state', (
    tester,
  ) async {
    final repo = _ScriptedRepo(
      [_pendingItem(jobId: 'detail-job')],
      jobScript: const [_runningJob],
    );
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
    }

    expect(find.text('Check status'), findsOneWidget);
    expect(find.textContaining('still being prepared'), findsOneWidget);
    final callsAtBudget = repo.jobCalls;
    await tester.pump(const Duration(seconds: 30));
    expect(repo.jobCalls, callsAtBudget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('practice item renders as a daily rhythm without generation', (
    tester,
  ) async {
    final repo = _ScriptedRepo([_dailyItem(), _dailyItem(completed: true)]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('DAILY RHYTHM · WEEK 1'), findsOneWidget);
    expect(
      find.text('Run one focused drill and write down the result.'),
      findsOneWidget,
    );
    expect(find.text('Complete for today'), findsOneWidget);
    expect(find.textContaining('Writing your lesson'), findsNothing);

    await tester.tap(find.text('Complete for today'));
    await tester.pumpAndSettle();
    expect(repo.dailyToggles, 1);
    expect(find.text('Mark as not done today'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
