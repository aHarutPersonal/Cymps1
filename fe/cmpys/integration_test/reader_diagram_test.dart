import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/cmpys/learning_diagram_view.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/fixtures/comparison_reader_harness.dart';
import '../test/fixtures/diagram_reader_harness.dart';

bool highlighted(InlineSpan span) =>
    span is TextSpan &&
    (span.style?.backgroundColor == AppColors.green ||
        (span.children?.any(highlighted) ?? false));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> startOrResume(WidgetTester tester) async {
    final firstListen = find.byKey(const Key('book-listen-button'));
    await tester.tap(
      firstListen.evaluate().isNotEmpty
          ? firstListen
          : find.byKey(const Key('book-narration-play-pause')),
    );
    await tester.pumpAndSettle();
  }

  for (final scenario in [
    (1, 'mr-market', 'Euphoria'),
    (10, 'playbook-tree', 'Execution'),
  ]) {
    testWidgets(
      'real reader ${scenario.$2}: highlight, note, pause and resume',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final repository = DiagramReaderRepository(scenario.$1);
        final narrator = ComparisonPreviewNarrator();
        await tester.pumpWidget(comparisonReaderHarness(repository, narrator));
        await tester.pumpAndSettle();
        expect(find.byType(LearningDiagramView), findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(find.byType(LearningDiagramView)),
          alignment: 0,
        );
        await tester.pumpAndSettle();
        await binding.takeScreenshot('${scenario.$2}-reading');
        await startOrResume(tester);
        expect(narrator.spoken, isNot(contains('---')));
        expect(narrator.spoken, isNot(contains('&gt;')));
        final offset = narrator.spoken.indexOf(scenario.$3);
        expect(offset, greaterThanOrEqualTo(0));
        narrator.progress?.call(
          offset,
          offset + scenario.$3.length,
          scenario.$3,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any(
                (text) => text.textSpan != null && highlighted(text.textSpan!),
              ),
          isTrue,
        );
        await binding.takeScreenshot('${scenario.$2}-listening');
        await tester.tap(find.byKey(const Key('book-narration-play-pause')));
        await tester.pumpAndSettle();
        expect(repository.cursor?['narrationTextVersion'], 3);
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any(
                (text) => text.textSpan != null && highlighted(text.textSpan!),
              ),
          isFalse,
        );
        final node = scenario.$1 == 1 ? 'High Euphoria' : 'Execution Mechanics';
        await Scrollable.ensureVisible(
          tester.element(find.text(node, findRichText: true).first),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text(node, findRichText: true).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add note'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Keep this principle in view.',
        );
        await tester.tap(find.text('Save note'));
        await tester.pumpAndSettle();
        expect(repository.savedQuote, isNotEmpty);
        expect(repository.savedQuote, isNot(contains('From ')));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final resumed = ComparisonPreviewNarrator();
        await tester.pumpWidget(comparisonReaderHarness(repository, resumed));
        await tester.pumpAndSettle();
        await startOrResume(tester);
        expect(resumed.spoken, startsWith(scenario.$3));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          comparisonReaderHarness(
            DiagramReaderRepository(scenario.$1),
            ComparisonPreviewNarrator(),
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.byType(LearningDiagramView)),
          alignment: 0,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('${scenario.$2}-large-text');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'real reader migrates v2 server position in a transformed diagram',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = DiagramReaderRepository(1);
      final resource = await repository.getResource('comparison-fixture');
      final chapter = splitBookChapters(resource.contentMarkdown!).first;
      final old = BookNarrationDocument.fromMarkdown(
        chapter.markdown,
        semanticDiagrams: false,
      );
      final segment = old.segments.firstWhere(
        (s) => s.text.contains('Despair'),
      );
      repository.cursor = {
        'narrationChapter': 0,
        'narrationSegment': segment.index,
        'narrationCharacterOffset': segment.text.indexOf('Despair'),
        'narrationTextVersion': 2,
        'narrationUpdatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
      };
      final narrator = ComparisonPreviewNarrator();
      await tester.pumpWidget(comparisonReaderHarness(repository, narrator));
      await tester.pumpAndSettle();
      await startOrResume(tester);
      expect(narrator.spoken, startsWith('Despair'));
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await tester.pumpAndSettle();
      expect(repository.cursor?['narrationTextVersion'], 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
