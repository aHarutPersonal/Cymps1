import 'package:cmpys/core/reading/learning_diagram.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_markdown.dart';
import 'package:cmpys/core/ui/cmpys/learning_comparison_view.dart';
import 'package:cmpys/core/ui/cmpys/learning_diagram_view.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/live_learning_diagrams.dart';
import 'fixtures/live_first_chapter_diagnostic.dart';

String body(String fenced) => fenced
    .split('\n')
    .skip(1)
    .join('\n')
    .replaceFirst(RegExp(r'```$'), '')
    .trim();
String words(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
void main() {
  test('all explicit links survive; no framed note gains an invented link', () {
    const linkCounts = [0, 4, 2, 2, 0, 0, 0, 7, 3, 3, 5, 5];
    for (var i = 1; i < liveLearningDiagrams.length; i++) {
      final diagram = BookNarrationDocument.fromMarkdown(
        liveLearningDiagrams[i],
      ).blocks.single.diagram!;
      final count = diagram.lines.fold<int>(
        0,
        (n, line) =>
            n +
            line.reverseLinks.length +
            (line.parentLineIndex == null ? 0 : 1),
      );
      expect(count, linkCounts[i], reason: 'fixture $i');
    }
    final friction = BookNarrationDocument.fromMarkdown(
      liveLearningDiagrams[9],
    ).blocks.single.diagram!;
    expect(
      friction.lines[1].parentPartIndex,
      1,
      reason: 'Friction A, not the initial skill label',
    );
    final loop = BookNarrationDocument.fromMarkdown(
      liveLearningDiagrams[11],
    ).blocks.single.diagram!;
    expect(loop.lines[1].parentPartIndex, 1, reason: 'Leading indicators');
    expect(
      loop.lines[2].entryPartIndex,
      1,
      reason: 'Correction enters Post-Mortem, not Completion',
    );
    final buffer = BookNarrationDocument.fromMarkdown(
      liveLearningDiagrams[2],
    ).blocks.single.diagram!;
    expect(buffer.lines.take(3).map((line) => line.parentLineIndex), [
      null,
      0,
      0,
    ]);
    expect(buffer.lines[1].branch, isTrue);
    final bidirectional = BookNarrationDocument.fromMarkdown(
      liveLearningDiagrams[3],
    ).blocks.single.diagram!;
    expect(bidirectional.lines.take(2).map((line) => line.reverseLinks), [
      [0],
      [0],
    ]);
  });

  testWidgets('code escaping is undone once at the Markdown boundary', (
    tester,
  ) async {
    const code = 'if (a < b && c > d) { print("&gt; &amp; &#62;"); }';
    const markdown = '```dart\n$code\n```';
    final document = BookNarrationDocument.fromMarkdown(markdown);
    expect(document.blocks.single.kind, BookNarrationBlockKind.code);
    expect(document.blocks.single.text, code);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CmpysMarkdown(markdown))),
    );
    await tester.pumpAndSettle();
    expect(find.text(code), findsOneWidget);
    final literalArrow = liveLearningDiagrams[1].replaceAll('--->', '---&gt;');
    final literal = BookNarrationDocument.fromMarkdown(
      literalArrow,
    ).blocks.single;
    expect(literal.kind, BookNarrationBlockKind.code);
    expect(literal.text, contains('---&gt;'));
    expect(literal.text, isNot(contains('&amp;gt;')));
    for (final version in [1, 2]) {
      final old = version == 1
          ? document.legacyDocument!
          : document.previousDocument!;
      final point = document.remapLegacyPosition(
        0,
        old.segments.first.text.indexOf('print'),
        textVersion: version,
      );
      expect(
        document.segments[point.$1].text.substring(point.$2),
        startsWith('print'),
      );
    }
  });

  test(
    'ambiguous or dangling connectors and language-labelled code stay literal',
    () {
      for (final source in [
        '[A] ──► [B]\n     │\n     ▼\n[C]',
        '[A] ──►\n│\n[B]',
        '[A]\n  │\n ▼\n[B]',
      ]) {
        expect(LearningDiagram.parse(source), isNull, reason: source);
      }
    },
  );
  test(
    'every diagram delivered in the two real books has a semantic renderer',
    () {
      expect(liveLearningDiagrams.length, 12);
      for (final markdown in liveLearningDiagrams) {
        final doc = BookNarrationDocument.fromMarkdown(markdown);
        expect(doc.blocks.length, 1);
        final block = doc.blocks.single;
        expect(
          block.comparison != null || block.diagram != null,
          isTrue,
          reason: markdown,
        );
        expect(
          words(block.text),
          words(body(markdown)),
          reason: 'No reordered, invented or lost words',
        );
        expect(block.text, isNot(contains('---')));
        expect(block.text, isNot(contains('│')));
      }
    },
  );
  test(
    'vertical arrows remain directed links, sibling branches retain one parent',
    () {
      final chain = LearningDiagram.parse(
        body(
          liveLearningDiagrams.firstWhere(
            (m) => m.contains('Friction Point A'),
          ),
        ),
      )!;
      expect(chain.lines.map((l) => l.parentLineIndex), [null, 0, 1]);
      expect(chain.lines.map((l) => l.directed), [false, true, true]);
      final tree = LearningDiagram.parse(
        body(
          liveLearningDiagrams.firstWhere((m) => m.contains('Non-Negotiable')),
        ),
      )!;
      expect(tree.lines.map((l) => l.parentLineIndex), [null, 0, 0]);
      expect(tree.lines.map((l) => l.branch), [false, true, true]);
      final independent = LearningDiagram.parse(
        body(
          liveLearningDiagrams.firstWhere(
            (m) => m.contains('MR. MARKET ALLEGORY'),
          ),
        ),
      )!;
      expect(
        independent.lines.every((line) => line.parentLineIndex == null),
        isTrue,
      );
      expect(independent.lines.take(2).map((line) => line.parts.length), [
        3,
        3,
      ]);
    },
  );
  test('v1 and v2 positions migrate through newly transformed diagrams', () {
    final markdown =
        '${liveLearningDiagrams[0]}\n\n${liveLearningDiagrams[1]}\n\nAfter this diagram continue reading.';
    final current = BookNarrationDocument.fromMarkdown(markdown);
    for (final version in [1, 2]) {
      // v1 and v2 were parsed with the Markdown parser's HTML escaping.
      final old = BookNarrationDocument.fromMarkdown(
        markdown,
        semanticComparisons: version == 2,
        semanticDiagrams: false,
        encodeHtml: true,
      );
      for (final word in [
        'Euphoria',
        'SELL',
        'Despair',
        'dictate',
        'After',
        'continue',
      ]) {
        final segment = old.segments.firstWhere((s) => s.text.contains(word));
        final position = current.remapLegacyPosition(
          segment.index,
          segment.text.indexOf(word),
          textVersion: version,
        );
        expect(
          current.segments[position.$1].text.substring(position.$2),
          startsWith(word),
          reason: '$version $word',
        );
      }
    }
  });
  test('unknown code and dangling connectors remain fallback', () {
    expect(LearningDiagram.parse('[Input]\n│\n▼\n[Output]\n│'), isNull);
    expect(
      LearningDiagram.parse('[Input]\n│\n▼\n[Output]', language: 'python'),
      isNull,
    );
    expect(LearningDiagram.parse('class Example {\n x = [1, 2];\n}'), isNull);
  });
  testWidgets(
    'full API chapter still renders original comparison through production splitting',
    (tester) async {
      final chapter = splitBookChapters(
        '$liveFirstChapter\n\n## Following Chapter\nFollow up.',
      ).first;
      expect(
        BookNarrationDocument.fromMarkdown(
          chapter.markdown,
        ).blocks.where((b) => b.comparison != null).length,
        1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CmpysMarkdown(chapter.markdown)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LearningComparisonView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('all real formats wrap at 320 pixels, scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final markdown in liveLearningDiagrams.skip(1)) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SelectionArea(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CmpysMarkdown(markdown, fontSize: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(LearningDiagramView),
          findsOneWidget,
          reason: markdown,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}
