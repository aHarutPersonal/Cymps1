import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/reading/lesson_fences.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/material_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/material_web_screen.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_web_platforms.dart';

class _FakePlanRepository extends PlanRepository {
  _FakePlanRepository() : super(dioClient: DioClient(tokenStore: TokenStore()));

  @override
  Future<({bool completed, bool itemCompleted})> toggleStepComplete(
    String itemId,
    String stepId, {
    String? artifactJobId,
    bool? complete,
  }) async => (completed: true, itemCompleted: false);
}

/// A book with no guide whose reading source is an author excerpt.
class _ExcerptPlanRepository extends _FakePlanRepository {
  @override
  Future<BookReadingAccess> resolveBookReadingAccess(
    String canonicalKey,
    String title,
    String? author,
  ) async => const BookReadingAccess(
    source: BookReadingSource(
      url: 'https://example.org/personal-mba-excerpt',
      scope: 'excerpt',
      description: 'Chapter 1 excerpt on the author’s website.',
    ),
  );
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

class _EmptyResourcePlanRepository extends Fake implements PlanRepository {
  @override
  Future<ContentResourceDetail> getContentResource(String resourceId) async =>
      const ContentResourceDetail(
        id: 'empty-course',
        title: 'Introduction to Business Analytics',
      );
}

const _bookMaterials = [
  PlanMaterialDetail(
    title: 'Start With Why',
    type: 'book',
    authorOrCreator: 'Simon Sinek',
    contentResourceId: 'book-1',
  ),
];

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

// Published lessons: the mission screen shows a step without content as
// "preparing" (tutorialRowStates), not as current or locked.
const _steps = [
  PlanStepDetail(
    id: 's1',
    title: 'Define the purpose',
    lessonContent: 'A published lesson.',
  ),
  PlanStepDetail(
    id: 's2',
    title: 'Map the evidence',
    lessonContent: 'A published lesson.',
  ),
  PlanStepDetail(
    id: 's3',
    title: 'Write the synthesis',
    lessonContent: 'A published lesson.',
  ),
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

  test('lesson progression supports one and five lesson missions', () {
    const oneLesson = PlanItemDetailed(
      item: _item,
      detailsStatus: 'available',
      steps: [PlanStepDetail(id: 'step_1', title: 'Build the artifact')],
      totalSteps: 1,
    );
    expect(oneLesson.activeStepIndex, 0);
    expect(oneLesson.isStepUnlocked(0), isTrue);

    const fiveLessons = PlanItemDetailed(
      item: _item,
      detailsStatus: 'available',
      steps: [
        PlanStepDetail(id: 'step_1', title: 'One'),
        PlanStepDetail(id: 'step_2', title: 'Two'),
        PlanStepDetail(id: 'step_3', title: 'Three'),
        PlanStepDetail(id: 'step_4', title: 'Four'),
        PlanStepDetail(id: 'step_5', title: 'Five'),
      ],
      completedStepIds: {'step_1', 'step_2'},
      completedSteps: 2,
      totalSteps: 5,
    );
    expect(fiveLessons.activeStepIndex, 2);
    expect(fiveLessons.isStepUnlocked(2), isTrue);
    expect(fiveLessons.isStepUnlocked(3), isFalse);
    expect(fiveLessons.isStepUnlocked(4), isFalse);
  });

  test('lesson references never fall back to unrelated materials', () {
    const materials = [
      PlanMaterialDetail(title: 'Deep Work: Rules for Focused Success'),
      PlanMaterialDetail(title: 'Unrelated Resource'),
    ];

    expect(
      matchLessonMaterials(const [
        'Deep Work — Rules for Focused Success',
      ], materials).map((material) => material.title),
      ['Deep Work: Rules for Focused Success'],
    );
    expect(matchLessonMaterials(const ['Missing title'], materials), isEmpty);
  });

  test('lesson markdown is outlined into the reader\'s sections', () {
    final outline = outlineLesson('''
# Define the purpose

## Why This Matters
Purpose creates a useful decision boundary.

## Core Framework
Separate the desired change from the activity.

## Guided Practice
Set a timer and write the decision boundary.
''');

    expect(outline.sections.map((section) => section.label), [
      'Why this skill',
      'The idea',
      'Try it',
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

    expect(find.text('LESSON 1 OF 3'), findsOneWidget);
    expect(find.text('8 min read'), findsOneWidget);
    expect(find.text('37 min practice'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Reading settings'));
    await tester.pumpAndSettle();
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Sepia'), findsOneWidget);
    Navigator.of(tester.element(find.text('Reading settings'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Contents'));
    await tester.pumpAndSettle();
    expect(find.text('The idea'), findsOneWidget);
    expect(find.text('References'), findsOneWidget);
    await tester.tap(find.text('References'));
    await tester.pumpAndSettle();

    expect(find.text('Start With Why'), findsOneWidget);
    expect(find.text('Simon Sinek'), findsOneWidget);
    // A book with a guide id reads as a study guide (was "Read book").
    const guide = AccessType.guide;
    expect(find.byType(V3AccessBadge), findsOneWidget);
    expect(find.text(accessCopy(guide).label), findsOneWidget);
    expect(find.text('Unrelated article'), findsNothing);
    expect(find.text('Open practice · 37 min'), findsOneWidget);
    await tester.tap(find.text('Start With Why'));
    await tester.pumpAndSettle();
    expect(find.text(accessCopy(guide).cta!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (branch, label) in [(0, 'Today'), (1, 'Plan')]) {
    testWidgets('a book opened from the tutorial keeps the $label shell '
        'branch', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const step = PlanStepDetail(
        id: 's1',
        title: 'Define the purpose',
        resources: ['Start With Why'],
        lessonContent: '''
# Define the purpose

## Why This Matters
Purpose creates a useful decision boundary.
''',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWithValue(_FakePlanRepository()),
          ],
          child: MaterialApp(
            home: branch == 1
                // The default is Plan's branch.
                ? const LessonReaderScreen(
                    itemId: 'mission-1',
                    missionTitle: 'Foundation & Research',
                    step: step,
                    stepNumber: 1,
                    totalSteps: 3,
                    materials: _bookMaterials,
                    completed: false,
                  )
                : LessonReaderScreen(
                    itemId: 'mission-1',
                    missionTitle: 'Foundation & Research',
                    step: step,
                    stepNumber: 1,
                    totalSteps: 3,
                    materials: _bookMaterials,
                    completed: false,
                    shellBranchIndex: branch,
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('References'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start With Why'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(accessCopy(AccessType.guide).cta!));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester
            .widget<BookReaderScreen>(find.byType(BookReaderScreen))
            .shellBranchIndex,
        branch,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

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
    // The current lesson's disc pulses, so pump rather than settle.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Lessons · 1 of 3'), findsOneWidget);
    expect(find.byKey(const Key('lesson-1-completed')), findsOneWidget);
    expect(find.byKey(const Key('lesson-2-active')), findsOneWidget);
    expect(find.byKey(const Key('lesson-3-locked')), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('lesson-3-locked')),
      180,
    );
    await tester.tap(find.byKey(const Key('lesson-3-locked')));
    await tester.pump();

    expect(find.text('Finish lesson 2 first'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a web reference opens the web viewer from the tutorial', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The web viewer builds on a fake platform (a test has no web view);
    // the previous platform is restored when the test ends.
    useFakeWebViewPlatform();

    const step = PlanStepDetail(
      id: 's1',
      title: 'Define the purpose',
      readingMinutes: 8,
      practiceMinutes: 7,
      estimateMinutes: 15,
      resources: ['Owner earnings'],
      lessonContent: '''
# Define the purpose

## Why This Matters
Purpose creates a useful decision boundary.
''',
    );
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
            materials: [
              PlanMaterialDetail(
                title: 'Owner earnings',
                type: 'article',
                url: 'https://example.org/owner-earnings',
              ),
            ],
            completed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('References'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner earnings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open source'));
    await tester.pumpAndSettle();

    final screen = tester.widget<MaterialWebScreen>(
      find.byType(MaterialWebScreen),
    );
    expect(screen.access, AccessType.web);
    expect(screen.openedFrom, 'Tutorial · Define the purpose');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an excerpt reading source opens as an excerpt from the '
      'tutorial', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    useFakeWebViewPlatform();

    const step = PlanStepDetail(
      id: 's1',
      title: 'Define the purpose',
      readingMinutes: 8,
      practiceMinutes: 7,
      estimateMinutes: 15,
      resources: ['The Personal MBA'],
      lessonContent: '''
# Define the purpose

## Why This Matters
Purpose creates a useful decision boundary.
''',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(_ExcerptPlanRepository()),
        ],
        child: const MaterialApp(
          home: LessonReaderScreen(
            itemId: 'mission-1',
            missionTitle: 'Foundation & Research',
            step: step,
            stepNumber: 1,
            totalSteps: 3,
            materials: [
              PlanMaterialDetail(
                title: 'The Personal MBA',
                type: 'book',
                authorOrCreator: 'Josh Kaufman',
                canonicalKey: 'book:josh_kaufman:the_personal_mba',
              ),
            ],
            completed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('References'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Personal MBA'));
    await tester.pumpAndSettle();
    // Not checked yet, the book reads as a guide; opening resolves it.
    await tester.tap(find.text('Open guide'));
    await tester.pumpAndSettle();

    final screen = tester.widget<MaterialWebScreen>(
      find.byType(MaterialWebScreen),
    );
    expect(screen.url, 'https://example.org/personal-mba-excerpt');
    expect(screen.access, AccessType.excerpt);
    expect(
      screen.sourceDescription,
      'Chapter 1 excerpt on the author’s website.',
    );
    expect(screen.openedFrom, 'Tutorial · Define the purpose');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('metadata-only resource shows an honest unavailable state', (
    tester,
  ) async {
    const material = PlanMaterialDetail(
      title: 'Introduction to Business Analytics',
      type: 'course',
      authorOrCreator: 'University of Pennsylvania (Coursera)',
      contentResourceId: 'legacy-empty-resource',
      durationMinutes: 120,
      reason: 'A useful external course recommendation.',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(
            _EmptyResourcePlanRepository(),
          ),
        ],
        child: const MaterialApp(
          home: MaterialReaderScreen(material: material),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The full content for this resource is not available.'),
      findsOneWidget,
    );
    expect(
      find.text('A useful external course recommendation.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
