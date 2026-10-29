import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_lab_step.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a scripted generate-results stream per attempt.
class _Sessions extends Fake implements SessionRepository {
  _Sessions(this.script);

  final Stream<Map<String, dynamic>> Function(int attempt) script;
  int starts = 0;

  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) {
    starts++;
    return script(starts);
  }
}

class _Plans extends Fake implements PlanRepository {
  String status = 'running';
  String? step;
  int progress = 30;
  int? totalLessons;
  int? readyLessons;
  BackendPlan? plan;
  int polls = 0;

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    polls++;
    return PlanJobStatus(
      id: jobId,
      status: status,
      progressPercent: progress,
      step: step,
      totalLessonCount: totalLessons,
      readyLessonCount: readyLessons,
    );
  }

  @override
  Future<BackendPlan?> getCurrentPlan() async => plan;

  /// Mission 1's peek (`?peek=true`): its tutorials as they stand.
  PlanItemDetailed? peekDetail;
  Object? peekError;
  final peekedIds = <String>[];
  int normalReads = 0;

  @override
  Future<PlanItemDetailed> peekPlanItemDetailed(String itemId) async {
    peekedIds.add(itemId);
    if (peekError case final error?) throw error;
    return peekDetail!;
  }

  /// The normal read, which can start generation: the lab never uses it.
  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async {
    normalReads++;
    throw StateError('the lab must only peek');
  }
}

BackendPlanItem _mission(String id, {int week = 1, String type = 'project'}) =>
    BackendPlanItem(
      id: id,
      title: 'Mission $id',
      type: type,
      description: '',
      weekStart: week,
      weekEnd: week,
      successMetric: '',
      estimatedHours: 2,
      status: 'not_started',
      progressPercent: 0,
    );

/// A plan whose week 1 opens with mission `m1` (after a habit). Without
/// `weeklyMinutes` the server predates peek ([planSupportsPeek]).
BackendPlan _planWithMission({bool supportsPeek = true}) => BackendPlan(
  id: 'plan-1',
  durationWeeks: 12,
  weeklyHours: 3,
  weeklyMinutes: supportsPeek ? 180 : null,
  items: [
    _mission('h1', type: 'habit'),
    _mission('m1'),
    _mission('m2'),
    _mission('m9', week: 2),
  ],
);

/// Mission 1's details, its first tutorial written or not.
PlanItemDetailed _missionDetail({required bool firstReady}) =>
    PlanItemDetailed.fromJson({
      'item': {'id': 'm1', 'title': 'Mission m1'},
      'details_status': firstReady ? 'partial' : 'pending',
      'details': {
        'lesson_format': 'tutorial_v1',
        'steps': [
          {
            'id': 'step_1',
            'title': 'Tutorial one',
            if (firstReady) 'lesson_content': '# Tutorial one\n\nRead this.',
          },
          {'id': 'step_2', 'title': 'Tutorial two'},
        ],
      },
    });

const _comparison =
    'At 24, Buffett had read every investing book he could find. You have '
    'curiosity and a few trades. The gap that matters most is evidence. He '
    'wrote down what a business earned before he bought it.';

const _blueprint =
    '## Strategic Verdict\nYou have no written analysis yet.\n\n'
    '## Twelve-Week Thesis\nLearn to read a business like an owner before you '
    'price it like a trader.\n\n## Phase Intent\n- Weeks 1-3 — Foundation.';

Stream<Map<String, dynamic>> _fullRun() async* {
  yield {'type': 'plan_job', 'job_id': 'job-1'};
  yield {'type': 'section', 'section': 'comparison'};
  yield {'type': 'chunk', 'section': 'comparison', 'content': _comparison};
  yield {'type': 'section', 'section': 'blueprint'};
  yield {'type': 'chunk', 'section': 'blueprint', 'content': _blueprint};
  yield {'type': 'comparison_scores', 'ready': true, 'status': 'ready'};
  yield {'type': 'done', 'phase': 'completed'};
}

Future<void> _mount(
  WidgetTester tester, {
  required _Sessions sessions,
  required _Plans plans,
  VoidCallback? onDone,
  VoidCallback? onPlan,
  CmpysOnboardingDraft? draft,
  bool reducedMotion = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(sessions),
        planRepositoryProvider.overrideWithValue(plans),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: CmpysMentorLabStep(
          idol: defaultIdol(),
          draft: draft ?? (CmpysOnboardingDraft()..sessionId = 'session-1'),
          onDone: onDone ?? () {},
          onPlan: onPlan,
        ),
      ),
    ),
  );
}

Finder _icon(String stage, String state) =>
    find.byKey(Key('lab-stage-icon-$stage-$state'));

void main() {
  testWidgets('stage_fail_shows_retry_and_keeps_done_stages', (tester) async {
    final sessions = _Sessions((attempt) async* {
      yield {'type': 'plan_job', 'job_id': 'job-1'};
      yield {'type': 'section', 'section': 'comparison'};
      yield {'type': 'chunk', 'section': 'comparison', 'content': _comparison};
      yield {'type': 'section', 'section': 'blueprint'};
      yield {'type': 'chunk', 'section': 'blueprint', 'content': 'Partial'};
      if (attempt == 1) {
        yield {
          'type': 'error',
          'section': 'blueprint',
          'code': 'generation_failed',
          'message': 'PRIVATE provider detail',
        };
        return;
      }
      yield {'type': 'chunk', 'section': 'blueprint', 'content': ' verdict.'};
      yield {'type': 'comparison_scores', 'ready': true};
      yield {'type': 'done', 'phase': 'completed'};
    });
    final plans = _Plans();
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 200));

    // Written comparison landed and stays done; the blueprint is the failure.
    expect(_icon('cmp', 'done'), findsOneWidget);
    expect(_icon('bp', 'fail'), findsOneWidget);
    expect(_icon('bp', 'run'), findsNothing);
    expect(
      find.text(
        'The blueprint request didn’t finish. Earlier steps are saved.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(find.text('One step'), findsOneWidget);
    expect(find.text('didn’t finish.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Go to Today'), findsNothing);
    expect(sessions.starts, 1);

    // Retry calls the existing path and the done stage never flips back.
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(sessions.starts, 2);
    expect(find.text('Retry'), findsNothing);
    expect(_icon('cmp', 'done'), findsOneWidget);
    expect(_icon('bp', 'fail'), findsNothing);
    expect(find.textContaining('Earlier steps are saved'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('previews_appear_in_order', (tester) async {
    final events = StreamController<Map<String, dynamic>>();
    final sessions = _Sessions((_) => events.stream);
    final plans = _Plans();
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump();

    final comparison = find.byKey(const Key('lab-preview-comparison'));
    final blueprint = find.byKey(const Key('lab-preview-blueprint'));
    final roadmap = find.byKey(const Key('lab-preview-roadmap'));
    expect(comparison, findsNothing);
    expect(blueprint, findsNothing);
    expect(roadmap, findsNothing);

    // 1. The comparison streams in: its card shows the opening sentences.
    events
      ..add({'type': 'plan_job', 'job_id': 'job-1'})
      ..add({'type': 'section', 'section': 'comparison'})
      ..add({'type': 'chunk', 'section': 'comparison', 'content': _comparison});
    await tester.pump(const Duration(milliseconds: 200));
    expect(comparison, findsOneWidget);
    expect(find.text('From your comparison'.toUpperCase()), findsOneWidget);
    expect(
      find.textContaining('The gap that matters most is evidence.'),
      findsOneWidget,
    );
    expect(find.textContaining('He wrote down'), findsNothing);
    expect(blueprint, findsNothing);
    expect(roadmap, findsNothing);

    // 2. The blueprint lands: its direction line appears under the comparison.
    events
      ..add({'type': 'section', 'section': 'blueprint'})
      ..add({'type': 'chunk', 'section': 'blueprint', 'content': _blueprint});
    await tester.pump(const Duration(milliseconds: 200));
    expect(blueprint, findsOneWidget);
    expect(
      find.text(
        'Learn to read a business like an owner before you price it like a trader.',
      ),
      findsOneWidget,
    );
    expect(roadmap, findsNothing);

    // 3. The plan backbone exists: the twelve-week grid appears last.
    plans
      ..step = 'preparing_current_week'
      ..progress = 95;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(roadmap, findsOneWidget);
    for (var week = 1; week <= 12; week++) {
      expect(find.text('W$week'), findsOneWidget);
    }

    final comparisonTop = tester.getTopLeft(comparison).dy;
    final blueprintTop = tester.getTopLeft(blueprint).dy;
    final roadmapTop = tester.getTopLeft(roadmap).dy;
    expect(comparisonTop, lessThan(blueprintTop));
    expect(blueprintTop, lessThan(roadmapTop));
    expect(tester.takeException(), isNull);

    // Let the stream finish so no timer outlives the test.
    events
      ..add({'type': 'comparison_scores', 'ready': true})
      ..add({'type': 'done', 'phase': 'completed'});
    unawaited(events.close());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'stages follow the stream and the plan job, then the plan is ready',
    (tester) async {
      final events = StreamController<Map<String, dynamic>>();
      final sessions = _Sessions((_) => events.stream);
      final plans = _Plans();
      await _mount(tester, sessions: sessions, plans: plans);
      await tester.pump();

      // Working on the comparison: it runs, everything else waits.
      expect(find.text('Buffett is studying'), findsOneWidget);
      expect(find.text('your starting point.'), findsOneWidget);
      expect(_icon('cmp', 'run'), findsOneWidget);
      expect(_icon('dim', 'wait'), findsOneWidget);
      expect(_icon('bp', 'wait'), findsOneWidget);
      expect(_icon('plan', 'wait'), findsOneWidget);
      expect(_icon('t1', 'wait'), findsOneWidget);
      expect(find.text('You at 24 next to Buffett at 24'), findsOneWidget);

      // The server saved the comparison and opened the blueprint; the plan job
      // is already running next to it.
      events
        ..add({'type': 'plan_job', 'job_id': 'job-1'})
        ..add({'type': 'section', 'section': 'comparison'})
        ..add({
          'type': 'chunk',
          'section': 'comparison',
          'content': _comparison,
        })
        ..add({'type': 'section', 'section': 'blueprint'})
        ..add({'type': 'chunk', 'section': 'blueprint', 'content': _blueprint});
      await tester.pump(const Duration(milliseconds: 200));
      expect(_icon('cmp', 'done'), findsOneWidget);
      expect(_icon('dim', 'run'), findsOneWidget);
      expect(_icon('bp', 'run'), findsOneWidget);
      expect(_icon('plan', 'run'), findsOneWidget);
      expect(_icon('t1', 'wait'), findsOneWidget);

      // The scores event follows the blueprint: both stages land.
      events.add({'type': 'comparison_scores', 'ready': true});
      await tester.pump(const Duration(milliseconds: 200));
      expect(_icon('dim', 'done'), findsOneWidget);
      expect(_icon('bp', 'done'), findsOneWidget);

      // The job reaches its publishing step: backbone done, tutorial running.
      plans
        ..step = 'preparing_current_week'
        ..progress = 95;
      await tester.pump(const Duration(seconds: 3));
      expect(_icon('plan', 'done'), findsOneWidget);
      expect(_icon('t1', 'run'), findsOneWidget);
      expect(find.text('Go to Today'), findsNothing);

      // The job completes with tutorial 1 ready; with the stream finished
      // the plan is ready.
      plans
        ..status = 'completed'
        ..step = 'done'
        ..progress = 100
        ..readyLessons = 1;
      events.add({'type': 'done', 'phase': 'completed'});
      unawaited(events.close());
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_icon('t1', 'done'), findsOneWidget);
      expect(find.text('Your plan is ready'), findsOneWidget);
      expect(find.text('to begin.'), findsOneWidget);
      expect(find.byKey(const Key('lab-done-badge')), findsOneWidget);
      expect(find.text('Go to Today'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the plan is not ready until the plan job completes', (
    tester,
  ) async {
    // Everything streamed and saved, but the job still runs: no entry yet.
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans();
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_icon('cmp', 'done'), findsOneWidget);
    expect(_icon('dim', 'done'), findsOneWidget);
    expect(_icon('bp', 'done'), findsOneWidget);
    expect(_icon('plan', 'run'), findsOneWidget);
    expect(find.text('Go to Today'), findsNothing);
    expect(find.text('Buffett is studying'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scores that are not ready yet never hold the learner up', (
    tester,
  ) async {
    final sessions = _Sessions((_) async* {
      yield {'type': 'plan_job', 'job_id': 'job-1'};
      yield {'type': 'section', 'section': 'comparison'};
      yield {'type': 'chunk', 'section': 'comparison', 'content': _comparison};
      yield {'type': 'section', 'section': 'blueprint'};
      yield {'type': 'chunk', 'section': 'blueprint', 'content': _blueprint};
      yield {
        'type': 'comparison_scores',
        'ready': false,
        'status': 'retry_wait',
      };
      yield {'type': 'done', 'phase': 'completed'};
    });
    final plans = _Plans()
      ..status = 'completed'
      ..progress = 100;
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_icon('dim', 'done'), findsOneWidget);
    expect(find.text('Go to Today'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed plan job marks the plan stage and keeps earlier ones', (
    tester,
  ) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()..status = 'failed';
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_icon('cmp', 'done'), findsOneWidget);
    expect(_icon('dim', 'done'), findsOneWidget);
    expect(_icon('bp', 'done'), findsOneWidget);
    expect(_icon('plan', 'fail'), findsOneWidget);
    expect(_icon('t1', 'wait'), findsOneWidget);
    expect(
      find.text('The plan backbone didn’t finish. Earlier steps are saved.'),
      findsOneWidget,
    );
    expect(find.text('One step'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Go to Today'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a server error names its own section', (tester) async {
    final sessions = _Sessions((_) async* {
      yield {'type': 'plan_job', 'job_id': 'job-1'};
      yield {'type': 'section', 'section': 'comparison'};
      yield {'type': 'chunk', 'section': 'comparison', 'content': _comparison};
      yield {'type': 'section', 'section': 'blueprint'};
      yield {'type': 'error', 'section': 'plan', 'message': 'PRIVATE'};
    });
    await _mount(tester, sessions: sessions, plans: _Plans());
    await tester.pump(const Duration(milliseconds: 300));
    expect(_icon('plan', 'fail'), findsOneWidget);
    expect(_icon('cmp', 'done'), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the done footer routes to Today or to the plan', (tester) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..progress = 100;
    var today = 0;
    var plan = 0;
    await _mount(
      tester,
      sessions: sessions,
      plans: plans,
      onDone: () => today++,
      onPlan: () => plan++,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Go to Today'), findsOneWidget);
    expect(find.text('See the full plan'), findsOneWidget);
    expect(
      find.text('Tutorials keep preparing in the background'),
      findsOneWidget,
    );
    await tester.tap(find.text('See the full plan'));
    await tester.pump();
    expect((today, plan), (0, 1));
    await tester.tap(find.text('Go to Today'));
    await tester.pump();
    expect((today, plan), (1, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without a plan route, See the full plan enters like Today', (
    tester,
  ) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..progress = 100;
    var entered = 0;
    await _mount(
      tester,
      sessions: sessions,
      plans: plans,
      onDone: () => entered++,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('See the full plan'));
    await tester.pump();
    expect(entered, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the footer names the remaining tutorials when the plan knows', (
    tester,
  ) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..progress = 100
      ..totalLessons = 8
      ..readyLessons = 1;
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Tutorials 2–8 keep preparing in the background'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a plan that completes before its first tutorial keeps '
      'tutorial 1 preparing', (tester) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..step = 'done'
      ..progress = 100
      ..totalLessons = 8;
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));

    // The plan exists, so the learner can go in; tutorial 1 is not ready.
    expect(_icon('plan', 'done'), findsOneWidget);
    expect(_icon('t1', 'run'), findsOneWidget);
    expect(find.text('Preparing — it’ll open on Today'), findsOneWidget);
    expect(find.text('Ready to start while the rest prepares'), findsNothing);
    // The headline does not claim the tutorial is ready …
    expect(find.text('to begin.'), findsNothing);
    expect(find.text('Your plan is ready.'), findsOneWidget);
    expect(find.text('Tutorial 1 is on its way.'), findsOneWidget);
    // … nor does the footer (tutorial 1 is among those still preparing).
    expect(
      find.text('Tutorials keep preparing in the background'),
      findsOneWidget,
    );
    expect(find.textContaining('Tutorials 2–8'), findsNothing);
    // Today is still the way in.
    expect(find.text('Go to Today'), findsOneWidget);
    expect(find.text('See the full plan'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a completed plan with a ready first tutorial ticks it', (
    tester,
  ) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..step = 'done'
      ..progress = 100
      ..readyLessons = 1;
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_icon('t1', 'done'), findsOneWidget);
    expect(find.text('Ready to start while the rest prepares'), findsOneWidget);
    expect(find.text('Your plan is ready'), findsOneWidget);
    expect(find.text('to begin.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('mission 1 peek after the plan completes (owner decision 5)', () {
    _Plans completedPlans() => _Plans()
      ..status = 'completed'
      ..step = 'done'
      ..progress = 100
      ..totalLessons = 8
      ..plan = _planWithMission();

    testWidgets('a ready first tutorial ticks Tutorial 1 and shows the full '
        'headline', (tester) async {
      final plans = completedPlans()
        ..peekDetail = _missionDetail(firstReady: true);
      await _mount(
        tester,
        sessions: _Sessions((_) => _fullRun()),
        plans: plans,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(plans.peekedIds, ['m1']);
      expect(plans.normalReads, 0);
      expect(_icon('t1', 'done'), findsOneWidget);
      expect(find.text('Your plan is ready'), findsOneWidget);
      expect(find.text('to begin.'), findsOneWidget);
      expect(find.text('Tutorial 1 is on its way.'), findsNothing);
      expect(
        find.text('Ready to start while the rest prepares'),
        findsOneWidget,
      );
      expect(find.text('Preparing — it’ll open on Today'), findsNothing);
      expect(
        find.text('Tutorials 2–8 keep preparing in the background'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a first tutorial still being written keeps the copy, and is '
        'checked once', (tester) async {
      final plans = completedPlans()
        ..peekDetail = _missionDetail(firstReady: false);
      await _mount(
        tester,
        sessions: _Sessions((_) => _fullRun()),
        plans: plans,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 10));

      expect(plans.peekedIds, ['m1']);
      expect(plans.normalReads, 0);
      expect(_icon('t1', 'run'), findsOneWidget);
      expect(find.text('Your plan is ready.'), findsOneWidget);
      expect(find.text('Tutorial 1 is on its way.'), findsOneWidget);
      expect(find.text('Preparing — it’ll open on Today'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed peek keeps the copy', (tester) async {
      final plans = completedPlans()..peekError = StateError('offline');
      await _mount(
        tester,
        sessions: _Sessions((_) => _fullRun()),
        plans: plans,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(plans.peekedIds, ['m1']);
      expect(find.text('Tutorial 1 is on its way.'), findsOneWidget);
      expect(find.text('Preparing — it’ll open on Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a server that cannot peek is never read', (tester) async {
      final plans = completedPlans()
        ..plan = _planWithMission(supportsPeek: false)
        ..peekDetail = _missionDetail(firstReady: true);
      await _mount(
        tester,
        sessions: _Sessions((_) => _fullRun()),
        plans: plans,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(plans.peekedIds, isEmpty);
      expect(plans.normalReads, 0);
      expect(find.text('Tutorial 1 is on its way.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tutorial the job already reports ready needs no peek', (
      tester,
    ) async {
      final plans = completedPlans()
        ..readyLessons = 1
        ..peekDetail = _missionDetail(firstReady: false);
      await _mount(
        tester,
        sessions: _Sessions((_) => _fullRun()),
        plans: plans,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(plans.peekedIds, isEmpty);
      expect(_icon('t1', 'done'), findsOneWidget);
      expect(find.text('to begin.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a job that completes after a dropped stream stops polling', (
    tester,
  ) async {
    final sessions = _Sessions((_) async* {
      yield {'type': 'plan_job', 'job_id': 'job-1'};
      yield {'type': 'section', 'section': 'comparison'};
      yield {'type': 'chunk', 'section': 'comparison', 'content': _comparison};
      throw const NetworkError();
    });
    final plans = _Plans()
      ..status = 'completed'
      ..step = 'done'
      ..progress = 100;
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    // The results connection dropped: the learner retries from here.
    expect(find.text('Retry'), findsOneWidget);
    final polls = plans.polls;
    expect(polls, greaterThanOrEqualTo(1));

    // The job is done: nothing polls it again while the lab waits.
    await tester.pump(const Duration(seconds: 12));
    expect(plans.polls, polls);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a plan that could not start leaves the saved comparison done', (
    tester,
  ) async {
    // The server saves the comparison, then fails to dispatch the plan
    // before the blueprint section starts.
    final sessions = _Sessions((_) async* {
      yield {'type': 'plan_job', 'job_id': 'job-1'};
      yield {'type': 'section', 'section': 'comparison'};
      yield {'type': 'chunk', 'section': 'comparison', 'content': _comparison};
      yield {
        'type': 'error',
        'section': 'plan',
        'message': 'Plan generation could not start. Please try again.',
        'retryable': true,
      };
    });
    await _mount(tester, sessions: sessions, plans: _Plans());
    await tester.pump(const Duration(milliseconds: 300));
    expect(_icon('cmp', 'done'), findsOneWidget);
    expect(_icon('cmp', 'wait'), findsNothing);
    expect(_icon('plan', 'fail'), findsOneWidget);
    expect(
      find.text('The plan backbone didn’t finish. Earlier steps are saved.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the done footer sits on an opaque ground', (tester) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..progress = 100
      ..readyLessons = 1;
    await _mount(tester, sessions: sessions, plans: plans);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final ground = find.byKey(const Key('lab-footer-ground'));
    expect(ground, findsOneWidget);
    expect(tester.widget<ColoredBox>(ground).color, AppColors.night);
    expect(AppColors.night.a, 1);
    final groundRect = tester.getRect(ground);
    // The status line and both buttons stand on it, so the comparison card
    // never shows through them.
    for (final finder in [
      find.text('Tutorials keep preparing in the background'),
      find.byKey(const Key('mentor-lab-today')),
      find.byKey(const Key('mentor-lab-plan')),
    ]) {
      final rect = tester.getRect(finder);
      expect(groundRect.top, lessThanOrEqualTo(rect.top));
      expect(groundRect.bottom, greaterThanOrEqualTo(rect.bottom));
    }
    // At rest, scrolled to the end, the last card ends above the ground.
    await tester.drag(
      find.byKey(const Key('mentor-lab-content')),
      const Offset(0, -2000),
    );
    await tester.pump();
    final roadmap = find.byKey(const Key('lab-preview-roadmap'));
    expect(
      tester.getRect(roadmap).bottom,
      lessThanOrEqualTo(groundRect.top),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the plan stage shows the capacity the plan reports', (
    tester,
  ) async {
    final events = StreamController<Map<String, dynamic>>();
    final plans = _Plans();
    final draft = CmpysOnboardingDraft()
      ..sessionId = 'session-1'
      ..intakeAnswers['weekly_hours'] = '4,5 hours a week';
    await _mount(
      tester,
      sessions: _Sessions((_) => events.stream),
      plans: plans,
      draft: draft,
    );
    await tester.pump();
    // Before the plan exists: what the learner answered on this device.
    expect(find.text('12 weeks · 4.5 h per week'), findsOneWidget);

    events.add({'type': 'plan_job', 'job_id': 'job-1'});
    await tester.pump(const Duration(milliseconds: 100));
    plans
      ..step = 'preparing_current_week'
      ..progress = 95
      ..plan = BackendPlan(
        id: 'plan-1',
        durationWeeks: 12,
        weeklyHours: 3,
        weeklyMinutes: 150,
        items: const [],
      );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    // Once the plan exists, its own weekly capacity wins.
    expect(find.text('12 weeks · 2.5 h per week'), findsOneWidget);

    events.add({'type': 'done'});
    unawaited(events.close());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the plan stage subtitle is just the length when capacity is unknown',
    (tester) async {
      final events = StreamController<Map<String, dynamic>>();
      await _mount(
        tester,
        sessions: _Sessions((_) => events.stream),
        plans: _Plans(),
      );
      await tester.pump();
      expect(find.text('12 weeks'), findsOneWidget);
      events.add({'type': 'done'});
      unawaited(events.close());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('animated lab runs and settles into the done footer', (
    tester,
  ) async {
    final sessions = _Sessions((_) => _fullRun());
    final plans = _Plans()
      ..status = 'completed'
      ..progress = 100;
    await _mount(
      tester,
      sessions: sessions,
      plans: plans,
      reducedMotion: false,
    );
    // Halo rings, orbit and spinners run: step frames, never settle.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Go to Today'), findsOneWidget);
    // The footer springs up from below the screen to rest on its bottom edge.
    final bottom = tester.getBottomLeft(
      find.byKey(const Key('lab-done-footer')),
    );
    expect(bottom.dy, lessThanOrEqualTo(844.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  group('text extraction', () {
    test(
      'labExcerpt keeps the first three finished sentences of the prose',
      () {
        expect(
          labExcerpt(_comparison, complete: true),
          'At 24, Buffett had read every investing book he could find. You '
          'have curiosity and a few trades. The gap that matters most is '
          'evidence.',
        );
      },
    );

    test('labExcerpt drops headings, list markers and emphasis', () {
      expect(
        labExcerpt(
          '## Where you stand\n\n**At 24**, he had a _plan_. You have '
          '[none](https://x.y).\n\n- First point here. Second point.',
          complete: true,
        ),
        'At 24, he had a plan. You have none. First point here.',
      );
    });

    test('labExcerpt only counts finished sentences while streaming', () {
      expect(labExcerpt('You have curiosity', complete: false), '');
      expect(
        labExcerpt('You have curiosity. And a few', complete: false),
        'You have curiosity.',
      );
      // A decimal is not a sentence end, and neither is an abbreviation.
      expect(labExcerpt('You read 4.5', complete: false), '');
      expect(
        labExcerpt('Mr. Market is moody. Next one', complete: false),
        'Mr. Market is moody.',
      );
      // A trailing line break finishes the last sentence.
      expect(labExcerpt('Only one.\n', complete: false), 'Only one.');
      expect(labExcerpt('Only one.', complete: false), '');
      expect(labExcerpt('Only one.', complete: true), 'Only one.');
    });

    test('labExcerpt shows a complete text with no sentence end whole', () {
      expect(
        labExcerpt('No full stop here', complete: true),
        'No full stop here',
      );
      expect(labExcerpt(null, complete: true), '');
      expect(labExcerpt('   ', complete: true), '');
    });

    test('labExcerpt never grows past about 420 characters', () {
      final long = '${'word ' * 120}. Another sentence.';
      final excerpt = labExcerpt(long, complete: true);
      expect(excerpt.length, lessThanOrEqualTo(421));
      expect(excerpt, endsWith('…'));
    });

    test('labDirection takes the first sentence of the thesis section', () {
      expect(
        labDirection(_blueprint, complete: false),
        'Learn to read a business like an owner before you price it like a '
        'trader.',
      );
      expect(labDirection(_blueprint, complete: true), isNotNull);
    });

    test('labDirection waits for the thesis while the blueprint streams', () {
      expect(
        labDirection(
          '## Strategic Verdict\nYou lack evidence.',
          complete: false,
        ),
        isNull,
      );
      expect(
        labDirection('## Twelve-Week Thesis\nLearn to read', complete: false),
        isNull,
      );
      expect(
        labDirection(
          '## Twelve-Week Thesis\nLearn to read.\n',
          complete: false,
        ),
        'Learn to read.',
      );
    });

    test('labDirection falls back to the first sentence, then a heading', () {
      expect(
        labDirection(
          '## Verdict\nStart with evidence. Then price.',
          complete: true,
        ),
        'Start with evidence.',
      );
      expect(
        labDirection('## Only A Heading', complete: true),
        'Only A Heading',
      );
      expect(labDirection('', complete: true), isNull);
      expect(labDirection(null, complete: true), isNull);
    });

    test('labHours shows half hours without a trailing zero', () {
      expect(labHours(60), '1');
      expect(labHours(90), '1.5');
      expect(labHours(240), '4');
      expect(labHours(270), '4.5');
      expect(labHours(900), '15');
    });
  });
}
