import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_markdown.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/presentation/record_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CompareStore extends CmpysStore {
  _CompareStore({
    Map<String, dynamic>? scores,
    String? perspective,
    int age = 24,
  }) {
    state = state.copyWith(
      sessionId: 'session-1',
      idol: cmpysIdols.first, // Warren Buffett
      user: CmpysUser(name: 'Ana', age: age),
      comparisonMd: perspective,
      liveComparisonScores: scores,
    );
  }
}

Map<String, dynamic> _dim(
  String id,
  String label,
  String status, {
  int? you,
  int? idol,
  String youNote = '',
  String idolNote = '',
  String basis = '',
}) => {
  'id': id,
  'label': label,
  'status': status,
  'you': you,
  'idol': idol,
  'comparison_basis': basis,
  'you_evidence': status == 'comparable' ? 'self_reported' : 'none',
  'idol_evidence': 'documented',
  'you_note': youNote,
  'idol_note': idolNote,
};

Map<String, dynamic> _v2Scores() => {
  'version': 2,
  'methodology': 'like_for_like_evidence',
  'overall': {'status': 'not_combined', 'you': null, 'idol': null},
  'dimensions': [
    _dim(
      'capital',
      'Capital at work',
      'different_basis',
      basis: 'Personal savings versus business capital raised.',
    ),
    _dim('knowledge', 'Knowledge base', 'comparable', you: 40, idol: 80),
    _dim('habits', 'Daily discipline', 'comparable', you: 30, idol: 70),
    _dim('network', 'Trusted network', 'insufficient_user_evidence'),
    _dim('clarity', 'Strategic clarity', 'insufficient_idol_evidence'),
  ],
  'milestones': <Map<String, dynamic>>[],
};

Map<String, dynamic> _v3Scores() => {
  'version': 3,
  'methodology': 'like_for_like_evidence',
  'overall': {'status': 'not_combined', 'you': null, 'idol': null},
  'dimensions': [
    _dim(
      'knowledge',
      'Knowledge base',
      'comparable',
      you: 34,
      idol: 78,
      youNote: 'Three tutorials passed; two books started.',
      idolNote: 'Had read The Intelligent Investor by 21.',
      basis: 'Book counts from biography are approximate.',
    ),
    _dim('practice', 'Practice volume', 'comparable', you: 22, idol: 70),
    _dim(
      'capital',
      'Capital & resources',
      'different_basis',
      youNote: 'You shared no savings figure.',
      idolNote: 'Biographers estimate about \$9,800 saved by 1951.',
      basis: 'Different era and money.',
    ),
    _dim(
      'network',
      'Network',
      'insufficient_user_evidence',
      basis: 'Log one mentor conversation to make this comparable.',
    ),
    _dim('judgment', 'Written judgment', 'insufficient_idol_evidence'),
  ],
  'milestones': <Map<String, dynamic>>[],
};

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? scores,
  String? perspective,
  int age = 24,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith(
          (ref) =>
              _CompareStore(scores: scores, perspective: perspective, age: age),
        ),
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        cmpysComparisonScoresSyncProvider.overrideWith(
          (ref) async => ComparisonScoresSyncResult.ready,
        ),
        // "Your record" opens the Record, which reads the mentor timeline.
        idolTimelineProvider.overrideWith((ref, name) async => const []),
      ],
      child: const MaterialApp(home: CmpysCompareScreen()),
    ),
  );
  await tester.pump();
  // Delayed count-ups start on a timer, then tick on the following frames.
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 2));
}

String _headline(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('compare-headline')))
    .textSpan!
    .toPlainText();

Future<void> _openRow(WidgetTester tester, String label) async {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byKey(const ValueKey('compare-dim-row')),
  );
  await tester.ensureVisible(row.first);
  await tester.tap(row.first);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 500));
}

final _sheet = find.byKey(V3Sheet.panelKey);

Finder _inSheet(Finder matching) =>
    find.descendant(of: _sheet, matching: matching);

Future<void> _closeSheet(WidgetTester tester) async {
  Navigator.of(tester.element(_sheet)).pop();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('v2_payload_renders_with_server_labels', (tester) async {
    // The store reader keeps v2 payloads and their legacy ids.
    final dims = dimsFromScores(_v2Scores());
    expect(dims, isNotNull);
    expect(dims!.map((d) => d.id), contains('habits'));

    await _pump(tester, scores: _v2Scores());

    for (final label in const [
      'Capital at work',
      'Knowledge base',
      'Daily discipline',
      'Trusted network',
      'Strategic clarity',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Ids are never shown, and no hard-coded short names replace labels.
    expect(find.text('habits'), findsNothing);
    expect(find.text('Discipline'), findsNothing);
    expect(find.text('Clarity'), findsNothing);
    expect(find.text('Like for like'), findsNWidgets(2));
    expect(find.text('Not comparable'), findsOneWidget);
    expect(find.text('Evidence missing'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('v3_payload_counts_comparable', (tester) async {
    expect(dimsFromScores(_v3Scores()), hasLength(5));

    await _pump(tester, scores: _v3Scores());

    expect(
      tester
          .widget<Text>(find.byKey(const Key('compare-comparable-count')))
          .data,
      '2',
    );
    expect(find.text('of 5 dimensions compared like for like'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compare-segment-solid')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('compare-segment-dashed')),
      findsNWidgets(3),
    );
    expect(
      find.text(
        'Dimensions without comparable evidence are left unscored. '
        'That’s not a zero.',
      ),
      findsOneWidget,
    );
    expect(find.text('Like for like'), findsNWidgets(2));
    expect(find.text('Not comparable'), findsOneWidget);
    expect(find.text('Evidence missing'), findsNWidgets(2));
    // Comparable rows carry both bars; the others carry none.
    expect(find.text('You'), findsNWidgets(2));
    expect(find.text('Buffett at 24'), findsNWidgets(2));
    // Non-comparable rows show the uncertainty line instead of zero bars.
    expect(find.text('Different era and money.'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v3 total follows the payload, not a fixed five', (tester) async {
    final scores = _v3Scores();
    scores['dimensions'] = (scores['dimensions'] as List).take(3).toList();
    await _pump(tester, scores: scores);
    expect(find.text('of 3 dimensions compared like for like'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compare-segment-dashed')),
      findsOneWidget,
    );
  });

  testWidgets('dim_sheet_uncertainty_copy', (tester) async {
    await _pump(tester, scores: _v3Scores());

    await _openRow(tester, 'Knowledge base');
    expect(_sheet, findsOneWidget);
    expect(_inSheet(find.text('Like for like')), findsOneWidget);
    // The two score boxes: you and the mentor, with their values.
    expect(
      _inSheet(find.byKey(const ValueKey('compare-score-box'))),
      findsNWidgets(2),
    );
    expect(_inSheet(find.text('You')), findsOneWidget);
    expect(_inSheet(find.text('Buffett')), findsOneWidget);
    expect(_inSheet(find.text('34')), findsOneWidget);
    expect(_inSheet(find.text('78')), findsOneWidget);
    expect(_inSheet(find.text('Your evidence')), findsOneWidget);
    expect(
      _inSheet(find.text('Three tutorials passed; two books started.')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Buffett at 24')), findsOneWidget);
    expect(
      _inSheet(find.text('Had read The Intelligent Investor by 21.')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Uncertainty')), findsOneWidget);
    expect(_inSheet(find.text('Why there’s no score')), findsNothing);
    expect(
      _inSheet(find.text('Book counts from biography are approximate.')),
      findsOneWidget,
    );
    expect(
      _inSheet(
        find.text(
          'Scores show evidence on a shared scale for this dimension only. '
          'They don’t rank overall ability.',
        ),
      ),
      findsOneWidget,
    );
    await _closeSheet(tester);

    await _openRow(tester, 'Capital & resources');
    expect(_inSheet(find.text('Not comparable')), findsOneWidget);
    expect(_inSheet(find.text('Why there’s no score')), findsOneWidget);
    expect(_inSheet(find.text('Uncertainty')), findsNothing);
    expect(
      _inSheet(find.byKey(const ValueKey('compare-score-box'))),
      findsNothing,
    );
    expect(
      _inSheet(find.text('You shared no savings figure.')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Different era and money.')), findsOneWidget);
    await _closeSheet(tester);

    // A dimension with no notes and no basis omits those sections.
    await _openRow(tester, 'Written judgment');
    expect(_inSheet(find.text('Evidence missing')), findsOneWidget);
    expect(_inSheet(find.text('Your evidence')), findsNothing);
    expect(_inSheet(find.text('Buffett at 24')), findsNothing);
    expect(_inSheet(find.text('Why there’s no score')), findsNothing);
    expect(_inSheet(find.text('Uncertainty')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('scorer shorthand reads as plain words (F12)', () {
    test('known enums and shorthand map to plain words', () {
      String plain(String text) => plainComparisonText(text, mentor: 'Buffett');
      expect(
        plain('Your evidence: diagnostics marked needs_review, confidence 2 '
            'of 5.'),
        'Your evidence: diagnostics marked needs a closer review, confidence '
        '2 of 5.',
      );
      expect(
        plain('valuation knowledge; Buffett facts at 24 not supplied'),
        'valuation knowledge; no verified record of Buffett at 24 for this '
        'yet',
      );
      expect(
        plain('Warren Buffett facts at 24 not supplied.'),
        'No verified record of Warren Buffett at 24 for this yet.',
      );
      expect(
        plain('The relevant learner input has not been established.'),
        'You haven’t shared this yet.',
      );
      expect(
        plain('Status insufficient_idol_evidence; status different_basis.'),
        'Status not enough documented evidence about Buffett; status not '
        'comparable.',
      );
      expect(
        plain('Marked needs_practice_on_item, correct_on_item, not_assessed '
            'and insufficient_user_evidence.'),
        'Marked needs practice on this skill, correct on this check, not '
        'checked yet and not enough of your evidence.',
      );
      // Field names and any other snake_case token lose their underscores.
      expect(
        plain('From learner_diagnostics and missing_evidence_keys: '
            'goal_specific_sample, some_new_value.'),
        'From starting checks and missing answers: your work example, some '
        'new value.',
      );
      // Ordinary prose, numbers and links are left alone.
      for (final text in [
        'Had read The Intelligent Investor by 21.',
        'Saved about \$9,800 by 1951 (see https://example.com/a_b).',
        '',
      ]) {
        expect(plain(text), text);
      }
    });

    testWidgets('rows and the sheet never show the scorer’s raw strings', (
      tester,
    ) async {
      final scores = _v3Scores();
      scores['dimensions'] = [
        _dim(
          'knowledge',
          'Knowledge base',
          'insufficient_idol_evidence',
          youNote: 'Your evidence: diagnostics marked needs_review, '
              'confidence 2 of 5.',
          idolNote: 'Buffett facts at 24 not supplied',
          basis: 'valuation knowledge; Buffett facts at 24 not supplied',
        ),
        _dim(
          'capital',
          'Capital & resources',
          'insufficient_user_evidence',
          basis: 'The relevant learner input has not been established.',
        ),
      ];
      await _pump(tester, scores: scores);
      expect(
        find.text(
          'valuation knowledge; no verified record of Buffett at 24 for '
          'this yet',
        ),
        findsOneWidget,
      );
      expect(find.text('You haven’t shared this yet.'), findsOneWidget);
      expect(find.textContaining('not supplied'), findsNothing);
      expect(find.textContaining('not been established'), findsNothing);

      await _openRow(tester, 'Knowledge base');
      expect(
        _inSheet(
          find.text(
            'Your evidence: diagnostics marked needs a closer review, '
            'confidence 2 of 5.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        _inSheet(find.text('No verified record of Buffett at 24 for this yet')),
        findsOneWidget,
      );
      expect(_inSheet(find.textContaining('needs_review')), findsNothing);
      expect(_inSheet(find.textContaining('not supplied')), findsNothing);
    });
  });

  testWidgets('unknown status shows Evidence missing', (tester) async {
    final scores = _v3Scores();
    scores['dimensions'] = [
      _dim('knowledge', 'Knowledge base', 'some_future_status'),
    ];
    await _pump(tester, scores: scores);
    expect(find.text('Evidence missing'), findsOneWidget);
    expect(find.text('Like for like'), findsNothing);
    expect(find.text('Not comparable'), findsNothing);
  });

  testWidgets('headline names the mentor and the shared age', (tester) async {
    await _pump(tester, scores: _v3Scores());
    expect(_headline(tester), 'You and Buffett,\nboth at 24.');
    expect(find.byKey(const Key('compare-age-disc')), findsOneWidget);
  });

  testWidgets('unknown age drops "both at age"', (tester) async {
    await _pump(tester, scores: _v3Scores(), age: 0);
    final headline = _headline(tester);
    expect(headline, contains('You and Buffett'));
    expect(headline, isNot(contains('both at')));
    expect(headline, isNot(contains('0')));
    expect(find.byKey(const Key('compare-age-disc')), findsNothing);
    expect(find.text('Buffett at 0'), findsNothing);
    expect(find.text('Buffett'), findsWidgets);
  });

  testWidgets('no perspective hides the Written perspective card', (
    tester,
  ) async {
    await _pump(tester, scores: _v3Scores());
    expect(find.text('Written perspective'), findsNothing);
    expect(find.byKey(const Key('compare-perspective-card')), findsNothing);
  });

  testWidgets('perspective card opens the full sheet with the disclaimer', (
    tester,
  ) async {
    const markdown =
        'At 24, Buffett was a **relentless** reader.\n\n'
        '---\n\n'
        'You are earlier on that path, and that is not a verdict.';
    await _pump(tester, scores: _v3Scores(), perspective: markdown);
    final card = find.byKey(const Key('compare-perspective-card'));
    expect(card, findsOneWidget);
    expect(find.text('Read in full'), findsOneWidget);
    // The preview is plain and clamped.
    final preview = tester.widget<Text>(
      find.descendant(
        of: card,
        matching: find.text('At 24, Buffett was a relentless reader.'),
      ),
    );
    expect(preview.maxLines, 5);
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The sheet renders the markdown itself, in the light reading theme.
    final body = tester.widget<CmpysMarkdown>(
      _inSheet(find.byType(CmpysMarkdown)),
    );
    expect(body.data, markdown);
    expect(body.readerTheme, ReaderTheme.light);
    expect(body.fontSize, 16.5);
    expect(body.lineHeight, 1.65);
    // Emphasis survives as a bold span.
    final spans = <TextSpan>[];
    for (final text in tester.widgetList<RichText>(
      _inSheet(find.byType(RichText)),
    )) {
      text.text.visitChildren((span) {
        if (span is TextSpan) spans.add(span);
        return true;
      });
    }
    final bold = spans.where((span) => span.text == 'relentless');
    expect(bold, isNotEmpty);
    expect(bold.first.style?.fontWeight, FontWeight.w600);
    expect(
      _inSheet(
        find.text(
          'You are earlier on that path, and that is not a verdict.',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inSheet(
        find.text(
          'Written by an AI interpretation of Warren Buffett. Historical claims '
          'come from cited biographies; treat them as reported, not certain.',
        ),
      ),
      findsOneWidget,
    );
  });

  group('perspective preview cleanup', () {
    test('blank input gives no paragraphs', () {
      expect(perspectiveParagraphs(null), isEmpty);
      expect(perspectiveParagraphs('  \n '), isEmpty);
    });

    test('headings, quotes and bold markers are dropped', () {
      expect(
        perspectiveParagraphs(
          '## From Buffett\n\nAt 24 I **read** everything.\nI wrote notes.'
          '\n\n> *Not a verdict.*',
        ),
        ['At 24 I read everything. I wrote notes.', 'Not a verdict.'],
      );
    });

    test('rule lines are dropped', () {
      expect(perspectiveParagraphs('First.\n\n---\n\nSecond.\n***\n___'), [
        'First.',
        'Second.',
      ]);
    });

    test('links and images unwrap to their text', () {
      expect(
        perspectiveParagraphs(
          'Read [the 1951 letter](https://example.com/letter) and '
          '![a chart](chart.png) twice.',
        ),
        ['Read the 1951 letter and a chart twice.'],
      );
    });

    test('underscore emphasis and inline code are unwrapped', () {
      expect(
        perspectiveParagraphs(
          'Keep _one_ __ledger__ of `cash_flow` and snake_case names.',
        ),
        ['Keep one ledger of cash_flow and snake_case names.'],
      );
    });

    test('a literal asterisk inside text is kept', () {
      expect(perspectiveParagraphs('Work out 5 * 3 and 2*4, *then* rest.'), [
        'Work out 5 * 3 and 2*4, then rest.',
      ]);
    });
  });

  group('store readers', () {
    test('v3 milestones are read', () {
      final milestones = milestonesFromScores({
        'version': 3,
        'methodology': 'like_for_like_evidence',
        'milestones': [
          {'id': 'm1', 'label': 'Wrote a first company note'},
          {'text': 'Read an annual report'},
        ],
      });
      expect(milestones, isNotNull);
      expect(milestones!.map((m) => m.id), ['m1', 'm2']);
      expect(milestones.last.label, 'Read an annual report');
    });

    test('a blank or absent label falls back to the id', () {
      final dims = dimsFromScores({
        'version': 3,
        'methodology': 'like_for_like_evidence',
        'dimensions': [
          _dim('knowledge', '   ', 'comparable', you: 40, idol: 80),
          _dim('network', 'x', 'comparable')..remove('label'),
        ],
      });
      expect(dims!.map((d) => d.label), ['knowledge', 'network']);
    });

    test('a wrong-typed score reads as no score', () {
      final dims = dimsFromScores({
        'version': 3,
        'methodology': 'like_for_like_evidence',
        'dimensions': [
          {
            ..._dim('knowledge', 'Knowledge base', 'comparable'),
            'you': '40',
            'idol': true,
          },
          _dim('practice', 'Practice volume', 'comparable', you: 22, idol: 70),
        ],
      });
      expect(dims, hasLength(2));
      expect(dims!.first.you, isNull);
      expect(dims.first.idol, isNull);
      expect(dims.first.isComparable, isFalse);
      expect(dims.last.you, 22);
    });

    testWidgets('a wrong-typed score renders as Evidence missing', (
      tester,
    ) async {
      final scores = _v3Scores();
      scores['dimensions'] = [
        {
          ..._dim('knowledge', 'Knowledge base', 'comparable'),
          'you': '40',
          'idol': 78.5,
        },
      ];
      await _pump(tester, scores: scores);
      expect(find.text('Evidence missing'), findsOneWidget);
      expect(find.text('Like for like'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    testWidgets('the headline is a header', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, scores: _v3Scores());
      expect(
        tester.getSemantics(find.byKey(const Key('compare-headline'))),
        containsSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('each bar reads its value out of 100 in the row label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, scores: _v3Scores());
      // The bar rows merge into the tappable dimension row's label.
      final row = tester.getSemantics(
        find
            .ancestor(
              of: find.text('Knowledge base'),
              matching: find.byKey(const ValueKey('compare-dim-row')),
            )
            .first,
      );
      expect(row.label, contains('Knowledge base'));
      expect(row.label, contains('You: 34 out of 100'));
      expect(row.label, contains('Buffett at 24: 78 out of 100'));
      expect(
        find.bySemanticsLabel(RegExp('You: 22 out of 100')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('a one-dimension payload reads "of 1 dimension"', (tester) async {
    final scores = _v3Scores();
    scores['dimensions'] = (scores['dimensions'] as List).take(1).toList();
    await _pump(tester, scores: scores);
    expect(find.text('of 1 dimension compared like for like'), findsOneWidget);
  });

  group('V3Pop delay', () {
    Finder popOpacity() => find.ancestor(
      of: find.byKey(const Key('popped')),
      matching: find.byType(Opacity),
    );

    Future<void> pumpPop(WidgetTester tester, {bool reduced = false}) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: V3Pop(
                delay: Duration(milliseconds: 450),
                child: SizedBox(key: Key('popped'), width: 10, height: 10),
              ),
            ),
          ),
        );

    testWidgets('stays hidden until the delay passes', (tester) async {
      await pumpPop(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Opacity>(popOpacity()).opacity, 0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Opacity>(popOpacity()).opacity, 1);
    });

    testWidgets('reduced motion shows the child at once', (tester) async {
      await pumpPop(tester, reduced: true);
      expect(popOpacity(), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets('Your record opens the Record screen', (tester) async {
    await _pump(tester, scores: _v3Scores());
    final button = find.text('Your record');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CmpysRecordScreen), findsOneWidget);
  });

  testWidgets('Plan goes to the Plan tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/compare',
      routes: [
        GoRoute(
          path: '/compare',
          builder: (_, _) => const CmpysCompareScreen(),
        ),
        GoRoute(
          path: AppRoutes.plan,
          builder: (_, _) => const Text('plan-tab'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysStoreProvider.overrideWith(
            (ref) => _CompareStore(scores: _v3Scores()),
          ),
          cmpysBackendSyncProvider.overrideWith((ref) async {}),
          cmpysComparisonScoresSyncProvider.overrideWith(
            (ref) async => ComparisonScoresSyncResult.ready,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final button = find.text('Plan');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('plan-tab'), findsOneWidget);
  });
}
