// Mirrors cmpys/backend/app/services/planning/tutorial_blocks.py (Task A6
// grammar plus its "Grammar update"): every valid fence parses, and each
// malformed case returns null so the reader shows the body as plain lines.
import 'package:cmpys/core/reading/lesson_fences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formula', () {
    const valid = '''
title: Owner earnings
= Owner earnings
+ Net income
- Maintenance capex
± Working capital
''';

    test('valid fence parses with signs normalised', () {
      final block = parseFormulaFence(valid)!;
      expect(block.title, 'Owner earnings');
      expect(block.terms.map((t) => t.sign), ['=', '+', '−', '±']);
      expect(block.terms[2].label, 'Maintenance capex');
    });

    test('Title header key is case-insensitive', () {
      expect(parseFormulaFence('TITLE: A\n= x\n× y'), isNotNull);
    });

    for (final entry in {
      'missing title': '= a\n+ b',
      'first sign is not =': 'title: T\n+ a\n= b',
      'only one term': 'title: T\n= a',
      'seven terms': 'title: T\n= a\n+ b\n+ c\n+ d\n+ e\n+ f\n+ g',
      'term without a space': 'title: T\n=a\n+ b',
      'unknown sign': 'title: T\n= a\n* b',
      'label over 60': 'title: T\n= a\n+ ${'x' * 61}',
      'title over 60': 'title: ${'x' * 61}\n= a\n+ b',
      'repeated title': 'title: T\ntitle: U\n= a\n+ b',
    }.entries) {
      test('malformed: ${entry.key}', () {
        expect(parseFormulaFence(entry.value), isNull);
      });
    }
  });

  group('chart', () {
    test('waterfall parses base, deltas and total', () {
      final block = parseChartFence('''
type: Waterfall
title: Reported to owner earnings
unit: \$m
Net income | 80
+D&A | 12
Maint. capex | −18
Working cap | -6
= Owner | 68
''')!;
      expect(block.type, ChartType.waterfall);
      expect(block.unit, r'$m');
      expect(block.rows.length, 5);
      expect(block.rows[2].value, -18);
      expect(block.rows[3].text, '−6');
      expect(block.rows.last.total, isTrue);
      expect(block.rows.last.label, 'Owner');
    });

    test('two-row waterfall (base plus total) is valid', () {
      expect(
        parseChartFence('type: waterfall\ntitle: T\nA | 5\n= B | 5'),
        isNotNull,
      );
    });

    test('waterfall total within 0.5% is accepted', () {
      // 1000 + 3 = 1003; 1008 is within 0.5% of 1008 (5.04).
      expect(
        parseChartFence(
          'type: waterfall\ntitle: T\nA | 1000\nB | 3\n= C | 1008',
        ),
        isNotNull,
      );
    });

    test('bars parse without a total row; empty unit means none', () {
      final block = parseChartFence(
        'type: bars\ntitle: T\nunit:\nA | 1\nB | 2.5',
      )!;
      expect(block.type, ChartType.bars);
      expect(block.unit, isNull);
      expect(block.rows[1].value, 2.5);
    });

    for (final entry in {
      'missing type': 'title: T\nA | 1\nB | 2',
      'unknown type': 'type: pie\ntitle: T\nA | 1\nB | 2',
      'missing title': 'type: bars\nA | 1\nB | 2',
      'one row': 'type: bars\ntitle: T\nA | 1',
      'nine rows':
          'type: bars\ntitle: T\n${List.generate(9, (i) => 'R$i | $i').join('\n')}',
      'three cells': 'type: bars\ntitle: T\nA | 1 | x\nB | 2',
      'comma number': 'type: bars\ntitle: T\nA | 1,000\nB | 2',
      'unit text in value': 'type: bars\ntitle: T\nA | 5m\nB | 2',
      'leading dot': 'type: bars\ntitle: T\nA | .5\nB | 2',
      'label over 24': 'type: bars\ntitle: T\n${'x' * 25} | 1\nB | 2',
      'unit over 12': 'type: bars\ntitle: T\nunit: ${'x' * 13}\nA | 1\nB | 2',
      'bars with a total row': 'type: bars\ntitle: T\nA | 1\n= B | 1',
      'waterfall without total': 'type: waterfall\ntitle: T\nA | 1\nB | 2',
      'waterfall total not last': 'type: waterfall\ntitle: T\n= A | 1\nB | 1',
      'waterfall with two totals':
          'type: waterfall\ntitle: T\nA | 1\n= B | 1\n= C | 1',
      'waterfall total off':
          'type: waterfall\ntitle: T\nA | 80\nB | 12\n= C | 70',
      'non-finite value': 'type: bars\ntitle: T\nA | ${'9' * 400}\nB | 2',
    }.entries) {
      test('malformed: ${entry.key}', () {
        expect(parseChartFence(entry.value), isNull);
      });
    }
  });

  group('steps', () {
    test('valued steps with a total parse', () {
      final block = parseStepsFence('''
title: From reported to owner earnings
unit: \$m
Start from net income | 80 | Reported profit.
Add back D&A | +12 | Non-cash charge.
Subtract maintenance capex | -24 | Keeps the business running.
= Owner earnings | 68
''')!;
      expect(block.title, 'From reported to owner earnings');
      expect(block.unit, r'$m');
      expect(block.rows.length, 3);
      expect(block.rows[2].text, '−24');
      expect(block.total!.label, 'Owner earnings');
      expect(block.total!.value, 68);
    });

    test('qualitative steps keep empty values and need no total', () {
      final block = parseStepsFence('''
title: Reading a claim
Name the claim | | What is being asserted?
Find the evidence | | What supports it?
''')!;
      expect(block.rows.every((row) => row.value == null), isTrue);
      expect(block.total, isNull);
    });

    test('steps total: rounding only, coarsest precision (Grammar update)', () {
      String fence(String total) =>
          'title: T\nA | 1000 | n\nB | -5 | n\n= Total | $total';
      expect(parseStepsFence(fence('995')), isNotNull);
      expect(parseStepsFence(fence('1000')), isNull);
      expect(parseStepsFence(fence('995.4')), isNotNull);
      expect(parseStepsFence(fence('995.6')), isNull);
      String decimals(String total) =>
          'title: T\nA | 12.5 | n\nB | 3.33 | n\n= Total | $total';
      expect(parseStepsFence(decimals('15.88')), isNotNull);
      expect(parseStepsFence(decimals('15.9')), isNull);
    });

    for (final entry in {
      'missing title': 'A | 1 | n\nB | 2 | n',
      'one step': 'title: T\nA | 1 | n',
      'seven steps':
          'title: T\n${List.generate(7, (i) => 'S$i | $i | n').join('\n')}',
      'two cells': 'title: T\nA | 1\nB | 2 | n',
      'empty note': 'title: T\nA | 1 | \nB | 2 | n',
      'note over 160': 'title: T\nA | 1 | ${'x' * 161}\nB | 2 | n',
      'non-number value': 'title: T\nA | about 5 | n\nB | 2 | n',
      'row starting with = before the total':
          'title: T\n= A | 1 | n\nB | 2 | n\n= C | 3',
      'total with three cells': 'title: T\nA | 1 | n\nB | 2 | n\n= C | 3 | x',
      'total without values': 'title: T\nA | | n\nB | | n\n= C | 0',
    }.entries) {
      test('malformed: ${entry.key}', () {
        expect(parseStepsFence(entry.value), isNull);
      });
    }
  });

  group('check', () {
    test('single choice', () {
      final block = parseCheckFence('''
Q: Which number is owner earnings?
- [ ] 80
- [x] 68
- [ ] 92
Why: Net income plus D&A minus maintenance capex.
''')!;
      expect(block.question, 'Which number is owner earnings?');
      expect(block.options.length, 3);
      expect(block.kind, CheckKind.single);
      expect(block.options[1].correct, isTrue);
      expect(block.why, 'Net income plus D&A minus maintenance capex.');
    });

    test('more than one correct option means select-all', () {
      final block = parseCheckFence(
        'q: Pick all\n- [X] a\n- [x] b\n- [ ] c\nwhy: Both.',
      )!;
      expect(block.kind, CheckKind.selectAll);
    });

    test('numeric answer with unit and tolerance', () {
      final block = parseCheckFence(
        'Q: Owner earnings?\nAnswer: 68 | Unit: \$m | Tolerance: 0.5\nWhy: 80 + 12 − 24.',
      )!;
      expect(block.kind, CheckKind.numeric);
      expect(block.numeric!.value, 68);
      expect(block.numeric!.unit, r'$m');
      expect(block.numeric!.tolerance, 0.5);
      expect(block.numeric!.accepts(68.4), isTrue);
      expect(block.numeric!.accepts(68.5), isTrue);
      expect(block.numeric!.accepts(68.6), isFalse);
    });

    test('numeric answer may have an empty unit and zero tolerance', () {
      final block = parseCheckFence(
        'Q: How many?\nanswer: −3 | unit: | tolerance: 0\nWhy: Count.',
      )!;
      expect(block.numeric!.value, -3);
      expect(block.numeric!.unit, '');
      expect(block.numeric!.accepts(-3), isTrue);
      expect(block.numeric!.accepts(-2.9), isFalse);
    });

    for (final entry in {
      'missing Q': '- [x] a\n- [ ] b\nWhy: w',
      'missing Why': 'Q: q\n- [x] a\n- [ ] b',
      'one option': 'Q: q\n- [x] a\nWhy: w',
      'five options':
          'Q: q\n- [x] a\n- [ ] b\n- [ ] c\n- [ ] d\n- [ ] e\nWhy: w',
      'no correct option': 'Q: q\n- [ ] a\n- [ ] b\nWhy: w',
      'option without brackets': 'Q: q\n- a\n- [x] b\nWhy: w',
      'options mixed with an answer':
          'Q: q\n- [x] a\nanswer: 1 | unit: | tolerance: 0\nWhy: w',
      'answer not a number':
          'Q: q\nanswer: five | unit: | tolerance: 0\nWhy: w',
      'answer keys out of order':
          'Q: q\nunit: | answer: 1 | tolerance: 0\nWhy: w',
      'negative tolerance': 'Q: q\nanswer: 1 | unit: | tolerance: -1\nWhy: w',
      'non-finite answer':
          'Q: q\nanswer: ${'9' * 400} | unit: | tolerance: 0\nWhy: w',
      'empty question': 'Q:\n- [x] a\n- [ ] b\nWhy: w',
      'question over 240': 'Q: ${'x' * 241}\n- [x] a\n- [ ] b\nWhy: w',
      'why over 280': 'Q: q\n- [x] a\n- [ ] b\nWhy: ${'x' * 281}',
    }.entries) {
      test('malformed: ${entry.key}', () {
        expect(parseCheckFence(entry.value), isNull);
      });
    }
  });

  group('envelope', () {
    test(
      'finds native fences at line start, with trailing spaces and CRLF',
      () {
        const text =
            'Intro\n```formula  \ntitle: T\n= a\n+ b\n```\n'
            'Code\n```python\nprint(1)\n```\n'
            '```chart\r\ntype: bars\r\ntitle: T\r\nA | 1\r\nB | 2\r\n```\r\n';
        final fences = findLessonFences(text);
        expect(fences.map((f) => f.kind), ['formula', 'chart']);
        expect(parseFormulaFence(fences[0].body), isNotNull);
        expect(parseChartFence(fences[1].body), isNotNull);
      },
    );

    test('an info string after the kind is not a native fence', () {
      expect(findLessonFences('```formula extra\n= a\n+ b\n```\n'), isEmpty);
    });

    test('pieces keep prose around fences in order', () {
      final pieces = splitLessonPieces(
        'Before.\n\n```check\nQ: q\n- [x] a\n- [ ] b\nWhy: w\n```\n\nAfter.',
      );
      expect(pieces.length, 3);
      expect((pieces[0] as LessonProse).markdown, 'Before.');
      expect((pieces[1] as LessonFence).kind, 'check');
      expect((pieces[2] as LessonProse).markdown, 'After.');
    });
  });

  group('section contract', () {
    const newFormat = '''
# Owner earnings

## Why This Matters
Profit is not cash.

## Core Framework
Owner earnings adjust profit.

```formula
title: Owner earnings
= Owner earnings
+ Net income
```

## Worked Example
A worked case.

```chart
type: bars
title: T
A | 1
B | 2
```

```steps
title: T
A | 1 | n
B | 2 | n
```

## Failure Modes
- Treating growth capex as maintenance.

## Check Your Understanding
```check
Q: q
- [x] a
- [ ] b
Why: w
```

## References
- A book
''';

    test('new format: design order, visuals pulled into Seeing it', () {
      final outline = outlineLesson(newFormat);
      expect(outline.canonical, isTrue);
      expect(outline.legacy, isFalse);
      expect(outline.sections.map((s) => s.id), [
        'why',
        'idea',
        'visual',
        'example',
        'errors',
        'check',
        'refs',
      ]);
      expect(outline.sections.map((s) => s.label), [
        'Why this skill',
        'The idea',
        'Seeing it',
        'Worked example',
        'Common errors',
        'Check yourself',
        'References',
      ]);
      final visual = outline.sections[2].pieces.whereType<LessonFence>();
      expect(visual.map((f) => f.kind), ['formula', 'chart']);
      final example = outline.sections[3].pieces;
      expect(example.whereType<LessonFence>().map((f) => f.kind), ['steps']);
      expect(outline.sections[1].pieces.whereType<LessonFence>(), isEmpty);
    });

    test('a missing heading omits its section; no visual, no Seeing it', () {
      final outline = outlineLesson(
        '## Why This Matters\nWhy.\n\n## Check Your Understanding\nCheck.',
      );
      expect(outline.sections.map((s) => s.id), ['why', 'check']);
    });

    test('legacy Guided Practice renders as Try it; diagrams in Seeing it', () {
      final outline = outlineLesson('''
## Why This Matters
Why.

## Core Framework
Idea.

## Worked Example
Example.

```diagram
[A]
 │
 ▼
[B]
```

## Guided Practice
Do it.

## Check Your Understanding
Check.
''');
      expect(outline.legacy, isTrue);
      expect(outline.sections.map((s) => s.label), [
        'Why this skill',
        'The idea',
        'Seeing it',
        'Worked example',
        'Try it',
        'Check yourself',
      ]);
      expect(
        outline.sections[2].pieces.whereType<LessonFence>().single.kind,
        'diagram',
      );
    });

    test('the first copy of a canonical heading wins', () {
      final outline = outlineLesson(
        '## Why This Matters\nFirst.\n\n## Why This Matters\nSecond.',
      );
      expect(outline.sections.single.pieces.length, 1);
      expect(
        (outline.sections.single.pieces.single as LessonProse).markdown,
        'First.',
      );
    });

    test('text without canonical headings keeps its own headings', () {
      final outline = outlineLesson(
        '# Title\nLead.\n\n## One clear idea\nIdea.\n\n## Try it\nGo.',
      );
      expect(outline.canonical, isFalse);
      expect(outline.sections.map((s) => s.label), [
        null,
        'One clear idea',
        'Try it',
      ]);
    });

    test('error items split a Failure Modes list into cards', () {
      final split = splitErrorItems(
        'Watch for these.\n\n- **First** mistake\n  continues here.\n- Second one.',
      );
      expect(split.lead, 'Watch for these.');
      expect(split.items, ['**First** mistake continues here.', 'Second one.']);
    });
  });
}
