import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/intake_answer_composer.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/intake_step.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/interview_response_ui.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Intake v3 (design `v3/onboard2.jsx` `Intake`): every Task A1 control kind
// against the real wire format, plus the missing-evidence flag.

const _weeklyHours = <String, Object?>{
  'version': 1,
  'kind': 'number',
  'answer_key': 'weekly_hours',
  'min': 1,
  'max': 15,
  'step': 0.5,
  'initial': 4,
  'presets': [2, 4, 6, 8],
  'unit': 'hours / week',
  'daily_hint': true,
  'allow_custom': true,
};

const _learning = <String, Object?>{
  'version': 1,
  'kind': 'multi_choice',
  'answer_key': 'learning_preferences',
  'options': [
    'Worked examples',
    'Reading deeply',
    'Doing exercises',
    'Listening',
    'Short daily sessions',
  ],
  'option_details': [
    {'icon': 'list'},
    {'icon': 'book'},
    {'icon': 'edit'},
    {'icon': 'headphones'},
    {'icon': 'clock'},
  ],
  'min_selected': 1,
  'allow_custom': true,
};

Widget _composer(
  Map<String, Object?> json,
  ValueChanged<String> onSubmit, {
  ValueChanged<String>? onMissing,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: IntakeAnswerComposer(
            responseUi: InterviewResponseUi.fromJson(json),
            onSubmit: onSubmit,
            onSubmitMissingEvidence: onMissing,
          ),
        ),
      ),
    ),
  );
}

Finder get _send => find.byKey(const ValueKey('intake-answer-submit'));

/// Taps "Send" once any caret scroll of a focused field has settled. A
/// disabled button ignores the tap, so a miss is expected there.
Future<void> _tapSend(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(_send);
  await tester.pumpAndSettle();
  await tester.tap(_send, warnIfMissed: false);
  await tester.pump();
}

void main() {
  group('InterviewResponseUi parses every A1 field', () {
    test('text: placeholder, suggestions, missing_option, answer_key', () {
      final ui = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'text',
        'answer_key': 'work_sample',
        'placeholder': 'Paste or describe your work…',
        'suggestions': ['I’ve tried it on my own', 'Nothing yet'],
        'missing_option': 'I don’t have one yet',
      });
      expect(ui.kind, InterviewResponseKind.text);
      expect(ui.answerKey, 'work_sample');
      expect(ui.placeholder, 'Paste or describe your work…');
      expect(ui.suggestions, ['I’ve tried it on my own', 'Nothing yet']);
      expect(ui.missingOption, 'I don’t have one yet');
      expect(ui.allowCustom, isTrue);
    });

    test('single_choice: options and aligned option_details', () {
      final ui = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'single_choice',
        'answer_key': 'self_check_method',
        'options': ['I compare with a trusted source', 'I don’t really check'],
        'option_details': [
          {'description': 'Books, documentation, primary material'},
          {'description': 'Honest answers help most', 'icon': 'target'},
        ],
        'allow_custom': false,
      });
      expect(ui.kind, InterviewResponseKind.singleChoice);
      expect(ui.options, [
        'I compare with a trusted source',
        'I don’t really check',
      ]);
      expect(ui.optionDetails.map((d) => d.description), [
        'Books, documentation, primary material',
        'Honest answers help most',
      ]);
      expect(ui.optionDetails.map((d) => d.icon), [null, 'target']);
      // Choice kinds always allow a custom answer (the server forces it).
      expect(ui.allowCustom, isTrue);
      expect(ui.answerKey, 'self_check_method');
    });

    test('multi_choice: icons, min_selected and max_selected', () {
      final ui = InterviewResponseUi.fromJson({
        ..._learning,
        'max_selected': 3,
      });
      expect(ui.kind, InterviewResponseKind.multiChoice);
      expect(ui.options, hasLength(5));
      expect(ui.optionDetails.map((d) => d.icon), [
        'list',
        'book',
        'edit',
        'headphones',
        'clock',
      ]);
      expect(ui.minSelected, 1);
      expect(ui.maxSelected, 3);
      expect(ui.answerKey, 'learning_preferences');
    });

    test('scale: low_label and high_label on a fixed 1 to 5 range', () {
      final ui = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'scale',
        'answer_key': 'skill_confidence',
        'min': 1,
        'max': 5,
        'step': 1,
        'low_label': 'Never opened one',
        'high_label': 'Read them often',
      });
      expect(ui.kind, InterviewResponseKind.scale);
      expect(ui.lowLabel, 'Never opened one');
      expect(ui.highLabel, 'Read them often');
      expect(ui.min, 1);
      expect(ui.max, 5);
      expect(ui.step, 1);
    });

    test('number: aliases, presets, daily_hint, unit and allow_custom', () {
      final ui = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'number',
        'answer_key': 'weekly_hours',
        'min_value': 1,
        'max_value': 15,
        'step': 0.5,
        'initial_value': 4,
        'presets': [2, 4, 6, 8],
        'daily_hint': true,
        'unit': 'hours / week',
        'allow_custom': false,
      });
      expect(ui.kind, InterviewResponseKind.number);
      expect(ui.min, 1);
      expect(ui.max, 15);
      expect(ui.step, 0.5);
      expect(ui.initial, 4);
      expect(ui.presets, [2, 4, 6, 8]);
      expect(ui.dailyHint, isTrue);
      expect(ui.unit, 'hours / week');
      expect(ui.allowCustom, isFalse);
      expect(ui.answerKey, 'weekly_hours');
      expect(ui.isWeeklyHours, isTrue);
    });

    test('drifted optional fields degrade without losing the control', () {
      final ui = InterviewResponseUi.fromJson({
        ..._weeklyHours,
        // Off-grid and out-of-range presets are dropped, not fatal.
        'presets': [2, 4.25, 99, 'x', 8],
        'daily_hint': 'yes',
      });
      expect(ui.kind, InterviewResponseKind.number);
      expect(ui.presets, [2, 8]);
      expect(ui.dailyHint, isFalse);

      final choice = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'single_choice',
        'options': ['A', 'B'],
        // Misaligned details and unknown icons are ignored.
        'option_details': [
          {'description': 'Only one', 'icon': 'rocket'},
        ],
      });
      expect(choice.kind, InterviewResponseKind.singleChoice);
      expect(choice.optionDetails.every((d) => d.isEmpty), isTrue);
    });

    test('invalid multi and scale payloads fall back to text', () {
      for (final invalid in <Map<String, Object?>>[
        {
          ..._learning,
          'options': ['Only one'],
        },
        {..._learning, 'min_selected': 9},
        {..._learning, 'max_selected': 0},
        {..._learning, 'min_selected': 3, 'max_selected': 2},
        {'version': 1, 'kind': 'multi_choice'},
      ]) {
        expect(
          InterviewResponseUi.fromJson(invalid).kind,
          InterviewResponseKind.text,
          reason: '$invalid',
        );
      }
    });
  });

  testWidgets('missing_chip_sends_with_flag_and_tags_bubble', (tester) async {
    final repository = _WorkSampleRepository();
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';
    await tester.pumpWidget(_step(repository, draft));
    await tester.pumpAndSettle();

    expect(find.text('TYPE OR PICK A STARTING POINT'), findsOneWidget);
    expect(find.text('Intake with ${defaultIdol().short}'), findsOneWidget);
    expect(find.text('Question 2 of 12'), findsOneWidget);
    expect(
      find.text('Answers are saved to your session as you go.'),
      findsOneWidget,
    );

    // An ordinary suggestion only fills the field.
    await tester.tap(find.text('I wrote a short memo'));
    await tester.pump();
    expect(repository.answers, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('intake-text-input')))
          .controller!
          .text,
      'I wrote a short memo',
    );

    // The missing-evidence chip sends at once, flagged.
    await tester.tap(find.text('I don’t have one yet'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.answers, ['I don’t have one yet']);
    expect(repository.missingFlags, [true]);
    expect(repository.answeredQuestionIds, ['work-sample']);
    expect(find.text('Recorded as missing evidence'), findsOneWidget);
    expect(find.text('I don’t have one yet'), findsOneWidget);
    expect(find.text('Question 3 of 12'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('multi_send_label_counts_selection', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      _composer({..._learning, 'max_selected': 2}, submitted.add),
    );
    await tester.pump();

    expect(find.text('CHOOSE ANY THAT FIT'), findsOneWidget);
    expect(find.text('Select at least one'), findsOneWidget);
    await _tapSend(tester);
    expect(submitted, isEmpty);

    await tester.tap(find.text('Worked examples'));
    await tester.pump();
    expect(find.text('Send 1 selected'), findsOneWidget);
    await tester.tap(find.text('Doing exercises'));
    await tester.pump();
    expect(find.text('Send 2 selected'), findsOneWidget);
    // max_selected 2: a third pick is ignored.
    await tester.tap(find.text('Listening'));
    await tester.pump();
    expect(find.text('Send 2 selected'), findsOneWidget);
    // Un-picking counts down.
    await tester.tap(find.text('Worked examples'));
    await tester.pump();
    expect(find.text('Send 1 selected'), findsOneWidget);
    await tester.tap(find.text('Worked examples'));
    await tester.pump();

    // The odd last card spans both columns.
    final last = tester.getSize(find.byKey(const ValueKey('intake-multi-4')));
    final first = tester.getSize(find.byKey(const ValueKey('intake-multi-0')));
    expect(last.width, greaterThan(first.width * 1.8));

    await _tapSend(tester);
    expect(submitted, ['Worked examples, Doing exercises']);
  });

  testWidgets('scale_requires_pick', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      _composer({
        'version': 1,
        'kind': 'scale',
        'answer_key': 'skill_confidence',
        'low_label': 'Never opened one',
        'high_label': 'Read them often',
      }, submitted.add),
    );
    await tester.pump();

    expect(find.text('RATE 1 TO 5'), findsOneWidget);
    expect(find.text('Never opened one'), findsOneWidget);
    expect(find.text('Read them often'), findsOneWidget);
    // Nothing is sent until a tile is picked.
    await _tapSend(tester);
    expect(submitted, isEmpty);
    expect(find.text('Write my own'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('intake-scale-3')));
    await tester.pumpAndSettle();
    Color tile(int v) =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(ValueKey('intake-scale-$v')),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(tile(1), AppColors.emberSoft);
    expect(tile(2), AppColors.emberSoft);
    expect(tile(3), AppColors.ink);
    expect(tile(4), AppColors.paper);
    expect(
      tester.getSize(find.byKey(const ValueKey('intake-scale-1'))).height,
      greaterThanOrEqualTo(56),
    );

    await _tapSend(tester);
    expect(submitted, ['3 of 5']);
  });

  testWidgets('number_typed_out_of_range_clamps', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(_composer(_weeklyHours, submitted.add));
    await tester.pump();
    final input = find.byKey(const ValueKey('intake-number-input'));

    expect(find.text('SET A NUMBER'), findsOneWidget);
    expect(find.text('hours / week'), findsOneWidget);

    // Blank never sends.
    await tester.enterText(input, '');
    await tester.pump();
    await _tapSend(tester);
    expect(submitted, isEmpty);

    // Malformed never sends.
    await tester.enterText(input, '1.2.3');
    await tester.pump();
    await _tapSend(tester);
    expect(submitted, isEmpty);

    // Above the range clamps to the maximum.
    await tester.enterText(input, '40');
    await tester.pump();
    await _tapSend(tester);
    expect(submitted, ['15 hours a week']);
  });

  testWidgets('number typed values snap to the step and clamp low', (
    tester,
  ) async {
    for (final (typed, sent) in [
      ('0', '1 hour a week'),
      ('4.3', '4.5 hours a week'),
      ('4.2', '4 hours a week'),
    ]) {
      final submitted = <String>[];
      await tester.pumpWidget(_composer(_weeklyHours, submitted.add));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('intake-number-input')),
        typed,
      );
      await tester.pump();
      await _tapSend(tester);
      expect(submitted, [sent], reason: typed);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('number_comma_decimal_parsed', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(_composer(_weeklyHours, submitted.add));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('intake-number-input')),
      '4,5',
    );
    await tester.pump();
    expect(
      find.text('About 39 min a day · your plan’s workload will fit this'),
      findsOneWidget,
    );
    await _tapSend(tester);
    expect(submitted, ['4.5 hours a week']);
  });

  testWidgets('daily_hint_shows_minutes', (tester) async {
    await tester.pumpWidget(_composer(_weeklyHours, (_) {}));
    await tester.pump();

    expect(
      find.text('About 34 min a day · your plan’s workload will fit this'),
      findsOneWidget,
    );
    // Presets, −/+ and the hint move together.
    await tester.tap(find.text('8 h'));
    await tester.pump();
    expect(
      find.text('About 69 min a day · your plan’s workload will fit this'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('intake-number-input')))
          .controller!
          .text,
      '8',
    );
    await tester.tap(find.byKey(const ValueKey('intake-number-plus')));
    await tester.pump();
    expect(
      find.text('About 73 min a day · your plan’s workload will fit this'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('intake-number-plus'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('1 h'), findsOneWidget);
    expect(find.text('15 h'), findsOneWidget);

    // Without daily_hint there is no hint.
    await tester.pumpWidget(
      _composer({..._weeklyHours, 'daily_hint': false}, (_) {}),
    );
    await tester.pump();
    expect(find.textContaining('min a day'), findsNothing);
  });

  testWidgets('unknown_kind_falls_back_to_text', (tester) async {
    expect(
      InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'calendar',
        'options': ['Mon', 'Tue'],
      }).kind,
      InterviewResponseKind.text,
    );

    final repository = _UnknownKindRepository();
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';
    await tester.pumpWidget(_step(repository, draft));
    await tester.pumpAndSettle();

    // A text turn without starting points (F3).
    expect(find.text('TYPE YOUR ANSWER'), findsOneWidget);
    final input = find.byKey(const ValueKey('intake-text-input'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Mondays mostly');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intake-text-submit')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.answers, ['Mondays mostly']);
    expect(repository.missingFlags, [false]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the text field stays focused and above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WorkSampleRepository();
    await tester.pumpWidget(
      _step(repository, CmpysOnboardingDraft()..sessionId = 'session-1'),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey('intake-text-input'));
    await tester.tap(input);
    await tester.pump();
    // The keyboard opens after the field is focused, as on a device; the
    // panel moves out of the overlay and must keep its field and focus.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(of: input, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(844 - 336));
    expect(
      tester.getRect(find.byKey(const ValueKey('intake-text-submit'))).bottom,
      lessThanOrEqualTo(844 - 336),
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(input, 'A rough memo on a retailer');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intake-text-submit')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.answers, ['A rough memo on a retailer']);
    expect(repository.missingFlags, [false]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('choice rows show descriptions and send the picked label', (
    tester,
  ) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      _composer({
        'version': 1,
        'kind': 'single_choice',
        'options': ['I read the annual report', 'I don’t really check'],
        'option_details': [
          {'description': 'Primary documents first', 'icon': 'book'},
          {'description': 'Honest answers help most'},
        ],
      }, submitted.add),
    );
    await tester.pump();

    expect(find.text('CHOOSE ONE'), findsOneWidget);
    expect(find.text('Primary documents first'), findsOneWidget);
    expect(find.text('Honest answers help most'), findsOneWidget);
    await _tapSend(tester);
    expect(submitted, isEmpty);
    await tester.tap(find.text('I don’t really check'));
    await tester.pump();
    await _tapSend(tester);
    expect(submitted, ['I don’t really check']);
  });

  testWidgets('choice rows and scale tiles read as radio buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _composer({
        'version': 1,
        'kind': 'single_choice',
        'options': ['I read the annual report', 'I don’t really check'],
      }, (_) {}),
    );
    await tester.pump();
    await tester.tap(find.text('I don’t really check'));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('intake-choice-0'))),
      containsSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
        isButton: false,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('intake-choice-1'))),
      containsSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
      ),
    );

    await tester.pumpWidget(
      _composer({'version': 1, 'kind': 'scale'}, (_) {}),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intake-scale-2')));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('intake-scale-2'))),
      containsSemantics(
        label: '2 of 5',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
        isButton: false,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('intake-scale-4'))),
      containsSemantics(
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a free-text turn with no starting points reads TYPE YOUR '
      'ANSWER', (tester) async {
    await tester.pumpWidget(
      _composer({
        'version': 1,
        'kind': 'text',
        'answer_key': 'goal',
        'placeholder': 'Say it in your own words…',
      }, (_) {}),
    );
    await tester.pump();
    expect(find.text('TYPE YOUR ANSWER'), findsOneWidget);
    expect(find.text('TYPE OR PICK A STARTING POINT'), findsNothing);
    // The same header style and pencil as the other kinds.
    final row = find.ancestor(
      of: find.text('TYPE YOUR ANSWER'),
      matching: find.byType(Row),
    );
    expect(
      tester
          .widget<V3Icon>(
            find.descendant(of: row.first, matching: find.byType(V3Icon)),
          )
          .icon,
      V3Icons.edit,
    );

    // With starting-point chips it still offers them.
    await tester.pumpWidget(
      _composer({
        'version': 1,
        'kind': 'text',
        'suggestions': ['I wrote a short memo'],
      }, (_) {}),
    );
    await tester.pump();
    expect(find.text('TYPE OR PICK A STARTING POINT'), findsOneWidget);
    expect(find.text('TYPE YOUR ANSWER'), findsNothing);
  });

  testWidgets('the number header shows a clock only for time', (tester) async {
    V3Icons headerIcon() => tester
        .widget<V3Icon>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('SET A NUMBER'),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byType(V3Icon),
          ),
        )
        .icon;
    Future<void> show(Map<String, Object?> json) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_composer(json, (_) {}));
      await tester.pump();
    }

    const count = <String, Object?>{
      'version': 1,
      'kind': 'number',
      'answer_key': 'practice_volume',
      'min': 0,
      'max': 50,
      'step': 1,
      'initial': 3,
      'unit': 'pieces of work',
    };
    await show(count);
    expect(headerIcon(), V3Icons.list);
    await show({...count, 'unit': null});
    expect(headerIcon(), V3Icons.list);

    await show(_weeklyHours);
    expect(headerIcon(), V3Icons.clock);
    await show({...count, 'answer_key': 'session', 'unit': 'minutes a day'});
    expect(headerIcon(), V3Icons.clock);
    await show({...count, 'answer_key': 'focus', 'unit': 'hrs'});
    expect(headerIcon(), V3Icons.clock);
  });

  testWidgets('finishing shows the closing line and Open the mentor lab', (
    tester,
  ) async {
    final repository = _FinishingRepository();
    var done = 0;
    await tester.pumpWidget(
      _step(
        repository,
        CmpysOnboardingDraft()..sessionId = 'session-1',
        onDone: () => done++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('intake-text-input')),
      'A memo I can show',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intake-text-submit')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Your starting point is saved.'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(done, 0);
    await tester.tap(find.text('Open the mentor lab'));
    await tester.pump();
    expect(done, 1);

    await tester.pumpWidget(const SizedBox());
  });

  test(
    'the interview request carries missing_evidence only when set',
    () async {
      final client = _SseClient();
      final repository = SessionRepository(dioClient: client);
      await repository
          .sendInterviewMessage(
            's1',
            'I don’t have one yet',
            questionId: 'q1',
            missingEvidence: true,
          )
          .toList();
      await repository
          .sendInterviewMessage('s1', 'Plain', questionId: 'q2')
          .toList();

      expect(client.bodies, [
        {
          'content': 'I don’t have one yet',
          'is_kickoff': false,
          'question_id': 'q1',
          'missing_evidence': true,
        },
        {'content': 'Plain', 'is_kickoff': false, 'question_id': 'q2'},
      ]);
    },
  );
}

Widget _step(
  SessionRepository repository,
  CmpysOnboardingDraft draft, {
  VoidCallback? onDone,
}) {
  return ProviderScope(
    overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Scaffold(
        body: CmpysIntakeChatStep(
          idol: defaultIdol(),
          draft: draft,
          onDone: onDone ?? () {},
        ),
      ),
    ),
  );
}

const _session = Session(
  id: 'session-1',
  phase: SessionPhase.interview,
  userAge: 24,
  userFinancialStatus: 'employed',
  userInterests: ['Investing'],
);

abstract class _Recording extends Fake implements SessionRepository {
  final answers = <String>[];
  final missingFlags = <bool>[];
  final answeredQuestionIds = <String?>[];

  @override
  Future<Session> getSession(String sessionId) async => _session;

  Map<String, Object?> get kickoffDone;
  String get kickoffQuestion;
  List<Map<String, Object?>> afterAnswer(String content);

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
    String? questionId,
    bool missingEvidence = false,
  }) async* {
    if (isKickoff) {
      yield {'type': 'chunk', 'content': kickoffQuestion};
      yield Map<String, dynamic>.from(kickoffDone);
      return;
    }
    answers.add(content);
    missingFlags.add(missingEvidence);
    answeredQuestionIds.add(questionId);
    for (final event in afterAnswer(content)) {
      yield Map<String, dynamic>.from(event);
    }
  }
}

class _WorkSampleRepository extends _Recording {
  @override
  String get kickoffQuestion => 'Show me some work.';

  @override
  Map<String, Object?> get kickoffDone => {
    'type': 'done',
    'turn': 2,
    'max_turns': 13,
    'phase_transition': false,
    'question_id': 'work-sample',
    'response_ui': {
      'version': 1,
      'kind': 'text',
      'answer_key': 'work_sample',
      'placeholder': 'Paste or describe your work…',
      'suggestions': ['I wrote a short memo'],
      'missing_option': 'I don’t have one yet',
    },
  };

  @override
  List<Map<String, Object?>> afterAnswer(String content) => [
    {'type': 'chunk', 'content': 'How do you check yourself?'},
    {
      'type': 'done',
      'turn': 3,
      'max_turns': 13,
      'phase_transition': false,
      'question_id': 'self-check',
      'response_ui': {
        'version': 1,
        'kind': 'single_choice',
        'options': ['I compare with a trusted source', 'I don’t really check'],
      },
    },
  ];
}

class _UnknownKindRepository extends _Recording {
  @override
  String get kickoffQuestion => 'Which days suit you?';

  @override
  Map<String, Object?> get kickoffDone => {
    'type': 'done',
    'turn': 1,
    'max_turns': 13,
    'phase_transition': false,
    'question_id': 'days',
    'response_ui': {
      'version': 1,
      'kind': 'calendar',
      'options': ['Mon', 'Tue'],
    },
  };

  @override
  List<Map<String, Object?>> afterAnswer(String content) => [
    {'type': 'chunk', 'content': 'Noted.'},
    {
      'type': 'done',
      'turn': 2,
      'max_turns': 13,
      'phase_transition': false,
      'question_id': 'next',
      'response_ui': {'version': 1, 'kind': 'text'},
    },
  ];
}

class _FinishingRepository extends _Recording {
  @override
  String get kickoffQuestion => 'What single result would make this worth it?';

  @override
  Map<String, Object?> get kickoffDone => {
    'type': 'done',
    'turn': 12,
    'max_turns': 13,
    'phase_transition': false,
    'question_id': 'target',
    'response_ui': {'version': 1, 'kind': 'text'},
  };

  @override
  List<Map<String, Object?>> afterAnswer(String content) => [
    {'type': 'chunk', 'content': 'Your starting point is saved.'},
    {'type': 'done', 'turn': 13, 'max_turns': 13, 'phase_transition': true},
  ];
}

class _SseClient extends Fake implements DioClient {
  final bodies = <Object?>[];

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
  }) async {
    bodies.add(data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          ResponseBody.fromString(
                'data: {"type":"done","turn":1,"max_turns":13,'
                '"phase_transition":false}\n\n',
                200,
              )
              as T,
    );
  }
}
