// Regression: after the user switches to a new idol (new session), the Plan
// tab must show the NEW idol's plan — not the previous idol's cached plan.
//
// Root cause: currentPlanProvider only re-fetched /plans/current on construction
// or a plan-job-id change, never when the active idol changed, so it kept
// serving the stale previous-idol plan (e.g. a Warren Buffett plan after the
// user had moved on to Martin Luther King Jr.).

import 'dart:async';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter_test/flutter_test.dart';

BackendPlan _planFor(String idol) => BackendPlan(
  id: 'plan-$idol',
  durationWeeks: 12,
  weeklyHours: 6,
  idolName: idol,
  items: const [
    BackendPlanItem(
      id: 'item-1',
      title: 'A task',
      type: 'project',
      description: 'do the thing',
      weekStart: 1,
      weekEnd: 1,
      successMetric: 'done',
      estimatedHours: 2,
      status: 'not_started',
      progressPercent: 0,
    ),
  ],
);

class _FakePlanRepo implements PlanRepository {
  _FakePlanRepo(this.plan);
  BackendPlan? plan;
  final requestedJobs = <String>[];
  final jobs = <String, PlanJobStatus>{};
  final pendingJobs = <String, Completer<PlanJobStatus>>{};
  Completer<BackendPlan?>? pendingPlan;
  Exception? planError;

  @override
  Future<BackendPlan?> getCurrentPlan() async {
    if (planError case final error?) throw error;
    return pendingPlan?.future ?? plan;
  }

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    requestedJobs.add(jobId);
    if (pendingJobs[jobId] case final pending?) return pending.future;
    return jobs[jobId]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final error in [
    const NetworkError(),
    const TimeoutError(),
    const ApiError(message: 'Unavailable', statusCode: 503),
  ]) {
    test(
      'a transient refresh failure retains the saved plan: $error',
      () async {
        final saved = _planFor('Seneca');
        final repo = _FakePlanRepo(saved);
        var generationRequests = 0;
        final controller = CurrentPlanController(
          repo: repo,
          readJobId: () => null,
          readIdolName: () => 'Seneca',
          requestGeneration: () async {
            generationRequests++;
            return null;
          },
        );
        addTearDown(controller.dispose);
        await pumpEventQueue();
        repo.planError = error;
        await controller.refresh();
        expect(controller.state.status, CurrentPlanStatus.ready);
        expect(controller.state.plan, same(saved));
        expect(generationRequests, 0);
      },
    );
  }

  for (final status in [401, 403]) {
    test(
      'authorization failure does not retain the saved plan: $status',
      () async {
        final repo = _FakePlanRepo(_planFor('Seneca'));
        final controller = CurrentPlanController(
          repo: repo,
          readJobId: () => null,
        );
        addTearDown(controller.dispose);
        await pumpEventQueue();
        repo.planError = ApiError(message: 'Denied', statusCode: status);
        await controller.refresh();
        expect(controller.state.status, CurrentPlanStatus.failed);
        expect(controller.state.plan, isNull);
      },
    );
  }

  test(
    'a failed mentor refresh never restores the previous mentor plan',
    () async {
      final repo = _FakePlanRepo(_planFor('Seneca'));
      var mentor = 'Seneca';
      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => null,
        readIdolName: () => mentor,
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();
      mentor = 'Warren Buffett';
      repo.planError = const NetworkError();
      controller.onIdolChanged(mentor);
      await pumpEventQueue();
      expect(controller.state.status, CurrentPlanStatus.failed);
      expect(controller.state.plan, isNull);
    },
  );

  test(
    'an obsolete response for the same job cannot fail a restarted poll',
    () async {
      final repo = _FakePlanRepo(null);
      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => null,
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();
      final old = Completer<PlanJobStatus>();
      repo.pendingJobs['job'] = old;
      controller.onJobIdChanged('job');
      await pumpEventQueue();
      await controller.refresh();
      repo.pendingJobs.remove('job');
      repo.jobs['job'] = const PlanJobStatus(
        id: 'job',
        status: 'running',
        progressPercent: 80,
      );
      controller.onJobIdChanged('job');
      await pumpEventQueue();
      expect(controller.state.jobProgress, 80);
      old.complete(
        const PlanJobStatus(id: 'job', status: 'failed', progressPercent: 0),
      );
      await pumpEventQueue();
      expect(controller.state.status, CurrentPlanStatus.generating);
      expect(controller.state.jobProgress, 80);
    },
  );

  test(
    'a slow old job cannot delay a fresh job or overwrite its progress',
    () async {
      final repo = _FakePlanRepo(null);
      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => null,
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();
      final old = Completer<PlanJobStatus>();
      repo.pendingJobs['old'] = old;
      controller.onJobIdChanged('old');
      await pumpEventQueue();
      repo.jobs['new'] = const PlanJobStatus(
        id: 'new',
        status: 'running',
        progressPercent: 70,
      );
      controller.onJobIdChanged('new');
      await pumpEventQueue();
      expect(repo.requestedJobs, contains('new'));
      expect(controller.state.jobProgress, 70);
      old.complete(
        const PlanJobStatus(id: 'old', status: 'failed', progressPercent: 0),
      );
      await pumpEventQueue();
      expect(controller.state.jobProgress, 70);
    },
  );

  test(
    'switching mentor hides the previous plan while the fresh read is pending',
    () async {
      final repo = _FakePlanRepo(_planFor('Warren Buffett'));
      var idol = 'Warren Buffett';
      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => null,
        readIdolName: () => idol,
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(controller.state.status, CurrentPlanStatus.ready);
      final pending = Completer<BackendPlan?>();
      repo.pendingPlan = pending;
      idol = 'Seneca';
      controller.onIdolChanged(idol);
      expect(controller.state.plan, isNull);
      pending.complete(_planFor(idol));
      await pumpEventQueue();
      expect(controller.state.plan?.idolName, idol);
    },
  );

  test(
    'late automatic recovery cannot replace a newer onboarding job',
    () async {
      final repo = _FakePlanRepo(null);
      final recovery = Completer<String?>();
      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => null,
        requestGeneration: () => recovery.future,
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();
      repo.jobs['new'] = const PlanJobStatus(
        id: 'new',
        status: 'running',
        progressPercent: 70,
      );
      repo.jobs['obsolete'] = const PlanJobStatus(
        id: 'obsolete',
        status: 'running',
        progressPercent: 10,
      );
      controller.onJobIdChanged('new');
      await pumpEventQueue();
      recovery.complete('obsolete');
      await pumpEventQueue();
      expect(controller.state.jobProgress, 70);
      expect(repo.requestedJobs, isNot(contains('obsolete')));
    },
  );

  test('refreshes to the new idol plan when the active idol changes', () async {
    final repo = _FakePlanRepo(_planFor('Warren Buffett'));
    var activeIdol = 'Warren Buffett';

    final controller = CurrentPlanController(
      repo: repo,
      readJobId: () => null,
      readIdolName: () => activeIdol,
    );
    await controller.refresh();

    expect(controller.state.status, CurrentPlanStatus.ready);
    expect(controller.state.plan?.idolName, 'Warren Buffett');

    // User switches idols; the backend now serves the new idol's plan.
    repo.plan = _planFor('Martin Luther King Jr.');
    activeIdol = 'Martin Luther King Jr.';
    controller.onIdolChanged('Martin Luther King Jr.');
    await pumpEventQueue();

    expect(controller.state.plan?.idolName, 'Martin Luther King Jr.');
  });

  test('never shows a plan whose idol differs from the active idol', () async {
    // Backend still returns the old Buffett plan, but the user is now on MLK
    // and no new plan exists yet. The stale plan must NOT be presented.
    final repo = _FakePlanRepo(_planFor('Warren Buffett'));

    final controller = CurrentPlanController(
      repo: repo,
      readJobId: () => null,
      readIdolName: () => 'Martin Luther King Jr.',
    );
    await controller.refresh();

    expect(controller.state.status, isNot(CurrentPlanStatus.ready));
  });

  test(
    'still shows the plan when the active idol is unknown (no regression)',
    () async {
      final repo = _FakePlanRepo(_planFor('Warren Buffett'));

      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => null,
        readIdolName: () => null,
      );
      await controller.refresh();

      expect(controller.state.status, CurrentPlanStatus.ready);
      expect(controller.state.plan?.idolName, 'Warren Buffett');
    },
  );

  test(
    'a new onboarding job replaces polling for a previous account job',
    () async {
      final repo = _FakePlanRepo(null)
        ..jobs['old-job'] = const PlanJobStatus(
          id: 'old-job',
          status: 'running',
          progressPercent: 0,
        )
        ..jobs['new-job'] = const PlanJobStatus(
          id: 'new-job',
          status: 'completed',
          progressPercent: 100,
        );
      var storedJobId = 'old-job';
      final controller = CurrentPlanController(
        repo: repo,
        readJobId: () => storedJobId,
        readIdolName: () => 'Oprah Winfrey',
      );
      await pumpEventQueue();
      expect(controller.state.status, CurrentPlanStatus.generating);

      repo.plan = _planFor('Oprah Winfrey');
      storedJobId = 'new-job';
      controller.onJobIdChanged('new-job');
      await pumpEventQueue();

      expect(repo.requestedJobs, contains('new-job'));
      expect(controller.state.status, CurrentPlanStatus.ready);
      expect(controller.state.plan?.idolName, 'Oprah Winfrey');
      controller.dispose();
    },
  );
}
