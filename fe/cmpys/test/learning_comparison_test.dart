import 'package:cmpys/core/reading/learning_comparison.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_markdown.dart';
import 'package:cmpys/core/ui/cmpys/learning_comparison_view.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/learning_comparison_fixture.dart';

void main() {
  test(
    'exact saved investment diagram retains every word without its frame',
    () {
      final comparison = LearningComparison.parse(investmentComparison)!;
      expect(comparison.sections.length, 2);
      expect(comparison.sections.map((section) => section.items.length), [
        3,
        3,
      ]);
      expect(comparison.text, isNot(contains('|')));
      expect(comparison.text, isNot(contains('---')));
      String compact(String value) =>
          value.replaceAll(RegExp(r'[\s+|\-=]'), '');
      expect(compact(comparison.text), compact(investmentComparison));
      final doc = BookNarrationDocument.fromMarkdown(investmentMarkdown);
      expect(doc.blocks.single.comparison!.text, comparison.text);
      expect(
        doc.chunks.map((chunk) => chunk.text).join(' '),
        isNot(contains('|')),
      );
      for (final segment in doc.segments) {
        expect(
          doc.blocks[segment.blockIndex].text.substring(
            segment.start,
            segment.end,
          ),
          segment.text,
        );
      }
    },
  );

  test('new explicit comparison format supports readable bullets', () {
    final source =
        'First approach\n- First useful action\n- Second useful action\n\nvs.\n\nSecond approach\n- Another useful action\n- A different useful action';
    expect(LearningComparison.parse(source), isNull);
    expect(
      LearningComparison.parse(source, language: 'comparison')!.sections.length,
      2,
    );
  });

  test(
    'code, tables and incomplete boxes are never guessed into comparisons',
    () {
      expect(
        LearningComparison.parse(investmentComparison, language: 'python'),
        isNull,
      );
      for (final source in [
        'final x = 2;',
        '| Name | Value |\n| A | B |',
        investmentComparison.replaceFirst(
          '                                   vs.',
          'then',
        ),
        investmentComparison.replaceFirst('1. Thorough', '5. Thorough'),
        investmentComparison.replaceFirst(
          '1. Thorough',
          '1. return {}; Thorough',
        ),
      ]) {
        expect(LearningComparison.parse(source), isNull);
      }
      final doc = BookNarrationDocument.fromMarkdown(
        'A normal paragraph.\n\n```dart\nfinal x = 2;\n```',
      );
      expect(doc.blocks.map((b) => b.kind), [
        BookNarrationBlockKind.paragraph,
        BookNarrationBlockKind.code,
      ]);
      expect(doc.legacyDocument, isNull);
    },
  );

  test(
    'saved positions before, inside and after a legacy diagram migrate by text',
    () {
      final doc = BookNarrationDocument.fromMarkdown(
        'Before the diagram.\n\n$investmentMarkdown\n\nAfter the diagram, continue here.',
      );
      final old = doc.legacyDocument!;
      for (final word in [
        'Before',
        'Thorough',
        'Safety',
        'Principal',
        'Price',
        'Greater',
        'Sentiment',
        'After',
        'continue',
      ]) {
        final segment = old.segments.firstWhere((s) => s.text.contains(word));
        final position = doc.remapLegacyPosition(
          segment.index,
          segment.text.indexOf(word),
        );
        expect(
          doc.segments[position.$1].text.substring(position.$2),
          startsWith(word),
          reason: word,
        );
      }
    },
  );

  for (final width in [320.0, 430.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('comparison wraps at $width with text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SelectionArea(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CmpysMarkdown(investmentMarkdown, fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LearningComparisonView), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final section
            in find
                .byKey(const ValueKey('learning-comparison-section-0'))
                .evaluate()) {
          final box = section.renderObject as RenderBox;
          expect(box.size.width, lessThanOrEqualTo(width - 48));
        }
      });
    }
  }
}
