// Fixture-only native UI smoke. No backend, account, or provider calls.
// Setup warms the public Google Fonts cache. During the flow, runtime font
// downloads are disabled and unexpected HTTP clients fail closed.
import 'dart:io';

import 'package:cmpys/core/ui/cmpys/learning_comparison_view.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Native tutorial smoke must not use the network.');
}

class _CompletionRepository extends Fake implements PlanRepository {
  int completions = 0;
  String? completedArtifact;
  String? completedItem;
  String? completedStep;

  @override
  Future<({bool completed, bool itemCompleted})> toggleStepComplete(
    String itemId,
    String stepId, {
    String? artifactJobId,
    bool? complete,
  }) async {
    completedItem = itemId;
    completedStep = stepId;
    completions++;
    completedArtifact = artifactJobId;
    return (completed: true, itemCompleted: false);
  }
}

class _SavedPracticeRepository extends Fake implements PracticeRepository {
  int loads = 0;
  String? loadedArtifact;
  String? loadedItem;
  String? loadedStep;

  final response = LessonPracticeState.fromJson({
    'state': 'ready',
    'revision': 2,
    'complete': true,
    'answers': {
      'claim.reason': 'The observation is separate from its explanation.',
    },
    'passed_activity_ids': ['claim'],
    'workbook': {
      'title': 'Practice one clear claim',
      'activities': [
        {
          'id': 'claim',
          'title': 'Explain the observation',
          'kind': 'practice',
          'instructions':
              'Explain why a clear claim should distinguish an observation from an explanation.',
          'minutes_min': 2,
          'minutes_max': 3,
          'fields': [
            {'id': 'reason', 'label': 'Your explanation', 'kind': 'text'},
          ],
        },
      ],
    },
  });

  @override
  Future<LessonPracticeState> load(
    String item,
    String step,
    String? artifact,
  ) async {
    loads++;
    loadedItem = item;
    loadedStep = step;
    loadedArtifact = artifact;
    return response;
  }
}

const _tutorial = PlanStepDetail(
  id: 'step_1',
  title: 'Explain a claim',
  lessonFormat: 'tutorial_v1',
  estimateMinutes: 7,
  readingMinutes: 4,
  practiceMinutes: 3,
  lessonContent: '''
# Explain a claim

## Why This Matters
A clear claim helps a reader follow what you observed and why you think it happened.

## Core Framework
Separate the observation from the explanation, then name a way to test it.

```comparison
A vague claim
- Observation and explanation are mixed
- No way to test the explanation
vs
A clear claim
- Observation and explanation are separate
- A test can check the explanation
```

## Worked Example
A plant grew toward the window. Light may explain the direction of growth.
Moving the plant gives us a way to test that explanation.

## Failure Modes
Do not treat a plausible explanation as a confirmed cause.

## Guided Practice
Explain why separating the observation from its explanation makes a claim clearer.

## Check Your Understanding
Can another person tell what was observed and what still needs testing?

## References
No outside material is required for this tutorial.
''',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() async {
    await GoogleFonts.pendingFonts([
      GoogleFonts.instrumentSerif(),
      GoogleFonts.instrumentSerif(fontStyle: FontStyle.italic),
      GoogleFonts.literata(),
      GoogleFonts.playfairDisplay(),
      GoogleFonts.playfairDisplay(fontStyle: FontStyle.italic),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
      for (final weight in [
        FontWeight.w300,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
      ])
        GoogleFonts.jetBrainsMono(fontWeight: weight),
    ]).timeout(const Duration(seconds: 30));
    GoogleFonts.config.allowRuntimeFetching = false;
    HttpOverrides.global = _NoNetwork();
  });

  testWidgets(
    'native continuous tutorial, contents, visual, and saved practice finish',
    (tester) async {
      final completion = _CompletionRepository();
      final practice = _SavedPracticeRepository();
      bool? finished;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWithValue(completion),
            practiceRepositoryProvider.overrideWithValue(practice),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      finished = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const LessonReaderScreen(
                            itemId: 'native-fixture-item',
                            missionTitle: 'A sequence of short tutorials',
                            step: _tutorial,
                            stepNumber: 1,
                            totalSteps: 12,
                            materials: [],
                            completed: false,
                            artifactJobId: 'native-fixture-artifact',
                          ),
                        ),
                      );
                    },
                    child: const Text('Open tutorial'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open tutorial'));
      await tester.pumpAndSettle();
      expect(find.text('TUTORIAL 1 OF 12'), findsOneWidget);
      expect(find.text('4 min read'), findsOneWidget);
      expect(find.text('3 min practice'), findsOneWidget);
      expect(find.byType(LearningComparisonView), findsOneWidget);
      await tester.ensureVisible(find.byType(LearningComparisonView));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.bySemanticsLabel('Contents'));
      await tester.pumpAndSettle();
      expect(find.text('Worked example'), findsOneWidget);
      await tester.tap(find.text('Worked example'));
      await tester.pumpAndSettle();
      expect(find.text('Worked example'), findsNothing);
      expect(find.text('WORKED EXAMPLE'), findsOneWidget);
      final readerScroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(LessonReaderScreen.scrollKey),
          matching: find.byType(Scrollable),
        ),
      );
      expect(readerScroll.position.pixels, greaterThan(0));
      expect(find.text('Open practice · 3 min'), findsOneWidget);
      await tester.tap(find.text('Open practice · 3 min'));
      await tester.pumpAndSettle();
      expect(find.text('Practice · Tutorial 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('answer-claim.reason')),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join(' | '),
      );
      final answer = tester.widget<TextField>(
        find.byKey(const ValueKey('answer-claim.reason')),
      );
      expect(
        answer.controller?.text,
        'The observation is separate from its explanation.',
      );
      expect(answer.enabled, isFalse);
      expect(practice.loadedItem, 'native-fixture-item');
      expect(practice.loadedStep, 'step_1');
      expect(practice.loadedArtifact, 'native-fixture-artifact');
      await tester.ensureVisible(find.text('Finish tutorial'));
      await tester.tap(find.text('Finish tutorial'));
      await tester.pumpAndSettle();
      expect(find.text('Tutorial 1 complete'), findsOneWidget);
      expect(completion.completions, 1);
      expect(completion.completedItem, 'native-fixture-item');
      expect(completion.completedStep, 'step_1');
      expect(completion.completedArtifact, 'native-fixture-artifact');
      expect(practice.loads, 1);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(find.text('Open tutorial'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_TUTORIAL_SMOKE passed: continuous reader, native comparison, '
        'honest timing, contents jump, saved practice, artifact-bound completion '
        'and celebration. '
        'Fixture repositories only; HTTP disabled; no account or provider calls.',
      );
    },
  );
}
