import 'package:cmpys/features/cmpys/state/plan_data.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/first_tutorial_auto_open.dart';
import 'package:flutter_test/flutter_test.dart';

// One-ahead generation: the backend writes the current tutorial and the next
// one, never more. The app shows a step as "preparing" only while a job is
// writing it inside that window; every other unwritten step is upcoming
// (locked).

Map<String, Object?> _json({
  required int steps,
  required int ready,
  Set<String> completed = const {},
  String status = 'partial',
  String? jobId = 'job-1',
  String? step = 'generating_lessons',
  String? error,
  Map<String, Object?>? window,
}) => {
  'item': {'id': 'mission-1', 'title': 'Explain with evidence'},
  'details_status': status,
  'job_id': ?jobId,
  'details_step': ?step,
  'details_error': ?error,
  'completed_step_ids': completed.toList(),
  'generation_window': ?window,
  'details': {
    'lesson_format': 'tutorial_v1',
    'steps': [
      for (var i = 0; i < steps; i++)
        {
          'id': 's${i + 1}',
          'title': 'Tutorial title ${i + 1}',
          if (i < ready) 'lesson_content': '# Tutorial ${i + 1}',
        },
    ],
  },
};

PlanItemDetailed _detail({
  required int steps,
  required int ready,
  Set<String> completed = const {},
  String status = 'partial',
  String? jobId = 'job-1',
  String? step = 'generating_lessons',
  String? error,
  Map<String, Object?>? window,
}) => PlanItemDetailed.fromJson(
  _json(
    steps: steps,
    ready: ready,
    completed: completed,
    status: status,
    jobId: jobId,
    step: step,
    error: error,
    window: window,
  ),
);

/// The parked shape: both window tutorials are written, nothing runs.
PlanItemDetailed _parked({Set<String> completed = const {}, int ready = 2}) =>
    _detail(
      steps: 5,
      ready: ready,
      completed: completed,
      jobId: null,
      step: 'waiting_for_learner',
      window: {
        'current_step_id': 's${completed.length + 1}',
        'next_step_id': 's${completed.length + 2}',
        'waiting_for_learner': true,
      },
    );

void main() {
  group('generation_window parsing', () {
    test('reads the window when the backend sends it', () {
      final detail = _parked();
      final window = detail.generationWindow!;
      expect(window.currentStepId, 's1');
      expect(window.nextStepId, 's2');
      expect(window.waitingForLearner, isTrue);
      expect(detail.windowCurrentIndex, 0);
      expect(detail.windowNextIndex, 1);
      expect(detail.generationParked, isTrue);
      // Parked is neither loading nor failed.
      expect(detail.detailsLoading, isFalse);
      expect(detail.detailsFailed, isFalse);
    });

    test('a null next step means the window is at the end', () {
      final detail = _detail(
        steps: 2,
        ready: 2,
        completed: const {'s1'},
        window: {
          'current_step_id': 's2',
          'next_step_id': null,
          'waiting_for_learner': false,
        },
      );
      expect(detail.windowCurrentIndex, 1);
      expect(detail.windowNextIndex, isNull);
    });

    test('an older backend without the window falls back to the next '
        'uncompleted step and the one after it', () {
      final detail = _detail(steps: 4, ready: 1, completed: const {'s1'});
      expect(detail.generationWindow, isNull);
      expect(detail.windowCurrentIndex, 1);
      expect(detail.windowNextIndex, 2);
      expect(detail.generationParked, isFalse);
      // At the last step there is no next one.
      final last = _detail(
        steps: 2,
        ready: 2,
        completed: const {'s1'},
        jobId: null,
        status: 'available',
      );
      expect(last.windowNextIndex, isNull);
    });

    test('a malformed window is ignored', () {
      final detail = PlanItemDetailed.fromJson({
        ..._json(steps: 3, ready: 1),
        'generation_window': 'nope',
      });
      expect(detail.generationWindow, isNull);
      expect(detail.windowNextIndex, 1);
    });

    test('details_step "waiting_for_learner" with no job parks without '
        'the window', () {
      final detail = _detail(
        steps: 4,
        ready: 2,
        jobId: null,
        step: 'waiting_for_learner',
      );
      expect(detail.generationParked, isTrue);
      expect(detail.detailsLoading, isFalse);
      expect(detail.detailsFailed, isFalse);
    });
  });

  group('one-ahead row states', () {
    test('a fresh mission: tutorial 1 preparing, the rest upcoming', () {
      final detail = _detail(steps: 4, ready: 0, status: 'generating');
      expect(tutorialRowStates(detail), [
        TutorialRowState.preparing,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('tutorial 1 ready and 2 being written: 3 onwards upcoming', () {
      final detail = _detail(
        steps: 5,
        ready: 1,
        window: {
          'current_step_id': 's1',
          'next_step_id': 's2',
          'waiting_for_learner': false,
        },
      );
      expect(tutorialRowStates(detail), [
        TutorialRowState.current,
        TutorialRowState.preparing,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('the same without the window (older backend)', () {
      final detail = _detail(steps: 5, ready: 1);
      expect(tutorialRowStates(detail), [
        TutorialRowState.current,
        TutorialRowState.preparing,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('parked: nothing is preparing, later tutorials are upcoming', () {
      expect(tutorialRowStates(_parked()), [
        TutorialRowState.current,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
      expect(tutorialRowStates(_parked(completed: {'s1'}, ready: 3)), [
        TutorialRowState.done,
        TutorialRowState.current,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('no job running: an unwritten step is upcoming, not preparing', () {
      final detail = _detail(
        steps: 3,
        ready: 1,
        jobId: null,
        step: 'lessons_ready',
      );
      expect(detail.detailsLoading, isFalse);
      expect(tutorialRowStates(detail), [
        TutorialRowState.current,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('a failure in the window stops the tutorial the learner is on', () {
      final detail = _detail(
        steps: 4,
        ready: 1,
        completed: const {'s1'},
        jobId: null,
        error: 'This tutorial could not be prepared.',
      );
      expect(detail.detailsFailed, isTrue);
      expect(tutorialRowStates(detail), [
        TutorialRowState.done,
        TutorialRowState.stopped,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('a failure of the next tutorial stays quiet until it is reached', () {
      final detail = _detail(
        steps: 4,
        ready: 1,
        jobId: null,
        error: 'This tutorial could not be prepared.',
      );
      expect(tutorialRowStates(detail), [
        TutorialRowState.current,
        TutorialRowState.locked,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });
  });

  group('a stalled window is a failure, not quiet', () {
    test('the window is authoritative over details_step', () {
      // The re-queue failed: details_step still says waiting, the window
      // does not, and the learner's tutorial is missing.
      final detail = _detail(
        steps: 4,
        ready: 1,
        completed: const {'s1'},
        jobId: null,
        step: 'waiting_for_learner',
        window: {
          'current_step_id': 's2',
          'next_step_id': 's3',
          'waiting_for_learner': false,
        },
      );
      expect(detail.generationParked, isFalse);
      expect(detail.detailsLoading, isFalse);
      expect(detail.detailsFailed, isTrue);
      expect(tutorialRowStates(detail), [
        TutorialRowState.done,
        TutorialRowState.stopped,
        TutorialRowState.locked,
        TutorialRowState.locked,
      ]);
    });

    test('the window saying waiting parks even with another details_step', () {
      final detail = _detail(
        steps: 4,
        ready: 2,
        jobId: null,
        step: 'lessons_ready',
        window: {
          'current_step_id': 's1',
          'next_step_id': 's2',
          'waiting_for_learner': true,
        },
      );
      expect(detail.generationParked, isTrue);
      expect(detail.detailsFailed, isFalse);
    });

    test('a missing current tutorial with no job and not parked is stopped '
        '(no window, no error)', () {
      final detail = _detail(
        steps: 3,
        ready: 1,
        completed: const {'s1'},
        jobId: null,
        step: 'lessons_ready',
      );
      expect(detail.detailsFailed, isTrue);
      expect(tutorialRowStates(detail), [
        TutorialRowState.done,
        TutorialRowState.stopped,
        TutorialRowState.locked,
      ]);
    });

    test('the same with the backend error shape', () {
      final detail = _detail(
        steps: 3,
        ready: 1,
        completed: const {'s1'},
        jobId: null,
        error: 'This tutorial could not be prepared.',
        window: {
          'current_step_id': 's2',
          'next_step_id': 's3',
          'waiting_for_learner': false,
        },
      );
      expect(detail.detailsFailed, isTrue);
      expect(tutorialRowStates(detail)[1], TutorialRowState.stopped);
    });

    test('a job still running is loading, not stalled', () {
      final detail = _detail(steps: 3, ready: 1, completed: const {'s1'});
      expect(detail.detailsLoading, isTrue);
      expect(detail.detailsFailed, isFalse);
      expect(tutorialRowStates(detail)[1], TutorialRowState.preparing);
    });
  });

  group('first tutorial readiness', () {
    test('preparing and readable', () {
      final fresh = _detail(steps: 3, ready: 0, status: 'generating');
      expect(fresh.firstTutorialPreparing, isTrue);
      expect(fresh.firstTutorialReadable, isFalse);
      final ready = _detail(steps: 3, ready: 1);
      expect(ready.firstTutorialPreparing, isFalse);
      expect(ready.firstTutorialReadable, isTrue);
      // Started already: tutorial 1 is no longer the one to open.
      final started = _detail(steps: 3, ready: 2, completed: const {'s1'});
      expect(started.firstTutorialReadable, isFalse);
      // No outline yet still counts as preparing tutorial 1.
      final outline = PlanItemDetailed.fromJson({
        'item': {'id': 'mission-1', 'title': 'M'},
        'details_status': 'pending',
        'job_id': 'job-1',
      });
      expect(outline.firstTutorialPreparing, isTrue);
      // A failure is not "preparing".
      final failed = _detail(steps: 3, ready: 0, status: 'failed', jobId: null);
      expect(failed.firstTutorialPreparing, isFalse);
    });
  });

  group('auto-open registry', () {
    setUp(FirstTutorialAutoOpen.resetForTest);

    test('claims each mission once per session', () {
      expect(FirstTutorialAutoOpen.claim('m1'), isTrue);
      expect(FirstTutorialAutoOpen.claim('m1'), isFalse);
      expect(FirstTutorialAutoOpen.claim('m2'), isTrue);
    });

    test('a manual open blocks the automatic one', () {
      FirstTutorialAutoOpen.markOpened('m1');
      expect(FirstTutorialAutoOpen.claim('m1'), isFalse);
    });
  });
}
