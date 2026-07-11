import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlanRepository extends PlanRepository {
  _FakePlanRepository() : super(dioClient: DioClient(tokenStore: TokenStore()));

  @override
  Future<({bool completed, bool itemCompleted})> toggleStepComplete(
    String itemId,
    String stepId,
  ) async => (completed: true, itemCompleted: false);
}

class _FocusedPlanRepository extends Fake implements PlanRepository {
  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async =>
      const PlanItemDetailed(
        item: _item,
        detailsStatus: 'available',
        steps: _steps,
        completedStepIds: {'s1'},
        completedSteps: 1,
        totalSteps: 3,
      );
}

const _item = BackendPlanItem(
  id: 'mission-1',
  title: 'Foundation & Research',
  type: 'project',
  description: 'Build a sound foundation.',
  weekStart: 1,
  weekEnd: 1,
  successMetric: 'A documented foundation exists.',
  estimatedHours: 5,
  status: 'in_progress',
  progressPercent: 33,
);

const _steps = [
  PlanStepDetail(id: 's1', title: 'Define the purpose'),
  PlanStepDetail(id: 's2', title: 'Map the evidence'),
  PlanStepDetail(id: 's3', title: 'Write the synthesis'),
];

void main() {
  test('lesson progression exposes only the next incomplete lesson', () {
    const detailed = PlanItemDetailed(
      item: _item,
      detailsStatus: 'available',
      steps: _steps,
      completedStepIds: {'s1'},
      completedSteps: 1,
      totalSteps: 3,
    );

    expect(detailed.activeStepIndex, 1);
    expect(detailed.isStepCompleted('s1'), isTrue);
    expect(detailed.isStepUnlocked(0), isTrue);
    expect(detailed.isStepUnlocked(1), isTrue);
    expect(detailed.isStepUnlocked(2), isFalse);
  });

  test('lesson markdown is split into reader-sized sections', () {
    final sections = splitLessonSections('''
# Define the purpose

## Why This Matters
Purpose creates a useful decision boundary.

## Core Framework
Separate the desired change from the activity.

## Guided Practice
Set a timer and write the decision boundary.
''');

    expect(sections.map((section) => section.title), [
      'Why This Matters',
      'Core Framework',
      'Guided Practice',
    ]);
  });

  testWidgets('dedicated reader has contents, settings, and book references', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const step = PlanStepDetail(
      id: 's1',
      title: 'Define the purpose',
      readingMinutes: 8,
      practiceMinutes: 37,
      estimateMinutes: 45,
      resources: ['Start With Why'],
      lessonContent: '''
# Define the purpose

## Why This Matters
Purpose creates a useful decision boundary and keeps the work focused.

## Core Framework
Separate the desired change from the activity used to create that change.

## Guided Practice
Set a timer, write the decision boundary, then test it against two choices.
''',
    );
    const materials = [
      PlanMaterialDetail(
        title: 'Start With Why',
        type: 'book',
        authorOrCreator: 'Simon Sinek',
        contentResourceId: 'book-1',
      ),
      PlanMaterialDetail(
        title: 'Unrelated article',
        type: 'article',
        url: 'https://example.com',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(_FakePlanRepository()),
        ],
        child: const MaterialApp(
          home: LessonReaderScreen(
            itemId: 'mission-1',
            missionTitle: 'Foundation & Research',
            step: step,
            stepNumber: 1,
            totalSteps: 3,
            materials: materials,
            completed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LESSON 1 · PART 1 OF 3'), findsOneWidget);
    expect(find.text('8 min read'), findsOneWidget);
    expect(find.text('37 min practice'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.format_size_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);
    Navigator.of(tester.element(find.text('Reading settings'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Lesson contents'), findsOneWidget);
    expect(find.text('Core Framework'), findsOneWidget);
    expect(find.text('References'), findsOneWidget);
    await tester.tap(find.text('References'));
    await tester.pumpAndSettle();

    expect(find.text('Start With Why'), findsOneWidget);
    expect(find.text('Read book'), findsOneWidget);
    expect(find.text('Unrelated article'), findsNothing);
    expect(find.text('Complete lesson'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mission page highlights one current lesson and locks the rest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(_FocusedPlanRepository()),
        ],
        child: const MaterialApp(
          home: PlanItemDetailScreen(itemId: 'mission-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FOCUSED LESSONS'), findsOneWidget);
    expect(find.byKey(const Key('lesson-1-completed')), findsOneWidget);
    expect(find.byKey(const Key('lesson-2-active')), findsOneWidget);
    expect(find.byKey(const Key('lesson-3-locked')), findsOneWidget);
    expect(find.text('CURRENT LESSON'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('lesson-3-locked')),
      180,
    );
    await tester.tap(find.byKey(const Key('lesson-3-locked')));
    await tester.pumpAndSettle();

    expect(find.text('Lesson 3 is locked'), findsOneWidget);
    expect(find.textContaining('Complete Lesson 2 first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
