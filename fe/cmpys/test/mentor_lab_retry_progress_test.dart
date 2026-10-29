import 'dart:async';

import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_lab_step.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedSessions extends Fake implements SessionRepository {}

class _RetryPlans extends Fake implements PlanRepository {
  String status = 'running';
  String? step = 'preparing_current_week';
  int progress = 96;
  final restarted = Completer<String>();

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async => PlanJobStatus(
    id: jobId,
    status: status,
    progressPercent: progress,
    step: step,
  );

  @override
  Future<String> generatePlan({
    required String idolId,
    required int targetAge,
    String? sessionId,
    int durationWeeks = 12,
    int weeklyHours = 10,
  }) => restarted.future;
}

void main() {
  testWidgets('retry restores confirmed progress instead of the failed peak', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plans = _RetryPlans();
    final draft = CmpysOnboardingDraft()
      ..sessionId = 'preview-session'
      ..backendIdolId = 'mentor-1'
      ..planJobId = 'job-1'
      ..comparisonMd = 'Completed comparison'
      ..blueprintMd = 'Completed blueprint';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(_UnusedSessions()),
          planRepositoryProvider.overrideWithValue(plans),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: CmpysMentorLabStep(
            idol: defaultIdol(),
            draft: draft,
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder icon(String stage, String state) =>
        find.byKey(Key('lab-stage-icon-$stage-$state'));
    final roadmap = find.byKey(const Key('lab-preview-roadmap'));

    // The job reached its publishing step: the backbone is confirmed.
    expect(icon('plan', 'done'), findsOneWidget);
    expect(icon('t1', 'run'), findsOneWidget);
    expect(roadmap, findsOneWidget);

    // It then fails: the backbone stays done and the failure lands on the
    // stage after it.
    plans.status = 'failed';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(icon('plan', 'done'), findsOneWidget);
    expect(icon('t1', 'fail'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mentor-lab-retry')));
    await tester.pump();

    // Retrying drops back to the results boundary: the failed peak is not
    // shown as confirmed while the plan restarts.
    expect(icon('plan', 'done'), findsNothing);
    expect(icon('plan', 'run'), findsOneWidget);
    expect(icon('t1', 'fail'), findsNothing);
    expect(roadmap, findsNothing);

    // Only what the restarted job reports is shown again.
    plans
      ..status = 'running'
      ..step = 'generating_curriculum'
      ..progress = 10;
    plans.restarted.complete('job-1');
    await tester.pumpAndSettle();
    expect(icon('plan', 'run'), findsOneWidget);
    expect(icon('plan', 'done'), findsNothing);
    expect(roadmap, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
