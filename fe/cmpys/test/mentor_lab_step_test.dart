import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_lab_step.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ResultsRepo extends Fake implements SessionRepository {
  int starts = 0;

  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) async* {
    starts++;
    yield {'type': 'plan_job', 'job_id': 'plan-job-1'};
    yield {'type': 'section', 'section': 'comparison'};
    yield {
      'type': 'chunk',
      'section': 'comparison',
      'content': 'Comparison ready.',
    };
    yield {'type': 'section', 'section': 'blueprint'};
    yield {
      'type': 'chunk',
      'section': 'blueprint',
      'content': 'Blueprint ready.',
    };
    yield {'type': 'done', 'phase': 'completed'};
  }
}

class _CompletedPlanRepo extends Fake implements PlanRepository {
  int polls = 0;

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    polls++;
    return PlanJobStatus.fromJson({
      'id': jobId,
      'status': 'completed',
      'progressPercent': 100,
      // Tutorial 1 is ready, so the lab may say the plan is ready to begin.
      'results': {'ready_lesson_count': 1},
    });
  }
}

/// The v3 lab never stops moving while it works (halo rings, spinners), so
/// settle-based tests run it with animations off, as the OS setting would.
Widget _reducedMotion(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(disableAnimations: true),
  child: child!,
);

void main() {
  comparisonWhileWaitingTests();

  testWidgets('starts results automatically and waits for the real plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final resultsRepo = _ResultsRepo();
    final planRepo = _CompletedPlanRepo();
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';
    var finished = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(resultsRepo),
          planRepositoryProvider.overrideWithValue(planRepo),
        ],
        child: MaterialApp(
          builder: _reducedMotion,
          home: CmpysMentorLabStep(
            idol: defaultIdol(),
            draft: draft,
            onDone: () => finished = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(resultsRepo.starts, 1);
    expect(planRepo.polls, greaterThanOrEqualTo(1));
    expect(draft.comparisonMd, 'Comparison ready.');
    expect(draft.blueprintMd, 'Blueprint ready.');
    expect(draft.planJobId, 'plan-job-1');
    expect(find.text('Your plan is ready'), findsOneWidget);
    expect(find.text('to begin.'), findsOneWidget);
    expect(find.text('Go to Today'), findsOneWidget);
    expect(find.text('See the full plan'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Go to Today'));
    await tester.pump();
    expect(finished, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}

class _RunningPlanRepo extends Fake implements PlanRepository {
  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    return PlanJobStatus.fromJson({
      'id': jobId,
      'status': 'running',
      'progressPercent': 20,
    });
  }
}

void comparisonWhileWaitingTests() {
  testWidgets(
    'shows the streamed comparison while the plan is still building',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final draft = CmpysOnboardingDraft()..sessionId = 'session-1';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(_ResultsRepo()),
            planRepositoryProvider.overrideWithValue(_RunningPlanRepo()),
          ],
          child: MaterialApp(
            home: CmpysMentorLabStep(
              idol: defaultIdol(),
              draft: draft,
              onDone: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.textContaining('Comparison ready.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Go to Today'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
