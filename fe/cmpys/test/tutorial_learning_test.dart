import 'package:cmpys/core/ui/cmpys/learning_diagram_view.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _tutorialMarkdown = '''
# Explain a claim

## One clear idea
A claim connects what you observe to what you can explain.

## See it
```diagram
[Observe]
    │
    ▼
[Explain]
    │
    ▼
[Test]
```

## Worked example
The plant grew toward the window. The light is a possible explanation.
Moving the plant gives us a way to test the explanation.

## Try it
Write one observation, one explanation, and a test of your own.
''';

PlanItemDetailed _tutorials({
  int ready = 1,
  Set<String> completed = const {},
}) => PlanItemDetailed.fromJson({
  'item': {'id': 'mission-1', 'title': 'Explain with evidence'},
  'details_status': 'partial',
  'job_id': 'job-1',
  'artifact_job_id': 'artifact-1',
  'details_progress': 70,
  'details_step': 'lessons_ready',
  'completed_step_ids': completed.toList(),
  'progress': {'completed_steps': completed.length, 'total_steps': 12},
  'details': {
    'lesson_format': 'tutorial_v1',
    'steps': List.generate(
      12,
      (index) => {
        'id': 'step_${index + 1}',
        'title': 'Explain concept ${index + 1}',
        'estimate_minutes': 7,
        'reading_minutes': 4,
        'practice_minutes': 3,
        if (index < ready) 'lesson_content': _tutorialMarkdown,
      },
    ),
  },
});

class _TutorialRepository extends Fake implements PlanRepository {
  _TutorialRepository(this.details, {this.jobs = const []});
  final List<PlanItemDetailed> details;
  final List<PlanJobStatus> jobs;
  int detailCalls = 0;
  int jobCalls = 0;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async =>
      details[(detailCalls++).clamp(0, details.length - 1)];

  @override
  Future<PlanJobStatus> getPlanDetailJobStatus(String jobId) async =>
      jobs[(jobCalls++).clamp(0, jobs.length - 1)];
}

Widget _app(PlanRepository repository) => ProviderScope(
  overrides: [planRepositoryProvider.overrideWithValue(repository)],
  child: const MaterialApp(home: PlanItemDetailScreen(itemId: 'mission-1')),
);

void main() {
  test(
    'tutorial metadata inherits from the outline and preserves 12 steps',
    () {
      final details = _tutorials(completed: {'step_1'});
      expect(details.isTutorialSequence, isTrue);
      expect(details.steps.length, 12);
      expect(details.steps.every((step) => step.isTutorial), isTrue);
      expect(details.readyLessonCount, 1);
      expect(details.activeStepIndex, 1);
      expect(details.isStepUnlocked(0), isTrue);
      expect(details.isStepUnlocked(1), isTrue);
      expect(details.isStepUnlocked(2), isFalse);
      expect(details.isStepUnlocked(11), isFalse);
      expect(details.steps.first.totalMinutes, 7);
      expect(details.steps.first.effectiveReadingMinutes, 4);
      expect(details.steps.first.effectivePracticeMinutes, 3);
      expect(details.artifactJobId, 'artifact-1');
    },
  );

  test('legacy lessons are unchanged and missing timing is not invented', () {
    final step = PlanStepDetail.fromJson({
      'id': 'step_1',
      'title': 'A legacy lesson',
      'readingMinutes': 12,
      'practiceMinutes': 30,
    });
    expect(step.isTutorial, isFalse);
    expect(step.readingMinutes, 12);
    expect(step.practiceMinutes, 30);
    final pending = PlanStepDetail.fromJson({'id': 'step_2', 'title': 'Next'});
    expect(pending.effectiveReadingMinutes, isNull);
    expect(pending.effectivePracticeMinutes, isNull);
    expect(pending.totalMinutes, isNull);
    expect(
      PlanItemDetailed.fromJson({
        'item': {'id': 'old'},
        'details': {
          'steps': [
            {'id': 'old-step', 'title': 'Legacy'},
          ],
        },
      }).isTutorialSequence,
      isFalse,
    );
  });

  test(
    'seven short backend sections form four tutorial pages without loss',
    () {
      const headings = [
        'Why This Matters',
        'Core Framework',
        'Worked Example',
        'Failure Modes',
        'Guided Practice',
        'Check Your Understanding',
        'References',
      ];
      final markdown = [
        for (var i = 0; i < headings.length; i++)
          '## ${headings[i]}\nUnique teaching content $i.',
      ].join('\n\n');
      final compact = splitLessonSections(markdown, compactTutorial: true);
      expect(compact.map((section) => section.title), [
        'The idea',
        'Worked example',
        'Try it',
        'Check your understanding',
      ]);
      final body = compact.map((section) => section.markdown).join('\n');
      for (var i = 0; i < headings.length; i++) {
        expect(body, contains('### ${headings[i]}'));
        expect(body, contains('Unique teaching content $i.'));
      }
      expect(splitLessonSections(markdown).length, 7);
      expect(
        splitLessonSections(_tutorialMarkdown, compactTutorial: true).length,
        4,
      );
    },
  );

  test('job ready count is read independently of rounded progress', () {
    final job = PlanJobStatus.fromJson({
      'id': 'job-1',
      'status': 'running',
      'progressPercent': 70,
      'results': {'ready_lesson_count': 3},
    });
    expect(job.readyLessonCount, 3);
    expect(PlanJobStatus.fromJson({'id': 'old-job'}).readyLessonCount, isNull);
  });

  testWidgets('the first tutorial opens while the rest are still preparing', (
    tester,
  ) async {
    final repo = _TutorialRepository([_tutorials()]);
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('1 of 12 tutorials ready.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CURRENT TUTORIAL'), 250);
    expect(find.text('SHORT TUTORIALS'), findsOneWidget);
    expect(find.text('7 min total'), findsWidgets);
    expect(find.text('4 min read'), findsWidgets);
    expect(find.text('3 min practice'), findsWidgets);
    await tester.tap(find.text('Explain concept 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TUTORIAL 1 · PART 1 OF 4'), findsOneWidget);
    expect(find.textContaining('Tutorial 1 of 12'), findsOneWidget);
    expect(find.text('Practice in app'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('later ready tutorials refresh at the same job percentage', (
    tester,
  ) async {
    final repo = _TutorialRepository(
      [
        _tutorials(completed: {'step_1'}),
        _tutorials(ready: 2, completed: {'step_1'}),
      ],
      jobs: [
        PlanJobStatus.fromJson({
          'id': 'job-1',
          'status': 'running',
          'step': 'generating_lessons',
          'progressPercent': 70,
          'results': {'ready_lesson_count': 2},
        }),
      ],
    );
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('Preparing your next tutorial.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(repo.detailCalls, 2);
    expect(find.textContaining('2 of 12 tutorials ready.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CURRENT TUTORIAL'), 250);
    expect(find.text('Explain concept 2'), findsOneWidget);
    expect(find.text('PREPARING'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new tutorial content renews the bounded idle polling window', (
    tester,
  ) async {
    final repo = _TutorialRepository(
      [_tutorials(), _tutorials(ready: 2)],
      jobs: [
        for (var index = 0; index < 35; index++)
          const PlanJobStatus(
            id: 'job-1',
            status: 'running',
            step: 'generating_lessons',
            progressPercent: 70,
            readyLessonCount: 1,
          ),
        const PlanJobStatus(
          id: 'job-1',
          status: 'running',
          step: 'generating_lessons',
          progressPercent: 70,
          readyLessonCount: 2,
        ),
      ],
    );
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();
    for (var index = 0; index < 56; index++) {
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      await tester.pump();
    }
    expect(repo.detailCalls, 2);
    expect(repo.jobCalls, greaterThan(52));
    expect(find.text('Check status'), findsOneWidget);
    expect(find.textContaining('2 of 12 tutorials ready.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('four tutorial sections render the visual and worked example', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LessonReaderScreen(
            itemId: 'mission-1',
            missionTitle: 'Explain with evidence',
            step: _tutorials().steps.first,
            stepNumber: 1,
            totalSteps: 12,
            materials: const [],
            completed: true,
            artifactJobId: 'artifact-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7 min total'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningDiagramView), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Worked example'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Try it'), findsOneWidget);
    expect(find.text('Close tutorial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
