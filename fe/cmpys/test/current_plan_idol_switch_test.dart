// Regression: after the user switches to a new idol (new session), the Plan
// tab must show the NEW idol's plan — not the previous idol's cached plan.
//
// Root cause: currentPlanProvider only re-fetched /plans/current on construction
// or a plan-job-id change, never when the active idol changed, so it kept
// serving the stale previous-idol plan (e.g. a Warren Buffett plan after the
// user had moved on to Martin Luther King Jr.).

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

  @override
  Future<BackendPlan?> getCurrentPlan() async => plan;

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    requestedJobs.add(jobId);
    return jobs[jobId]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
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

  test('still shows the plan when the active idol is unknown (no regression)',
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
  });

  test('a new onboarding job replaces polling for a previous account job',
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
  });
}
