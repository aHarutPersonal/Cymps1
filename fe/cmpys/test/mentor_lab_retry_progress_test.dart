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
  int progress = 90;
  final restarted = Completer<String>();

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async =>
      PlanJobStatus(id: jobId, status: status, progressPercent: progress);

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
    double? progress() => tester
        .widget<LinearProgressIndicator>(
          find.byKey(const Key('mentor-lab-progress')),
        )
        .value;
    expect(progress(), .95);

    plans.status = 'failed';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mentor-lab-retry')));
    await tester.pump();
    expect(progress(), .62);

    plans.status = 'running';
    plans.progress = 10;
    plans.restarted.complete('job-1');
    await tester.pumpAndSettle();
    expect(progress(), .66);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
