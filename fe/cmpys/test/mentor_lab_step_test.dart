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
    });
  }
}

void main() {
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
    expect(find.text('Your plan is ready.'), findsOneWidget);
    expect(find.text('Enter CMPYS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Enter CMPYS'));
    await tester.pump();
    expect(finished, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('benefit cards can be swiped while generation runs', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(_ResultsRepo()),
          planRepositoryProvider.overrideWithValue(_CompletedPlanRepo()),
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
    await tester.pumpAndSettle();

    expect(
      find.text('The interview is not a personality quiz.'),
      findsOneWidget,
    );
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Learn the pattern, not the costume.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
