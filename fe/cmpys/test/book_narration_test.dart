import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markdown becomes ordered, sentence-sized narration segments', () {
    final document = BookNarrationDocument.fromMarkdown('''
First sentence. **Second sentence stays readable.**

### Practice This

1. Start with one action.
2. Record what changed!

> A quoted idea remains part of the narration.
''');

    expect(document.segments.map((segment) => segment.text), [
      'First sentence.',
      'Second sentence stays readable.',
      'Practice This',
      'Start with one action.',
      'Record what changed!',
      'A quoted idea remains part of the narration.',
    ]);
    expect(document.blocks.map((block) => block.kind), [
      BookNarrationBlockKind.paragraph,
      BookNarrationBlockKind.heading,
      BookNarrationBlockKind.listItem,
      BookNarrationBlockKind.listItem,
      BookNarrationBlockKind.quote,
    ]);
    expect(document.blocks[2].listMarker, '1.');
    expect(document.blocks[3].listMarker, '2.');
  });

  test('sentence offsets map exactly back to the visible block', () {
    final document = BookNarrationDocument.fromMarkdown(
      'Read this first. Then keep going?',
    );

    final block = document.blocks.single;
    for (final segment in document.segments) {
      expect(block.text.substring(segment.start, segment.end), segment.text);
    }
  });

  test('common abbreviations do not create false narration jumps', () {
    final document = BookNarrationDocument.fromMarkdown(
      'Use a small cue, e.g. a card by the door. Then begin.',
    );

    expect(document.segments.map((segment) => segment.text), [
      'Use a small cue, e.g. a card by the door.',
      'Then begin.',
    ]);
  });

  test(
    'paragraph-aware chunks stay bounded and preserve sentence navigation',
    () {
      final paragraph = List.generate(
        34,
        (index) =>
            'Sentence $index carries enough context for natural narration.',
      ).join(' ');
      final document = BookNarrationDocument.fromMarkdown(
        '$paragraph\n\n$paragraph',
      );

      expect(document.chunks.length, greaterThan(1));
      expect(
        document.chunks.every((chunk) => chunk.text.length <= 1800),
        isTrue,
      );
      expect(document.chunks.any((chunk) => chunk.text.length >= 600), isTrue);
      for (final chunk in document.chunks) {
        for (final slice in chunk.segments) {
          final segment = document.segments[slice.segmentIndex];
          expect(
            chunk.text.substring(slice.start, slice.end),
            segment.text.substring(slice.segmentStart, slice.segmentEnd),
          );
        }
      }
    },
  );

  test('an overlong sentence splits without joining or losing words', () {
    final sentence = List.generate(430, (index) => 'token$index').join(' ');
    final document = BookNarrationDocument.fromMarkdown(sentence);

    expect(document.segments, hasLength(1));
    expect(document.chunks.length, greaterThan(1));
    expect(document.chunks.every((chunk) => chunk.text.length <= 1800), isTrue);
    final reconstructed = document.chunks
        .map((chunk) => chunk.text)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    expect(reconstructed, sentence);
  });

  test('exact cue lookup clears highlights during every silence interval', () {
    const cues = [
      BookNarrationCue(
        start: 0,
        end: 5,
        startTime: Duration(milliseconds: 200),
        endTime: Duration(milliseconds: 400),
      ),
      BookNarrationCue(
        start: 6,
        end: 10,
        startTime: Duration(milliseconds: 700),
        endTime: Duration(milliseconds: 900),
      ),
    ];

    expect(activeBookNarrationCueAt(cues, Duration.zero), isNull);
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 250)),
      same(cues.first),
    );
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 500)),
      isNull,
    );
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 750)),
      same(cues.last),
    );
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 900)),
      isNull,
    );
  });

  test('legacy code-point offsets convert safely to Dart UTF-16 offsets', () {
    final cue = BookNarrationCue.fromJson(
      const {'start': 2, 'end': 3, 'startMs': 0, 'endMs': 100},
      sourceText: '💡 A',
      offsetEncoding: 'unicode_codepoints',
    );

    expect(cue.start, 3);
    expect(cue.end, 4);
    expect(
      BookNarrationAlignmentGranularity.fromApi(
        'provider_segment',
        hasAlignment: true,
      ),
      BookNarrationAlignmentGranularity.phrase,
    );
  });
}
