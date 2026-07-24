import 'package:cmpys/features/plan/presentation/book_narration.dart';
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
}
