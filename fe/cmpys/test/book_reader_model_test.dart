import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated book markdown becomes navigable reader chapters', () {
    final chapters = splitBookChapters('''
# Deep Work

## Focus Rituals

Protect the first hour.

### Practice This
1. Block the hour.

## Attention Residue

Finish one context before opening another.

## Closing Synthesis

Combine both practices.
''');

    expect(chapters.map((chapter) => chapter.title), [
      'Focus Rituals',
      'Attention Residue',
      'Closing Synthesis',
    ]);
    expect(chapters.first.markdown, contains('Protect the first hour.'));
    expect(chapters.first.markdown, isNot(contains('# Deep Work')));
  });

  test('unstructured long text is split into manageable reader parts', () {
    final paragraph = List.filled(2600, 'word').join(' ');
    final chapters = splitBookChapters('$paragraph\n\n$paragraph');

    expect(chapters.length, 2);
    expect(chapters.first.title, 'Part 1');
    expect(chapters.last.title, 'Part 2');
  });
}
