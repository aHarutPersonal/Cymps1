import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/presentation/record_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_practice_screen.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Task D6: the v3 practice workbook (design `v3/practice.jsx`).

Map<String, dynamic> _field(
  String id,
  String label,
  String kind, {
  String unit = '',
  String? prefix,
  List<List<String>> choices = const [],
  String? criterion,
}) => {
  'id': id,
  'label': label,
  'kind': kind,
  'unit': unit,
  if (prefix != null) 'prefix': prefix,
  'choices': [
    for (final c in choices) {'id': c[0], 'label': c[1]},
  ],
  'rubric_criterion': criterion,
};

Map<String, dynamic> _workbook() => {
  'state': 'ready',
  'revision': 1,
  'lesson_version': 'v1',
  'complete': false,
  'answers': <String, String>{},
  'attempts': <Map<String, dynamic>>[],
  'hints': <Map<String, dynamic>>[],
  'passed_activity_ids': <String>[],
  'workbook': {
    'title': 'Owner earnings',
    'activities': [
      {
        'id': 'guided',
        'title': 'Owner earnings at Harbor Tools',
        'kind': 'practice',
        'instructions':
            'Harbor Tools reported net income of 120. Work out what its owners really earned this year.',
        'minutes_min': 6,
        'minutes_max': 10,
        'data': [
          {'id': 'ni', 'label': 'Net income', 'value': 120, 'unit': 'm'},
          {'id': 'capex', 'label': 'Capital expenditure', 'value': 70},
          {'id': 'wh', 'label': '… of which new warehouse', 'value': 25.0},
        ],
        'fields': [
          _field(
            'oe',
            'Owner earnings',
            'number',
            unit: 'm',
            prefix: r'$',
            criterion: 'Owner earnings computed from the figures',
          ),
          _field(
            'lines',
            'Which lines are maintenance?',
            'multi_choice',
            choices: [
              ['repairs', 'Repairs'],
              ['warehouse', 'New warehouse'],
              ['fleet', 'Fleet replacement'],
            ],
          ),
          _field(
            'buy',
            'Is it worth 1.2bn?',
            'choice',
            choices: [
              ['no', 'No'],
              ['yes', 'Yes'],
            ],
          ),
          _field(
            'why',
            'Why does net income mislead here?',
            'text',
            criterion: 'Explains what net income leaves out',
          ),
        ],
      },
      {
        'id': 'independent',
        'title': 'Owner earnings at Delta Foods',
        'kind': 'transfer',
        'instructions':
            'Delta Foods reported net income of 64. Work out owner earnings on your own.',
        'minutes_min': 6,
        'minutes_max': 10,
        'data': <Map<String, dynamic>>[],
        'fields': [
          _field('oe', 'Owner earnings', 'number', unit: 'm', prefix: r'$'),
        ],
      },
    ],
  },
};

const _filled = {
  'guided.oe': '100',
  'guided.lines': 'repairs,fleet',
  'guided.buy': 'no',
  'guided.why': 'Net income ignores the capex that keeps the business going.',
};

Map<String, dynamic> _attempt(
  String activity,
  Map<String, String> answers, {
  required List<String> fields,
  required Set<String> passing,
}) => {
  'request_id': 'r-$activity-${answers.hashCode}',
  'activity_id': activity,
  'answers': {for (final f in fields) f: answers['$activity.$f']},
  'passed': passing.length == fields.length,
  'assisted': false,
  'feedback': [
    for (final f in fields)
      {
        'field_id': f,
        'passed': passing.contains(f),
        'feedback': passing.contains(f) ? 'Correct.' : 'Look again at $f.',
        'criterion': 'Criterion $f',
      },
  ],
};

class _Repo extends Fake implements PracticeRepository {
  Map<String, dynamic> data = _workbook();
  final hintCalls = <({String activity, String fieldId})>[];
  int checks = 0;
  bool failSave = false;
  Completer<void>? holdSubmit, holdSave, holdHint;
  final saved = <Map<String, String>>[];

  /// Which guided fields the next submission passes.
  Set<String> passing = {'oe', 'lines', 'buy', 'why'};

  LessonPracticeState get _state => LessonPracticeState.fromJson(data);

  @override
  Future<LessonPracticeState> load(String item, String step, String? a) async =>
      _state;

  @override
  Future<LessonPracticeState> save(
    String item,
    String step,
    String? artifact,
    int revision,
    Map<String, String> answers, {
    List<PracticeActivity> activities = const [],
  }) async {
    if (holdSave != null) await holdSave!.future;
    if (failSave) throw StateError('offline');
    if (revision != data['revision']) throw StateError('revision conflict');
    saved.add(answers);
    data = {...data, 'revision': revision + 1, 'answers': answers};
    _recomputePassed();
    return _state;
  }

  /// As the server: a case is passed while a passed attempt's answers equal
  /// the stored ones, string for string.
  void _recomputePassed() {
    final answers = (data['answers'] as Map).cast<String, String>();
    final passed = [
      for (final activity in ['guided', 'independent'])
        if ((data['attempts'] as List).cast<Map>().any(
          (a) =>
              a['activity_id'] == activity &&
              a['passed'] == true &&
              (a['answers'] as Map).entries.every(
                (e) => answers['$activity.${e.key}'] == e.value,
              ),
        ))
          activity,
    ];
    data = {
      ...data,
      'passed_activity_ids': passed,
      'complete': passed.length == 2,
    };
  }

  @override
  Future<LessonPracticeState> fieldHint(
    String item,
    String step,
    String? artifact, {
    required int revision,
    required String activity,
    required String fieldId,
    required String requestId,
  }) async {
    hintCalls.add((activity: activity, fieldId: fieldId));
    if (holdHint != null) await holdHint!.future;
    if (revision != data['revision']) throw StateError('revision conflict');
    data = {
      ...data,
      'revision': revision + 1,
      'hints': [
        ...data['hints'] as List,
        {
          'activity_id': activity,
          'kind': 'field_hint',
          'field_id': fieldId,
          'content': 'Start from net income and add back depreciation.',
        },
      ],
    };
    return _state;
  }

  @override
  Future<LessonPracticeState> act(
    String item,
    String step,
    String? artifact, {
    required String action,
    required int revision,
    required String activity,
    required String requestId,
    bool solution = false,
  }) async {
    if (action != 'submit') throw UnimplementedError(action);
    checks++;
    if (holdSubmit != null) await holdSubmit!.future;
    if (revision != data['revision']) throw StateError('revision conflict');
    final answers = (data['answers'] as Map).cast<String, String>();
    final attempt = _attempt(
      activity,
      answers,
      fields: activity == 'guided' ? ['oe', 'lines', 'buy', 'why'] : ['oe'],
      passing: activity == 'guided' ? passing : {'oe'},
    );
    data = {
      ...data,
      'revision': revision + 1,
      'attempts': [...data['attempts'] as List, attempt],
    };
    _recomputePassed();
    return _state;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Repo repo, {
  bool reduced = false,
  Widget? screen,
  double width = 390,
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceRepositoryProvider.overrideWithValue(repo),
        ...overrides,
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home:
            screen ??
            const LessonPracticeScreen(
              itemId: 'item',
              stepId: 's1',
              lessonTitle: 'Owner earnings',
              lessonContent: '## Owner earnings\nAdd back D&A.',
              isTutorial: true,
              tutorialNumber: 4,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _answer(String key) => find.byKey(ValueKey('answer-$key'));

Finder get _submit => find.widgetWithText(V3Button, 'Submit for checking');

Finder get _back =>
    find.byWidgetPredicate((w) => w is V3IconButton && w.label == 'Back');

bool _enabled(WidgetTester tester, Finder button) {
  final b = tester.widget<V3Button>(button);
  return b.onPressed != null && !b.disabled && !b.loading;
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(_answer(key));
  await tester.enterText(_answer(key), text);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pump();
}

Color _border(WidgetTester tester, String key) {
  final card = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('field-card-$key')),
  );
  return ((card.decoration! as BoxDecoration).border! as Border).top.color;
}

/// The design's criterion rows, by state.
Finder _criteria(String state) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('criterion-') &&
      (w.key! as ValueKey<String>).value.endsWith('-$state'),
);

void main() {
  testWidgets('submit_disabled_until_all_filled', (tester) async {
    final repo = _Repo();
    await _mount(tester, repo);
    expect(find.text('Your answers'.toUpperCase()), findsOneWidget);
    expect(_enabled(tester, _submit), isFalse);

    await _type(tester, 'guided.oe', '100');
    expect(_enabled(tester, _submit), isFalse);
    await _tapText(tester, 'Repairs');
    expect(_enabled(tester, _submit), isFalse);
    await _tapText(tester, 'No');
    expect(_enabled(tester, _submit), isFalse);
    await _type(tester, 'guided.why', '   ');
    expect(_enabled(tester, _submit), isFalse);
    await _type(tester, 'guided.why', 'Net income skips capex.');
    expect(_enabled(tester, _submit), isTrue);

    // Un-ticking the only selected line empties the multi field again.
    await _tapText(tester, 'Repairs');
    expect(_enabled(tester, _submit), isFalse);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('numeric_field_parses_comma_decimal', (tester) async {
    final repo = _Repo()
      ..data['answers'] = {..._filled}
      ..data['answers'].remove('guided.oe');
    await _mount(tester, repo);
    // Prefix and unit sit inside the number input.
    expect(find.text(r'$'), findsWidgets);
    expect(find.text('m'), findsWidgets);

    await _type(tester, 'guided.oe', '-');
    expect(_enabled(tester, _submit), isFalse);
    await _type(tester, 'guided.oe', '4,5');
    expect(_enabled(tester, _submit), isTrue);
    expect(find.text('Unsaved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Sent as a plain decimal the server parses; never silently zeroed.
    expect(repo.data['answers']['guided.oe'], '4.5');
    expect(find.text('Draft saved'), findsOneWidget);

    await _type(tester, 'guided.oe', '1.250,5');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.data['answers']['guided.oe'], '1250.5');

    // A multi selection is stored canonically (choice order, no spaces).
    await _tapText(tester, 'Repairs');
    await _tapText(tester, 'New warehouse');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.data['answers']['guided.lines'], 'warehouse,fleet');
  });

  testWidgets('field_hint_calls_api_with_field_id', (tester) async {
    final repo = _Repo();
    await _mount(tester, repo);
    expect(find.text('Hint used'), findsNothing);
    expect(find.text('Hint'), findsNWidgets(4));

    await tester.tap(find.text('Hint').first);
    await tester.pumpAndSettle();
    expect(repo.hintCalls, [(activity: 'guided', fieldId: 'guided.oe')]);
    expect(find.text('Hint used'), findsOneWidget);
    expect(
      find.text('Start from net income and add back depreciation.'),
      findsOneWidget,
    );

    // "Hint used" cannot be asked again, and survives a reload.
    await tester.tap(find.text('Hint used'));
    await tester.pumpAndSettle();
    expect(repo.hintCalls, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, repo);
    expect(find.text('Hint used'), findsOneWidget);
    expect(repo.hintCalls, hasLength(1));
  });

  testWidgets('criteria_tick_sequentially', (tester) async {
    final repo = _Repo()
      ..data['answers'] = {..._filled}
      ..passing = {'oe', 'buy', 'why'}
      ..holdSubmit = Completer<void>();
    await _mount(tester, repo);
    await tester.ensureVisible(_submit);
    await tester.tap(_submit);
    await tester.pump();

    // Checking: the night panel, the "Checking" CTA, nothing ticked yet.
    expect(find.text('Checking against criteria'), findsOneWidget);
    expect(find.text('Your draft is saved while this runs'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is V3Button && w.loading && w.semanticLabel == 'Checking',
      ),
      findsOneWidget,
    );
    expect(_criteria('pending'), findsNWidgets(4));
    expect(find.text('Owner earnings computed from the figures'), findsWidgets);

    repo.holdSubmit!.complete();
    await tester.pump();
    await tester.pump();
    expect(_criteria('pending'), findsNWidgets(4));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_criteria('met'), findsNWidgets(1));
    expect(_criteria('pending'), findsNWidgets(3));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_criteria('missed'), findsNWidgets(1));
    expect(_criteria('pending'), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_criteria('pending'), findsNothing);
    expect(find.text('Checking against criteria'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Result: ring score, "n of m criteria met", feedback, attempt chip.
    expect(find.text('Checking against criteria'), findsNothing);
    expect(find.text('3 of 4 criteria met'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('#1 · 3/4'), findsOneWidget);
    expect(find.text('Look again at lines.'), findsOneWidget);
    expect(find.text('Criterion oe'), findsOneWidget);
    expect(find.widgetWithText(V3Button, 'Revise answer'), findsOneWidget);
    // Field borders turn sage or danger per field.
    expect(_border(tester, 'guided.lines'), AppColors.danger);
    expect(_border(tester, 'guided.oe'), AppColors.sage);

    // Revise reopens editing.
    await tester.tap(find.widgetWithText(V3Button, 'Revise answer'));
    await tester.pumpAndSettle();
    expect(_submit, findsOneWidget);
    expect(_border(tester, 'guided.oe'), AppColors.hair);
  });

  testWidgets('criteria_tick_sequentially: reduced motion shows every tick at '
      'once', (tester) async {
    final repo = _Repo()..data['answers'] = {..._filled};
    await _mount(tester, repo, reduced: true);
    await tester.ensureVisible(_submit);
    await tester.tap(_submit);
    await tester.pump();
    await tester.pump();
    expect(_criteria('pending'), findsNothing);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Saved with your attempt history'), findsOneWidget);
    expect(
      find.widgetWithText(V3Button, 'Continue to independent case'),
      findsOneWidget,
    );
  });

  testWidgets('independent_locked_until_guided_passed', (tester) async {
    final repo = _Repo();
    await _mount(tester, repo);
    expect(find.text('Guided'), findsWidgets);
    expect(find.text('Independent'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is V3Icon && w.icon == V3Icons.lock),
      findsOneWidget,
    );

    await tester.tap(find.text('Independent'));
    await tester.pumpAndSettle();
    expect(find.text('Owner earnings at Harbor Tools'), findsOneWidget);
    expect(find.text('Owner earnings at Delta Foods'), findsNothing);

    // Pass the guided case, then continue to the independent one.
    repo.data['answers'] = {..._filled};
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, repo);
    await tester.ensureVisible(_submit);
    await tester.tap(_submit);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(V3Button, 'Continue to independent case'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Owner earnings at Delta Foods'), findsOneWidget);
    expect(
      find.text(
        'The worked solution for this case appears only after it is accepted.',
      ),
      findsOneWidget,
    );
    // The guided step is now a sage check and can be revisited.
    await tester.tap(find.text('Guided'));
    await tester.pumpAndSettle();
    expect(find.text('Owner earnings at Harbor Tools'), findsOneWidget);
  });

  testWidgets('leave_sheet_when_unsaved', (tester) async {
    final repo = _Repo();
    final results = <bool?>[];
    // Reduced motion: the "Saving" spinner holds still while the save waits.
    await _mount(
      tester,
      repo,
      reduced: true,
      screen: _host(_practice, results),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _type(tester, 'guided.oe', '100');
    expect(find.text('Unsaved'), findsOneWidget);
    repo.holdSave = Completer<void>(); // the save is still in flight

    await tester.tap(_back);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Leave practice?'), findsOneWidget);
    expect(
      find.text(
        'Your last change hasn’t saved yet. Wait a moment, or leave without it.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Leave practice?'), findsNothing);
    expect(find.byType(LessonPracticeScreen), findsOneWidget);

    // System back asks too.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Leave practice?'), findsOneWidget);
    await tester.tap(find.text('Leave without saving'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonPracticeScreen), findsNothing);
    expect(results, [false]);

    // The abandoned save landing later pops nothing else.
    repo.holdSave!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(results, [false]);
  });

  testWidgets('leave sheet closes itself when the slow save lands', (
    tester,
  ) async {
    final repo = _Repo();
    final results = <bool?>[];
    await _mount(
      tester,
      repo,
      reduced: true,
      screen: _host(_practice, results),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _type(tester, 'guided.oe', '100');
    repo.holdSave = Completer<void>();
    await tester.tap(_back);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Leave practice?'), findsOneWidget);

    repo.holdSave!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Leave practice?'), findsNothing);
    expect(find.byType(LessonPracticeScreen), findsNothing);
    expect(repo.data['answers']['guided.oe'], '100');
    expect(results, [false]);
  });

  testWidgets('a save landing while the leave sheet closes keeps practice', (
    tester,
  ) async {
    final repo = _Repo();
    final results = <bool?>[];
    await _mount(tester, repo, screen: _host(_practice, results));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _type(tester, 'guided.oe', '100');
    repo.holdSave = Completer<void>();
    // With motion on (the sheet animates out), so pump by time: the
    // "Saving" spinner never settles while the save waits.
    await tester.tap(_back);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Leave practice?'), findsOneWidget);

    // "Keep editing" starts the sheet's exit; the save lands during it.
    await tester.tap(find.text('Keep editing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    repo.holdSave!.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(LessonPracticeScreen), findsOneWidget);
    expect(find.text('Leave practice?'), findsNothing);
    expect(find.text('Draft saved'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('leave sheet offers a retry after a failed save', (tester) async {
    final repo = _Repo()..failSave = true;
    final results = <bool?>[];
    await _mount(tester, repo, screen: _host(_practice, results));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _type(tester, 'guided.oe', '100');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.text('Leave practice?'), findsOneWidget);
    expect(
      find.text('Couldn’t save — try again, or leave without it.'),
      findsOneWidget,
    );
    expect(find.text('Wait a moment'), findsNothing);
    repo.failSave = false;
    await tester.tap(find.widgetWithText(V3Button, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonPracticeScreen), findsNothing);
    expect(repo.data['answers']['guided.oe'], '100');
    expect(results, [false]);
  });

  for (final (locale, wire) in [
    (const Locale('en', 'US'), '1250'),
    (const Locale('de', 'DE'), '1.25'),
  ]) {
    testWidgets('ambiguous "1,250" follows the device locale: $locale', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = locale;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final repo = _Repo();
      await _mount(tester, repo);
      await _type(tester, 'guided.oe', '1,250');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.data['answers']['guided.oe'], wire);
    });
  }

  testWidgets('typing back to a failed attempt keeps the field editable', (
    tester,
  ) async {
    final failed = {..._filled, 'guided.oe': '70'};
    final repo = _Repo()
      ..data['answers'] = {..._filled, 'guided.oe': '7'}
      ..data['attempts'] = [
        _attempt(
          'guided',
          failed,
          fields: ['oe', 'lines', 'buy', 'why'],
          passing: {'lines', 'buy', 'why'},
        ),
      ];
    await _mount(tester, repo);
    expect(_submit, findsOneWidget);

    // The answers now equal the failed attempt's, but the learner is typing.
    await _type(tester, 'guided.oe', '70');
    expect(tester.widget<TextField>(_answer('guided.oe')).enabled, isTrue);
    expect(_submit, findsOneWidget);
    expect(find.text('3 of 4 criteria met'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_answer('guided.oe')).enabled, isTrue);
  });

  testWidgets('a legacy "4,5" keeps the guided case passed', (tester) async {
    final legacy = {..._filled, 'guided.oe': '4,5'};
    final repo = _Repo()
      ..data['answers'] = legacy
      ..data['passed_activity_ids'] = ['guided']
      ..data['attempts'] = [
        _attempt(
          'guided',
          legacy,
          fields: ['oe', 'lines', 'buy', 'why'],
          passing: {'oe', 'lines', 'buy', 'why'},
        ),
      ];
    await _mount(tester, repo);
    expect(find.text('Owner earnings at Delta Foods'), findsOneWidget);

    await _type(tester, 'independent.oe', '58');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // The unchanged answer keeps its stored spelling; the new one is plain.
    expect(repo.saved.last['guided.oe'], '4,5');
    expect(repo.saved.last['independent.oe'], '58');
    expect(repo.data['passed_activity_ids'], ['guided']);
    expect(find.text('Owner earnings at Delta Foods'), findsOneWidget);
    await tester.tap(find.text('Guided'));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets('a hint keeps every field editable and the keyboard up', (
    tester,
  ) async {
    final repo = _Repo()..holdHint = Completer<void>();
    await _mount(tester, repo);
    await tester.tap(_answer('guided.oe'));
    await tester.pump();
    final editable = find.descendant(
      of: _answer('guided.oe'),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Hint').first);
    await tester.pump();
    expect(find.byKey(const ValueKey('hint-loading')), findsOneWidget);
    expect(tester.widget<TextField>(_answer('guided.oe')).enabled, isTrue);
    expect(tester.widget<TextField>(_answer('guided.why')).enabled, isTrue);
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    // Typing meanwhile saves after the hint lands, on its revision.
    await tester.enterText(_answer('guided.oe'), '100');
    await tester.pump(const Duration(seconds: 1));
    expect(repo.saved, isEmpty);
    repo.holdHint!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Hint used'), findsOneWidget);
    expect(repo.data['answers']['guided.oe'], '100');
    expect(find.text('Draft saved'), findsOneWidget);
  });

  testWidgets('a narrow phone at large text keeps the title and does not '
      'overflow', (tester) async {
    final repo = _Repo()..data['answers'] = {..._filled};
    await _mount(tester, repo, width: 320, textScale: 1.6);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.text('Practice · Tutorial 4')).width,
      greaterThan(60),
    );
  });

  testWidgets('a legacy "1,250" is read as the server graded it', (
    tester,
  ) async {
    // en_US: live "1,250" would mean 1250, but the server read the stored
    // "1,250" as 1.25, so typing 1250 is a change and must be sent.
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final legacy = {..._filled, 'guided.oe': '1,250'};
    final repo = _Repo()
      ..data['answers'] = legacy
      ..data['attempts'] = [
        _attempt(
          'guided',
          legacy,
          fields: ['oe', 'lines', 'buy', 'why'],
          passing: {'lines', 'buy', 'why'},
        ),
      ];
    await _mount(tester, repo);
    // The stored answer shows its failed result; revise and type 1250.
    expect(find.text('3 of 4 criteria met'), findsOneWidget);
    await tester.tap(find.widgetWithText(V3Button, 'Revise answer'));
    await tester.pumpAndSettle();
    await _type(tester, 'guided.oe', '1250');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.saved.last['guided.oe'], '1250');
    // Untouched answers keep their stored spelling.
    expect(repo.saved.last['guided.lines'], 'repairs,fleet');
  });

  testWidgets('Submit waits while a hint (and its pre-save) is in flight', (
    tester,
  ) async {
    final repo = _Repo()..data['answers'] = {..._filled};
    await _mount(tester, repo, reduced: true);
    repo.holdSave = Completer<void>();
    await _type(tester, 'guided.oe', '101'); // dirty: the hint saves first
    // Bring the Hint clear of the footer before tapping it.
    unawaited(
      Scrollable.ensureVisible(
        tester.element(find.text('Hint').first),
        alignment: .5,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hint').first);
    await tester.pump();
    expect(find.byKey(const ValueKey('hint-loading')), findsOneWidget);
    expect(_enabled(tester, _submit), isFalse);
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();
    expect(repo.checks, 0);

    repo.holdSave!.complete();
    await tester.pumpAndSettle();
    expect(repo.hintCalls, hasLength(1));
    expect(find.text('Hint used'), findsOneWidget);
    expect(_enabled(tester, _submit), isTrue);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    // One check, on the hint's revision: no conflict, no error.
    expect(repo.checks, 1);
    expect(find.textContaining('Could not finish this check'), findsNothing);
    expect(find.text('Accepted'), findsOneWidget);
  });

  group('finish', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<_Completion> openReaderAndFinish(
      WidgetTester tester,
      List<bool?> results, {
      bool failFirst = false,
      _Store? store,
    }) async {
      final completion = _Completion(failFirst: failFirst);
      await _mount(
        tester,
        _finishedRepo(),
        reduced: true,
        screen: _host(_reader, results),
        overrides: [
          planRepositoryProvider.overrideWithValue(completion),
          currentPlanProvider.overrideWith((_) => _Plan(completion)),
          cmpysStoreProvider.overrideWith((_) => store ?? _Store()),
        ],
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open practice'));
      await tester.pumpAndSettle();
      // A finished workbook opens on its last case, accepted.
      expect(find.text('Owner earnings at Delta Foods'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Show worked solution'), findsOneWidget);
      await tester.tap(find.widgetWithText(V3Button, 'Finish tutorial'));
      await tester.pumpAndSettle();
      return completion;
    }

    testWidgets('finish_shows_celebration', (tester) async {
      final results = <bool?>[];
      final completion = await openReaderAndFinish(tester, results);
      // The step is complete before anything is celebrated.
      expect(completion.calls, 1);
      final overlay = tester.widget<CelebrationOverlay>(
        find.byType(CelebrationOverlay),
      );
      expect(overlay.celebration.kind, CelebrationKind.tutorial);
      expect(overlay.celebration.title, 'Tutorial 4 complete');
      expect(overlay.celebration.statLabel, 'of 8 tutorials');
      expect(
        overlay.celebration.sub,
        'Both cases accepted. Tutorial 5, Maintenance versus growth capex, '
        'is now open.',
      );
      expect(
        overlay.celebration.achievement,
        'Completed “Owner earnings” with every case accepted',
      );
      expect(find.byType(LessonPracticeScreen), findsNothing);
      expect(results, isEmpty);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(CelebrationOverlay), findsNothing);
      expect(find.byType(LessonReaderScreen), findsNothing);
      expect(results, [true]);
      expect(completion.saves, isEmpty);
    });

    testWidgets('a failed completion shows no celebration, then the retry '
        'celebrates', (tester) async {
      final results = <bool?>[];
      final completion = await openReaderAndFinish(
        tester,
        results,
        failFirst: true,
      );
      expect(completion.calls, 1);
      expect(find.byType(CelebrationOverlay), findsNothing);
      expect(find.byType(LessonReaderScreen), findsOneWidget);
      expect(
        find.text('Couldn’t complete this tutorial. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Complete tutorial'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // the toast times out

      await tester.tap(find.text('Complete tutorial'));
      await tester.pumpAndSettle();
      expect(completion.calls, 2);
      // Both the finish and its retry ask for "complete", so a retry after
      // a committed-but-lost response can never un-complete the step.
      expect(completion.completes, [true, true]);
      expect(find.byType(CelebrationOverlay), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(results, [true]);
    });

    testWidgets('a celebration error never reads as a completion failure', (
      tester,
    ) async {
      final results = <bool?>[];
      final completion = _Completion();
      await _mount(
        tester,
        _finishedRepo(),
        reduced: true,
        screen: _host(_reader, results),
        overrides: [
          planRepositoryProvider.overrideWithValue(completion),
          // Reading the plan for the record fails.
          currentPlanProvider.overrideWith((_) => throw StateError('no plan')),
          cmpysStoreProvider.overrideWith((_) => _Store()),
        ],
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open practice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(V3Button, 'Finish tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to your record'));
      await tester.pumpAndSettle();
      // The step stays complete: no failure toast, no retry, one toggle.
      expect(completion.calls, 1);
      expect(
        find.text('Couldn’t complete this tutorial. Try again.'),
        findsNothing,
      );
      expect(find.text('Complete tutorial'), findsNothing);
      expect(find.byType(LessonReaderScreen), findsNothing);
      expect(results, [true]);
    });

    testWidgets('a learner with no age gets the win under Undated', (
      tester,
    ) async {
      final results = <bool?>[];
      final store = _Store(age: 0);
      final completion = await openReaderAndFinish(
        tester,
        results,
        store: store,
      );
      await tester.tap(find.text('Add to your record'));
      await tester.pumpAndSettle();
      expect(find.text('Age 0'), findsNothing);
      await tester.tap(find.text('Confirm achievement'));
      await tester.pumpAndSettle();
      // Saved on the server, and kept at age 0 on this device, so the
      // Record files it under Undated.
      expect(completion.saves, hasLength(1));
      final win = store.current.achievements.single;
      expect(win.age, 0);
      expect(win.source, 'auto');
      expect(win.synced, isTrue);
      final entry = recordTimeline(
        store.current,
      ).singleWhere((e) => e.mine);
      expect(entry.age, isNull);
      expect(results, [true]);
      await tester.pump(const Duration(seconds: 3)); // the toast times out
    });

    testWidgets('the tutorial achievement is the learner’s own, with plan and '
        'cycle, and joins the record', (tester) async {
      final results = <bool?>[];
      final store = _Store();
      final completion = await openReaderAndFinish(
        tester,
        results,
        store: store,
      );
      await tester.tap(find.text('Add to your record'));
      await tester.pumpAndSettle();
      expect(find.text('Suggested achievement'), findsOneWidget);
      await tester.tap(find.text('Confirm achievement'));
      await tester.pumpAndSettle();
      expect(completion.saves, [
        {
          'title': 'Completed “Owner earnings” with every case accepted',
          'source': 'manual',
          'planId': 'plan-7',
          'planItemId': null,
          'cycleNumber': 3,
        },
      ]);
      final win = store.current.achievements.last;
      expect(win.title, 'Completed “Owner earnings” with every case accepted');
      expect(win.dim, 'practice');
      expect(win.source, 'auto');
      expect(win.assessed, isTrue);
      // The server copy's id, so "Delete entry" can delete both (R3-I2),
      // and no canned mentor line (R3-M7).
      expect(win.serverId, 'ach-tutorial-1');
      expect(win.idolNote, isNull);
      expect(results, [true]);
      await tester.pump(const Duration(seconds: 3)); // the toast times out
    });
  });
}

const _practice = LessonPracticeScreen(
  itemId: 'item',
  stepId: 's1',
  lessonTitle: 'Owner earnings',
  lessonContent: 'Owner earnings.',
  isTutorial: true,
);

const _reader = LessonReaderScreen(
  itemId: 'item',
  missionTitle: 'Owner earnings',
  step: PlanStepDetail(
    id: 's1',
    title: 'Owner earnings',
    lessonContent: '## Learn\nOwner earnings.',
    lessonFormat: 'tutorial_v1',
  ),
  stepNumber: 4,
  totalSteps: 8,
  materials: [],
  completed: false,
  nextTitle: 'Maintenance versus growth capex',
);

/// Hosts [screen] behind an "Open" button and records what it pops.
Widget _host(Widget screen, List<bool?> results) => Builder(
  builder: (context) => TextButton(
    onPressed: () async => results.add(
      await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => screen)),
    ),
    child: const Text('Open'),
  ),
);

/// Both cases accepted on the current answers.
_Repo _finishedRepo() {
  final answers = {..._filled, 'independent.oe': '58'};
  return _Repo()
    ..data['answers'] = answers
    ..data['complete'] = true
    ..data['passed_activity_ids'] = ['guided', 'independent']
    ..data['attempts'] = [
      _attempt(
        'guided',
        answers,
        fields: ['oe', 'lines', 'buy', 'why'],
        passing: {'oe', 'lines', 'buy', 'why'},
      ),
      _attempt('independent', answers, fields: ['oe'], passing: {'oe'}),
    ];
}

class _Completion extends Fake implements PlanRepository {
  _Completion({this.failFirst = false});
  final bool failFirst;
  int calls = 0;
  final saves = <Map<String, Object?>>[];

  /// The desired state each completion request carried.
  final completes = <bool?>[];

  @override
  Future<({bool completed, bool itemCompleted})> toggleStepComplete(
    String itemId,
    String stepId, {
    String? artifactJobId,
    bool? complete,
  }) async {
    calls++;
    completes.add(complete);
    if (failFirst && calls == 1) throw Exception('offline');
    return (completed: true, itemCompleted: false);
  }

  @override
  Future<String?> saveAchievement({
    required String title,
    required String category,
    String? notes,
    String? evidenceLink,
    required String source,
    String? planId,
    String? planItemId,
    int cycleNumber = 1,
  }) async {
    saves.add({
      'title': title,
      'source': source,
      'planId': planId,
      'planItemId': planItemId,
      'cycleNumber': cycleNumber,
    });
    return 'ach-tutorial-${saves.length}';
  }
}

class _Plan extends CurrentPlanController {
  _Plan(PlanRepository repo) : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(
      status: CurrentPlanStatus.ready,
      plan: BackendPlan(
        id: 'plan-7',
        durationWeeks: 12,
        weeklyHours: 4,
        cycleNumber: 3,
        items: const [],
      ),
    );
  }

  @override
  Future<void> refresh() async {}
}

class _Store extends CmpysStore {
  _Store({int age = 24}) {
    state = state.copyWith(
      user: CmpysUser(name: 'Maya', age: age),
    );
  }

  CmpysState get current => state;
}
