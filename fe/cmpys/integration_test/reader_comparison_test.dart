import 'package:cmpys/core/ui/cmpys/learning_comparison_view.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/fixtures/comparison_reader_harness.dart';

bool highlighted(InlineSpan span) =>
    span is TextSpan &&
    (span.style?.backgroundColor == AppColors.green ||
        (span.children?.any(highlighted) ?? false));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real reader comparison, selection and synchronized text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = ComparisonReaderRepository();
    final narrator = ComparisonPreviewNarrator();
    await tester.pumpWidget(comparisonReaderHarness(repository, narrator));
    await tester.pumpAndSettle();
    expect(find.byType(LearningComparisonView), findsWidgets);
    await Scrollable.ensureVisible(
      tester.element(
        find.byKey(const ValueKey('learning-comparison-section-0')).first,
      ),
      alignment: 0,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('comparison-reading');
    await tester.tap(find.byKey(const Key('book-listen-button')));
    await tester.pumpAndSettle();
    expect(narrator.spoken, isNot(contains('|')));
    expect(narrator.spoken, isNot(contains('---')));
    final start = narrator.spoken.indexOf('INVESTMENT');
    expect(start, greaterThanOrEqualTo(0));
    narrator.progress?.call(start, start + 'INVESTMENT'.length, 'INVESTMENT');
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .any((text) => text.textSpan != null && highlighted(text.textSpan!)),
      isTrue,
    );
    await Scrollable.ensureVisible(
      tester.element(
        find.byKey(const ValueKey('learning-comparison-section-0')).first,
      ),
      alignment: 0,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('comparison-listening');
    await tester.tap(find.byKey(const Key('book-narration-play-pause')));
    await tester.pumpAndSettle();
    expect(repository.cursor?['narrationTextVersion'], 2);
    await tester.longPress(
      find.text('1. Thorough Financial Analysis', findRichText: true).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Compare the evidence before acting.',
    );
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(repository.savedQuote, isNotEmpty);
    expect(repository.savedQuote, isNot(contains('|')));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      comparisonReaderHarness(
        ComparisonReaderRepository(),
        ComparisonPreviewNarrator(),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(
        find.byKey(const ValueKey('learning-comparison-section-0')).first,
      ),
      alignment: 0,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('comparison-large-text');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
