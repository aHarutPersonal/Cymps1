// Task D5: the v3 tutorial reader (design v3/tutorial.jsx `LessonScreen`).
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_markdown.dart';
import 'package:cmpys/core/ui/cmpys/learning_diagram_view.dart';
import 'package:cmpys/core/ui/v3/lesson_blocks/formula_stack.dart';
import 'package:cmpys/core/ui/v3/lesson_blocks/illustration_hero.dart';
import 'package:cmpys/core/ui/v3/lesson_blocks/quick_check.dart';
import 'package:cmpys/core/ui/v3/lesson_blocks/waterfall_chart.dart';
import 'package:cmpys/core/ui/v3/lesson_blocks/worked_steps.dart';
import 'package:cmpys/core/ui/v3/motion.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/material_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _newFormat = '''
# Owner earnings

## Why This Matters
Reported profit is not the cash an owner can take out.

## Core Framework
Owner earnings adjust reported profit for what the business really consumes.

```formula
title: Owner earnings
= Owner earnings
+ Net income
- Maintenance capex
```

## Worked Example
Take a company that reports 80 of net income.

```chart
type: waterfall
title: Reported to owner earnings
Net | 80
D&A | 12
Maint. | -24
= Owner | 68
```

```steps
title: Acme Co.
Start from net income | 80 | The reported profit.
Add back D&A | 12 | A non-cash charge.
Subtract maintenance capex | -24 | Spending that keeps the lights on.
= Owner earnings | 68
```

## Failure Modes
- Treating growth capex as maintenance.
- Ignoring working capital.

## Check Your Understanding
```check
Q: What are the owner earnings here?
- [ ] 80
- [x] 68
- [ ] 92
- [ ] 56
Why: 80 plus 12 minus 24 is 68.
```

## References
- Start With Why
''';

const _legacy = '''
# Explain a claim

## Why This Matters
Claims need evidence.

## Core Framework
A claim connects observation and explanation.

```diagram
[Observe]
    │
    ▼
[Explain]
```

## Worked Example
The plant grew toward the window.

## Failure Modes
- Confusing a guess with a test.

## Guided Practice
Write one observation and a test of your own.

## Check Your Understanding
What makes a claim testable?
''';

PlanStepDetail _step({
  String content = _newFormat,
  TutorialIllustration? illustration,
}) => PlanStepDetail(
  id: 's2',
  title: 'Owner earnings',
  readingMinutes: 6,
  practiceMinutes: 12,
  resources: const ['Start With Why'],
  lessonContent: content,
  lessonFormat: 'tutorial_v1',
  illustration: illustration,
);

/// The reader in a fresh app session. [signedIn] opens an account's store,
/// as the app does before any screen shows (the store is kept per account,
/// so it persists only then).
Widget _reader(
  PlanStepDetail step, {
  bool completed = false,
  bool signedIn = false,
}) => ProviderScope(
  overrides: [
    if (signedIn)
      cmpysStoreProvider.overrideWith(
        (ref) => CmpysStore()..openAccount('acct', unkeyedOwner: 'acct'),
      ),
  ],
  child: MaterialApp(
    home: LessonReaderScreen(
      itemId: 'mission-1',
      missionTitle: 'Read the numbers',
      step: step,
      stepNumber: 2,
      totalSteps: 5,
      week: '3',
      materials: const [
        PlanMaterialDetail(
          title: 'Start With Why',
          type: 'book',
          authorOrCreator: 'Simon Sinek',
          contentResourceId: 'book-1',
        ),
      ],
      completed: completed,
    ),
  ),
);

Widget _block(String kind, String body, {Key? key}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: LessonFenceBlock(key: key, kind: kind, body: body),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sections_in_design_order', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_reader(_step()));
    await tester.pumpAndSettle();

    expect(find.text('TUTORIAL 2 OF 5 · WEEK 3'), findsOneWidget);
    expect(find.text('6 min read'), findsOneWidget);
    expect(find.text('12 min practice'), findsOneWidget);
    expect(find.text('Open practice · 12 min'), findsOneWidget);

    const order = [
      'WHY THIS SKILL',
      'THE IDEA',
      'SEEING IT',
      'WORKED EXAMPLE',
      'COMMON ERRORS',
      'CHECK YOURSELF',
      'REFERENCES',
    ];
    final tops = [
      for (final label in order) tester.getTopLeft(find.text(label)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: order[i]);
    }
    // Native blocks land in their design sections.
    expect(find.byType(FormulaStack), findsOneWidget);
    expect(find.byType(WaterfallChart), findsOneWidget);
    expect(find.byType(WorkedSteps), findsOneWidget);
    expect(find.byType(QuickCheck), findsOneWidget);
    final seeing = tester.getTopLeft(find.text('SEEING IT')).dy;
    final example = tester.getTopLeft(find.text('WORKED EXAMPLE')).dy;
    final chart = tester.getTopLeft(find.byType(WaterfallChart)).dy;
    expect(chart, inExclusiveRange(seeing, example));
    // Common errors are ✕ cards; references are material rows.
    expect(find.text('Treating growth capex as maintenance.'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-error-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-error-1')), findsOneWidget);
    expect(find.text('Simon Sinek'), findsOneWidget);
    expect(find.text('Try it'), findsNothing);
    expect(find.text('TRY IT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toc_jumps_to_section', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_reader(_step()));
    await tester.pumpAndSettle();
    final scrollable = find.byKey(LessonReaderScreen.scrollKey);
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: scrollable, matching: find.byType(Scrollable)),
          )
          .position
          .pixels,
      0,
    );

    await tester.tap(find.bySemanticsLabel('Contents'));
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsWidgets);
    for (final label in const [
      'Why this skill',
      'The idea',
      'Seeing it',
      'Worked example',
      'Common errors',
      'Check yourself',
      'References',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Worked example'));
    await tester.pumpAndSettle();

    expect(find.text('Why this skill'), findsNothing); // the sheet closed
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.pixels, greaterThan(0));
    final heading = tester.getTopLeft(find.text('WORKED EXAMPLE')).dy;
    // The heading sits just below the top bar and progress bar.
    // The kicker row lands just under the top bar and progress bar (55 pt
    // here, plus an 8 pt gap), not 40 pt lower.
    expect(heading, inInclusiveRange(55, 75));
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme_switch_persists', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_reader(_step(), signedIn: true));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Reading settings'));
    await tester.pumpAndSettle();
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A++'));
    await tester.pumpAndSettle();
    // Past the store's debounced write.
    await tester.pump(const Duration(milliseconds: 400));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LessonReaderScreen)),
    );
    expect(container.read(cmpysStoreProvider).settings.readTheme, 'sepia');
    expect(container.read(cmpysStoreProvider).settings.readSize, 2);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs
        .getKeys()
        .map((key) => prefs.get(key).toString())
        .join();
    expect(stored, contains('"readTheme":"sepia"'));
    expect(stored, contains('"readSize":2'));

    // A fresh app session reads the persisted theme back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_reader(_step(), signedIn: true));
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(LessonReaderScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, ReaderTheme.sepia.bg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worked_steps_running_total', (tester) async {
    await tester.pumpWidget(
      _block('steps', '''
title: Acme Co.
Start from net income | 80 | The reported profit.
Add back D&A | 12 | A non-cash charge.
Subtract maintenance capex | -24 | Spending that keeps the lights on.
= Owner earnings | 68
'''),
    );
    await tester.pumpAndSettle();

    String total() =>
        tester.widget<Text>(find.byKey(WorkedSteps.runningTotalKey)).data!;
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(total(), '80');
    expect(find.text('Add back D&A'), findsNothing);

    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(total(), '92');

    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('−24'), findsOneWidget);
    expect(total(), '68');
    expect(find.text('Next step'), findsNothing);
    expect(find.text('Owner earnings: 68'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick_check_multi_requires_all_correct', (tester) async {
    const body = '''
Q: Which belong in owner earnings?
- [x] Net income
- [x] D&A add-back
- [ ] Growth capex
Why: Growth capex is optional spending.
''';
    Future<void> attempt(List<String> picks, String verdict) async {
      await tester.pumpWidget(_block('check', body, key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(find.text('Select all that apply'), findsOneWidget);
      for (final pick in picks) {
        await tester.tap(find.text(pick));
        await tester.pump();
      }
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.textContaining(verdict), findsOneWidget, reason: '$picks');
      expect(find.text('Quick checks aren’t graded.'), findsOneWidget);
      expect(
        find.textContaining('Growth capex is optional spending.'),
        findsOneWidget,
      );
    }

    await attempt(['Net income'], 'Not quite.');
    await attempt(['Net income', 'D&A add-back', 'Growth capex'], 'Not quite.');
    await attempt(['Net income', 'D&A add-back'], 'Right.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick_check_numeric_tolerance', (tester) async {
    const body = '''
Q: What are the owner earnings?
answer: 68 | unit: \$m | tolerance: 0.5
Why: 80 plus 12 minus 24.
''';
    Future<void> attempt(String typed, String verdict) async {
      await tester.pumpWidget(_block('check', body, key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(find.text(r'$m'), findsOneWidget);
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.textContaining(verdict), findsOneWidget, reason: typed);
      expect(find.text('Quick checks aren’t graded.'), findsOneWidget);
    }

    await attempt('68.4', 'Right.');
    await attempt('67,5', 'Right.'); // comma decimal, at the tolerance edge
    await attempt('68.6', 'Not quite.');
    await attempt('70', 'Not quite.');

    // Nothing typed (or not a number): the check cannot run.
    await tester.pumpWidget(_block('check', body, key: UniqueKey()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(find.text('Quick checks aren’t graded.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed_fence_renders_plain_lines', (tester) async {
    await _phone(tester);
    const broken = '''
## Why This Matters
Why it matters.

## Core Framework
The idea prose stays.

```formula
title: Owner earnings
+ Net income
- Maintenance capex
```

## Worked Example
Example prose.

```steps
title: Acme
Only one step | 80 | note
```
''';
    await tester.pumpWidget(_reader(_step(content: broken)));
    await tester.pumpAndSettle();

    expect(find.byType(FormulaStack), findsNothing);
    expect(find.byType(WorkedSteps), findsNothing);
    // The prose still shows and each fence line shows as a plain line.
    expect(find.text('The idea prose stays.'), findsOneWidget);
    expect(find.text('Example prose.'), findsOneWidget);
    expect(find.text('title: Owner earnings'), findsOneWidget);
    expect(find.text('+ Net income'), findsOneWidget);
    expect(find.text('- Maintenance capex'), findsOneWidget);
    expect(find.text('Only one step | 80 | note'), findsOneWidget);
    expect(find.text('SEEING IT'), findsOneWidget);

    // The same routing outside the reader.
    await tester.pumpWidget(_block('chart', 'type: pie\ntitle: T\nA | 1'));
    await tester.pumpAndSettle();
    expect(find.byType(WaterfallChart), findsNothing);
    expect(find.text('type: pie'), findsOneWidget);
    expect(find.text('A | 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy_lesson_shows_try_it', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_reader(_step(content: _legacy)));
    await tester.pumpAndSettle();

    expect(find.text('TRY IT'), findsOneWidget);
    expect(
      find.text('Write one observation and a test of your own.'),
      findsOneWidget,
    );
    final errors = tester.getTopLeft(find.text('COMMON ERRORS')).dy;
    final tryIt = tester.getTopLeft(find.text('TRY IT')).dy;
    final check = tester.getTopLeft(find.text('CHECK YOURSELF')).dy;
    expect(tryIt, inExclusiveRange(errors, check));
    // The legacy diagram renders natively inside "Seeing it".
    expect(find.byType(LearningDiagramView), findsOneWidget);
    final seeing = tester.getTopLeft(find.text('SEEING IT')).dy;
    final example = tester.getTopLeft(find.text('WORKED EXAMPLE')).dy;
    final diagram = tester.getTopLeft(find.byType(LearningDiagramView)).dy;
    expect(diagram, inExclusiveRange(seeing, example));

    await tester.tap(find.bySemanticsLabel('Contents'));
    await tester.pumpAndSettle();
    expect(find.text('Try it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no_illustration_no_hero', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_reader(_step()));
    await tester.pumpAndSettle();
    expect(find.byType(IllustrationHero), findsNothing);
    expect(find.text('Illustration · AI-generated'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _reader(
        _step(
          illustration: const TutorialIllustration(
            url: '/media/tutorials/owner.png',
            alt: 'A ledger turning into a stream of coins',
            provider: 'gemini_imagen',
            aspect: '16:9',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(IllustrationHero), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'A ledger turning into a stream of coins. Illustration · AI-generated',
      ),
      findsOneWidget,
    );
    final hero = tester.getSize(find.byKey(IllustrationHero.frameKey));
    expect(hero.width / hero.height, closeTo(16 / 9, 0.01));
    // The test HTTP client fails every image: the hero collapses rather than
    // showing a broken image, and the tutorial still reads.
    await tester.pumpAndSettle();
    expect(find.byKey(IllustrationHero.frameKey), findsNothing);
    expect(find.text('Illustration · AI-generated'), findsNothing);
    expect(find.text('WHY THIS SKILL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the Next step pacing', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _block('steps', '''
title: Acme Co.
Start | 80 | a
Add | 12 | b
= Total | 92
'''),
      ),
    );
    await tester.pump();
    String total() =>
        tester.widget<Text>(find.byKey(WorkedSteps.runningTotalKey)).data!;
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(total(), '80');
    expect(find.text('Next step'), findsOneWidget);
    expect(find.text('Total: 92'), findsNothing);

    await tester.tap(find.text('Next step'));
    // No rise animation: the step is in place on the very next frame.
    await tester.pump();
    expect(
      find.ancestor(of: find.text('Add'), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(total(), '92');
    expect(find.text('Total: 92'), findsOneWidget);
    expect(find.text('Next step'), findsNothing);
  });

  testWidgets('all steps shown: the stated total, not a mixed-precision sum', (
    tester,
  ) async {
    await tester.pumpWidget(
      _block('steps', '''
title: Rounding
A | 12.5 | n
B | 3.33 | n
= Total | 15.88
'''),
    );
    await tester.pumpAndSettle();
    String total() =>
        tester.widget<Text>(find.byKey(WorkedSteps.runningTotalKey)).data!;
    expect(total(), '12.50');
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    // 12.5 + 3.33 sums to 15.83; the fence states 15.88 (within rounding).
    expect(total(), '15.88');
    expect(find.text('Total: 15.88'), findsOneWidget);
  });

  testWidgets('formula and chart stay hidden until scrolled into view, once', (
    tester,
  ) async {
    await _phone(tester);
    final spacer = ValueNotifier<double>(1200);
    addTearDown(spacer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: spacer,
                  builder: (context, height, _) => SizedBox(height: height),
                ),
                const LessonFenceBlock(
                  kind: 'formula',
                  body: 'title: Owner earnings\n= Owner earnings\n+ Net income',
                ),
                const LessonFenceBlock(
                  kind: 'chart',
                  body:
                      'type: waterfall\ntitle: T\nNet | 80\nD&A | 12\n= Owner | 92',
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double opacity(String text) => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(opacity('Net income'), 0);
    expect(opacity('+12'), 0);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(opacity('Net income'), 1);
    expect(opacity('+12'), 1);

    // Revealed once: scrolling away and back does not hide or replay them.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pump();
    expect(opacity('Net income'), 1);
    expect(opacity('+12'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a layout shift with no scroll still reveals a block', (
    tester,
  ) async {
    await _phone(tester);
    final spacer = ValueNotifier<double>(1200);
    addTearDown(spacer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: spacer,
                  builder: (context, height, _) => SizedBox(height: height),
                ),
                const LessonFenceBlock(
                  kind: 'formula',
                  body: 'title: T\n= Owner earnings\n+ Net income',
                ),
                const SizedBox(height: 400),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double opacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.text('Net income'),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(opacity(), 0);
    // Content above collapses (like a failed hero image): no scroll event.
    spacer.value = 100;
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });

  testWidgets('single choice: one tap answers; wrong shakes, right pops', (
    tester,
  ) async {
    const body = '''
Q: What are the owner earnings here?
- [ ] 80
- [x] 68
- [ ] 92
- [ ] 56
Why: 80 plus 12 minus 24 is 68.
''';
    await tester.pumpWidget(_block('check', body, key: UniqueKey()));
    await tester.pumpAndSettle();
    expect(find.text('Quick checks aren’t graded.'), findsNothing);

    await tester.tap(find.text('80'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.textContaining('Not quite.'), findsOneWidget);
    final shake = find.byKey(QuickCheck.shakeKey);
    expect(
      find.descendant(of: shake, matching: find.text('80')),
      findsOneWidget,
    );
    final turned = tester.widget<Transform>(
      find.descendant(of: shake, matching: find.byType(Transform)).first,
    );
    expect(turned.transform.isIdentity(), isFalse);
    // The right option is revealed with the pop.
    expect(
      find.ancestor(of: find.text('68'), matching: find.byType(V3Pop)),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    // Only one answer: later taps change nothing.
    await tester.tap(find.text('92'));
    await tester.tap(find.text('68'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not quite.'), findsOneWidget);
    expect(find.textContaining('Right.'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('92'),
        matching: find.byKey(QuickCheck.shakeKey),
      ),
      findsNothing,
    );

    await tester.pumpWidget(_block('check', body, key: UniqueKey()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('68'));
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.textContaining('Right.'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('68'), matching: find.byType(V3Pop)),
      findsOneWidget,
    );
    expect(find.byKey(QuickCheck.shakeKey), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Quick checks aren’t graded.'), findsOneWidget);
  });

  group('typed numbers', () {
    test('every reading of a typed number', () {
      expect(checkNumberReadings('4,5'), [4.5]);
      expect(checkNumberReadings('4.5'), [4.5]);
      expect(checkNumberReadings('1,250'), [1250, 1.25]);
      expect(checkNumberReadings('1,250.5'), [1250.5]);
      expect(checkNumberReadings('1.250,5'), [1250.5]);
      expect(checkNumberReadings('1,250,000'), [1250000]);
      expect(checkNumberReadings('−3'), [-3]);
      expect(checkNumberReadings('-1,250'), [-1250, -1.25]);
      expect(checkNumberReadings(' 68 '), [68]);
      expect(checkNumberReadings(''), isEmpty);
      expect(checkNumberReadings('-'), isEmpty);
      expect(checkNumberReadings('abc'), isEmpty);
      expect(checkNumberReadings('1,2,3'), isEmpty);
    });

    test('thousands groups need a 1–3 digit lead with no leading zero', () {
      expect(checkNumberReadings('1,250'), [1250, 1.25]);
      expect(checkNumberReadings('999,999'), [999999, 999.999]);
      // Not a valid thousands group: the comma is a decimal comma.
      expect(checkNumberReadings('0,500'), [0.5]);
      expect(checkNumberReadings('1234,567'), [1234.567]);
      expect(checkNumberReadings('01,250'), [1.25]);
      // The same lead rule for the grouped forms.
      expect(checkNumberReadings('12,345,678.5'), [12345678.5]);
      expect(checkNumberReadings('0,250,000'), isEmpty);
      expect(checkNumberReadings('1234,567,000'), isEmpty);
      expect(checkNumberReadings('1.234.567,5'), [1234567.5]);
      expect(checkNumberReadings('0.250.000,5'), isEmpty);
    });

    testWidgets('"1,250" is right for 1250 and for 1.25', (tester) async {
      Future<void> attempt(String answer, String typed, String verdict) async {
        await tester.pumpWidget(
          _block(
            'check',
            'Q: How much?\nanswer: $answer | unit: | tolerance: 0\nWhy: Because.',
            key: UniqueKey(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump();
        await tester.tap(find.text('Check'));
        await tester.pumpAndSettle();
        expect(find.textContaining(verdict), findsOneWidget, reason: typed);
      }

      await attempt('1250', '1,250', 'Right.');
      await attempt('1.25', '1,250', 'Right.');
      await attempt('1250.5', '1.250,5', 'Right.');
      await attempt('1250.5', '1,250.5', 'Right.');
      await attempt('-3', '−3', 'Right.');
      await attempt('1250', '1,251', 'Not quite.');
    });

    testWidgets('empty input cannot be checked', (tester) async {
      await tester.pumpWidget(
        _block(
          'check',
          'Q: How much?\nanswer: 5 | unit: | tolerance: 0\nWhy: W.',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Quick checks aren’t graded.'), findsNothing);
    });
  });

  testWidgets('references: matched rows, unmatched lines kept as prose', (
    tester,
  ) async {
    await _phone(tester);
    const content = '''
## Why This Matters
Why.

## References
These deepen the lesson.

- **Start With Why** by Simon Sinek — the golden circle behind purpose.
- **The Lean Startup** — adds the build-measure-learn loop
  for testing a purpose quickly.
''';
    await tester.pumpWidget(_reader(_step(content: content)));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialRow), findsOneWidget);
    expect(find.text('Start With Why'), findsOneWidget); // the row title
    expect(find.textContaining('golden circle'), findsNothing);
    expect(find.textContaining('These deepen the lesson.'), findsOneWidget);
    expect(find.textContaining('The Lean Startup'), findsOneWidget);
    expect(
      find.textContaining('adds the build-measure-learn loop'),
      findsOneWidget,
    );
    expect(
      find.textContaining('for testing a purpose quickly.'),
      findsOneWidget,
    );
    final row = tester.getTopLeft(find.byType(MaterialRow)).dy;
    final unmatched = tester
        .getTopLeft(find.textContaining('The Lean Startup'))
        .dy;
    expect(unmatched, greaterThan(row));
    expect(tester.takeException(), isNull);
  });

  test('a reference item naming an unmatched resource is kept', () {
    const markdown = '''
- Start With Why and The Lean Startup both test a purpose.
- **Start With Why** — the golden circle.''';
    final rest = unmatchedReferenceMarkdown(
      markdown,
      const [PlanMaterialDetail(title: 'Start With Why')],
      otherTitles: const ['Start With Why', 'The Lean Startup'],
    );
    expect(rest, contains('both test a purpose.'));
    expect(rest, isNot(contains('golden circle')));
  });

  test('a short material title only matches a whole item', () {
    const markdown = '''
- Deep Work — builds focus for long sessions.
- **Focus**
- Focus''';
    final rest = unmatchedReferenceMarkdown(markdown, const [
      PlanMaterialDetail(title: 'Focus'),
    ]);
    expect(rest, contains('Deep Work — builds focus for long sessions.'));
    expect(rest, isNot(contains('**Focus**')));
    expect(rest.split('\n').where((line) => line.trim() == '- Focus'), isEmpty);
    // A two-word title of eight characters or more matches inside a line.
    expect(
      unmatchedReferenceMarkdown('- Read Deep Work this week.', const [
        PlanMaterialDetail(title: 'Deep Work'),
      ]),
      isEmpty,
    );
    // Two words but under eight characters: whole item only.
    expect(
      unmatchedReferenceMarkdown('- Go Big today.', const [
        PlanMaterialDetail(title: 'Go Big'),
      ]),
      '- Go Big today.',
    );
  });

  test('unmatched reference markdown keeps everything but matched items', () {
    const markdown = '''
Intro.
- **Start With Why** — matched.
- Other book — kept
  with its continuation.

Outro.''';
    final rest = unmatchedReferenceMarkdown(markdown, const [
      PlanMaterialDetail(title: 'Start With Why'),
    ]);
    expect(rest, isNot(contains('matched.')));
    expect(rest, contains('Intro.'));
    expect(rest, contains('- Other book — kept\n  with its continuation.'));
    expect(rest, contains('\n\nOutro.'));
    expect(unmatchedReferenceMarkdown(markdown, const []), markdown.trim());
  });

  test('step illustration parses from the step JSON and is optional', () {
    final step = PlanStepDetail.fromJson({
      'id': 's1',
      'title': 'T',
      'illustration': {
        'url': '/media/tutorials/a.png',
        'alt': 'Alt text',
        'provider': 'gemini_imagen',
        'aspect': '16:9',
      },
    });
    expect(step.illustration!.url, '/media/tutorials/a.png');
    expect(step.illustration!.alt, 'Alt text');
    expect(step.illustration!.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(PlanStepDetail.fromJson({'id': 's1'}).illustration, isNull);
    expect(
      PlanStepDetail.fromJson({
        'id': 's1',
        'illustration': {'url': ''},
      }).illustration,
      isNull,
    );
    expect(
      PlanStepDetail.fromJson({
        'id': 's1',
        'illustration': 'nope',
      }).illustration,
      isNull,
    );
  });

  testWidgets('completed tutorial shows Completed and review CTA', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_reader(_step(), completed: true));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Review practice & attempts'), findsOneWidget);
    expect(find.text('Open practice · 12 min'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
