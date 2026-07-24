import 'dart:ui' as ui;

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/intake_answer_composer.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/intake_step.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/interview_response_ui.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _composerHarness(
  InterviewResponseUi responseUi,
  ValueChanged<String> onSubmit, {
  TextScaler? textScaler,
}) {
  return MaterialApp(
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: IntakeAnswerComposer(
            responseUi: responseUi,
            onSubmit: onSubmit,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('InterviewResponseUi', () {
    test('parses supported controls and falls back for unknown metadata', () {
      final choice = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'single_choice',
        'options': ['None yet', 'A peer', 'A mentor'],
        'allow_custom': false,
      });
      final number = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'number',
        'answer_key': 'weekly_hours',
        'min': 3,
        'max': 60,
        'step': 1,
        'initial': 8,
        'unit': 'hours per week',
      });
      final unknown = InterviewResponseUi.fromJson({
        'version': 2,
        'kind': 'calendar',
      });
      final preciseLargeRange = InterviewResponseUi.fromJson({
        'version': 1,
        'kind': 'number',
        'min': 999999.9999,
        'max': 1000000,
        'step': 0.0001,
        'initial': 999999.9999,
      });

      expect(choice.kind, InterviewResponseKind.singleChoice);
      expect(choice.options, ['None yet', 'A peer', 'A mentor']);
      expect(choice.allowCustom, isTrue);
      expect(number.kind, InterviewResponseKind.number);
      expect(number.min, 3);
      expect(number.initial, 8);
      expect(preciseLargeRange.kind, InterviewResponseKind.number);
      expect(unknown.kind, InterviewResponseKind.text);
      expect(
        InterviewResponseUi.fromJson({
          'version': 1.5,
          'kind': 'single_choice',
          'options': ['A', 'B'],
        }).kind,
        InterviewResponseKind.text,
      );
    });

    test('invalid ranges and choices fall back to text', () {
      expect(
        InterviewResponseUi.fromJson({
          'version': 1,
          'kind': 'single_choice',
          'options': ['Only one'],
        }).kind,
        InterviewResponseKind.text,
      );
      for (final invalidNumber in [
        {'min': 0, 'max': 10, 'step': 20},
        {'min': 0, 'max': 10, 'step': 3},
        {'min': 0, 'max': 1, 'step': 0.00001},
        {'min': 0, 'max': 10, 'step': 2, 'initial': 1},
        {'min': -1000000, 'max': 1000000, 'step': 2000},
        {'min': 0, 'max': 1e308, 'step': 1},
        {'min': -1000001, 'max': 0, 'step': 1},
      ]) {
        expect(
          InterviewResponseUi.fromJson({
            'version': 1,
            'kind': 'number',
            ...invalidNumber,
          }).kind,
          InterviewResponseKind.text,
        );
      }
      expect(
        InterviewResponseUi.fromJson({
          'version': 1,
          'kind': 'number',
          'min': 10,
          'max': 2,
          'step': 1,
        }).kind,
        InterviewResponseKind.text,
      );
    });
  });

  testWidgets('choice requires selection and confirmation before submitting', (
    tester,
  ) async {
    final submitted = <String>[];
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'single_choice',
      'options': ['None yet', 'A peer', 'A mentor'],
    });

    await tester.pumpWidget(_composerHarness(responseUi, submitted.add));

    expect(find.byType(TextField), findsNothing);
    expect(find.text('None yet'), findsOneWidget);
    expect(find.text('Send answer'), findsOneWidget);

    await tester.tap(find.text('A peer'));
    await tester.pump();
    expect(submitted, isEmpty);

    await tester.tap(find.text('Send answer'));
    await tester.pump();
    expect(submitted, ['A peer']);
  });

  testWidgets('choice controls are keyboard operable', (tester) async {
    final submitted = <String>[];
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'single_choice',
      'options': ['A peer', 'A mentor'],
    });

    await tester.pumpWidget(_composerHarness(responseUi, submitted.add));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(submitted, ['A peer']);
  });

  testWidgets('keyboard repeat does not reactivate a pressable', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmpysPressable(
            onTap: () => activations++,
            child: const Text('Activate'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('numpad enter activates a focused pressable', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmpysPressable(
            onTap: () => activations++,
            child: const Text('Activate'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('remote select activates a focused pressable', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmpysPressable(
            onTap: () => activations++,
            child: const Text('Activate'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(activations, 1);
  });

  testWidgets('number stepper submits an exact natural-language answer', (
    tester,
  ) async {
    final submitted = <String>[];
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'number',
      'min': 2,
      'max': 10,
      'step': 2,
      'initial': 8,
      'unit': 'hours per week',
    });

    await tester.pumpWidget(_composerHarness(responseUi, submitted.add));

    expect(find.text('8'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('intake-number-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intake-number-plus')));
    await tester.pump();
    expect(find.text('10'), findsOneWidget);

    // The upper-bound action is disabled and cannot exceed the contract.
    await tester.tap(find.byKey(const ValueKey('intake-number-plus')));
    await tester.pump();
    expect(find.text('10'), findsOneWidget);

    await tester.tap(find.text('Send answer'));
    await tester.pump();
    expect(submitted, ['10 hours per week']);
  });

  testWidgets('weekly-hours picker enforces the three-hour lower boundary', (
    tester,
  ) async {
    final submitted = <String>[];
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'number',
      'answer_key': 'weekly_hours',
      'min': 3,
      'max': 60,
      'step': 1,
      'initial': 3,
      'unit': 'hours per week',
    });

    await tester.pumpWidget(_composerHarness(responseUi, submitted.add));

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('intake-number-minus')));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Send answer'));
    await tester.pump();
    expect(submitted, ['3 hours per week']);
  });

  testWidgets('number picker exposes adjustable value semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'number',
      'min': 2,
      'max': 10,
      'step': 2,
      'initial': 8,
      'unit': 'hours per week',
    });

    await tester.pumpWidget(_composerHarness(responseUi, (_) {}));
    final finder = find.byKey(const ValueKey('intake-number-adjustable'));
    final node = tester.getSemantics(finder);
    expect(
      node,
      matchesSemantics(
        label: 'Selected number',
        value: '8 hours per week',
        increasedValue: '10 hours per week',
        decreasedValue: '6 hours per week',
        isSlider: true,
        isLiveRegion: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.increase,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();

    expect(find.text('10'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('number picker scrolls on a short screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'number',
      'min': 2,
      'max': 10,
      'step': 2,
      'initial': 8,
      'unit': 'hours per week',
    });

    await tester.pumpWidget(
      _composerHarness(
        responseUi,
        (_) {},
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('number-answer')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('structured controls always offer a free-text path', (
    tester,
  ) async {
    final submitted = <String>[];
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'single_choice',
      'options': ['A', 'B'],
    });

    await tester.pumpWidget(_composerHarness(responseUi, submitted.add));
    await tester.tap(find.text('Write my own'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Back to choices'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'It is more complicated.');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intake-text-submit')));
    await tester.pump();
    expect(submitted, ['It is more complicated.']);
  });

  testWidgets('six choices remain usable on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'single_choice',
      'options': [
        'No support yet',
        'A trusted peer',
        'An experienced mentor',
        'A small community',
        'A professional network',
        'Several collaborators',
      ],
    });

    await tester.pumpWidget(
      _composerHarness(
        responseUi,
        (_) {},
        textScaler: const TextScaler.linear(1.3),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CHOOSE ONE'), findsOneWidget);
  });

  testWidgets('choice confirmation stacks at accessibility text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final responseUi = InterviewResponseUi.fromJson({
      'version': 1,
      'kind': 'single_choice',
      'options': ['A peer', 'An experienced mentor'],
    });

    await tester.pumpWidget(
      _composerHarness(
        responseUi,
        (_) {},
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Write my own'), findsOneWidget);
    expect(find.text('Send answer'), findsOneWidget);
  });

  testWidgets(
    'intake consumes response metadata and sends the selected label',
    (tester) async {
      final repository = _ResponseUiRepository();
      final draft = CmpysOnboardingDraft()..sessionId = 'session-1';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: CmpysIntakeChatStep(
                idol: defaultIdol(),
                draft: draft,
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('What keeps you accountable?'), findsOneWidget);
      expect(find.text('A mentor'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('A mentor'));
      await tester.pump();
      await tester.tap(find.text('Send answer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.answers, ['A mentor']);
      expect(repository.answeredQuestionIds, ['question-1']);
      expect(find.text('A mentor'), findsOneWidget);
      expect(draft.intakeAnswers['question-1'], 'A mentor');

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stale answer conflict resyncs to the current question', (
    tester,
  ) async {
    final repository = _StaleQuestionRepository();
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: CmpysIntakeChatStep(
              idol: defaultIdol(),
              draft: draft,
              onDone: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('A peer'));
    await tester.pump();
    await tester.tap(find.text('Send answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.kickoffs, 2);
    expect(repository.answeredQuestionIds, ['question-1']);
    expect(find.text('What is the current constraint?'), findsOneWidget);
    expect(find.text('A peer'), findsNothing);
    expect(draft.intakeAnswers.containsKey('question-1'), isFalse);
    expect(find.text('Retry'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('superseded stream resyncs to the current question', (
    tester,
  ) async {
    final repository = _StaleQuestionRepository(streamConflict: true);
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: CmpysIntakeChatStep(
              idol: defaultIdol(),
              draft: draft,
              onDone: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('A peer'));
    await tester.pump();
    await tester.tap(find.text('Send answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.kickoffs, 2);
    expect(find.text('What is the current constraint?'), findsOneWidget);
    expect(find.textContaining('Obsolete partial'), findsNothing);
    expect(find.text('Retry'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uncoded conflict discards the rejected answer before resync', (
    tester,
  ) async {
    final repository = _StaleQuestionRepository(uncodedConflict: true);
    final draft = CmpysOnboardingDraft()..sessionId = 'session-1';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: CmpysIntakeChatStep(
              idol: defaultIdol(),
              draft: draft,
              onDone: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('A peer'));
    await tester.pump();
    await tester.tap(find.text('Send answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.kickoffs, 2);
    expect(find.text('What is the current constraint?'), findsOneWidget);
    expect(find.text('A peer'), findsNothing);
    expect(draft.intakeAnswers.containsKey('question-1'), isFalse);
    expect(find.text('Retry'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'invalid custom hours stay editable without replaying the question',
    (tester) async {
      final repository = _InvalidHoursRepository();
      final draft = CmpysOnboardingDraft()..sessionId = 'session-1';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: CmpysIntakeChatStep(
                idol: defaultIdol(),
                draft: draft,
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('Type instead'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField), 'I am not sure');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('intake-text-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      const question = 'How many focused hours can you protect each week?';
      const validation = 'Choose a weekly commitment between 3 and 60 hours.';
      expect(repository.kickoffs, 1);
      expect(find.text(question), findsOneWidget);
      expect(find.text(validation), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'I am not sure',
      );
      expect(draft.intakeAnswers.containsKey('hours-question'), isFalse);
      expect(find.text('Retry'), findsNothing);

      await tester.tap(find.text('Back to number picker'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('8'), findsOneWidget);
      await tester.tap(find.text('Type instead'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(validation), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.text('Back to number picker'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Send answer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(repository.answers, ['I am not sure', '8 hours per week']);
      expect(repository.answeredQuestionIds, [
        'hours-question',
        'hours-question',
      ]);
      expect(draft.intakeAnswers['hours-question'], '8 hours per week');
      expect(find.text(question), findsOneWidget);
      expect(find.text('I am not sure'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _ResponseUiRepository extends Fake implements SessionRepository {
  final answers = <String>[];
  final answeredQuestionIds = <String?>[];

  Session get _session => const Session(
    id: 'session-1',
    phase: SessionPhase.interview,
    userAge: 28,
    userFinancialStatus: 'employed',
    userInterests: ['Technology'],
  );

  @override
  Future<Session> getSession(String sessionId) async => _session;

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
    String? questionId,
  }) async* {
    if (isKickoff) {
      yield {'type': 'chunk', 'content': 'What keeps you accountable?'};
      yield {
        'type': 'done',
        'turn': 1,
        'max_turns': 5,
        'phase_transition': false,
        'question_id': 'question-1',
        'response_ui': {
          'version': 1,
          'kind': 'single_choice',
          'options': ['No one yet', 'A peer', 'A mentor'],
          'allow_custom': true,
        },
      };
      return;
    }

    answers.add(content);
    answeredQuestionIds.add(questionId);
    yield {'type': 'chunk', 'content': 'That gives me a clear picture.'};
    yield {'type': 'done', 'turn': 2, 'max_turns': 5, 'phase_transition': true};
  }
}

class _StaleQuestionRepository extends Fake implements SessionRepository {
  _StaleQuestionRepository({
    this.streamConflict = false,
    this.uncodedConflict = false,
  });

  final bool streamConflict;
  final bool uncodedConflict;
  int kickoffs = 0;
  final answeredQuestionIds = <String?>[];

  Session get _session => const Session(
    id: 'session-1',
    phase: SessionPhase.interview,
    userAge: 28,
    userFinancialStatus: 'employed',
    userInterests: ['Technology'],
  );

  @override
  Future<Session> getSession(String sessionId) async => _session;

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
    String? questionId,
  }) async* {
    if (!isKickoff) {
      answeredQuestionIds.add(questionId);
      if (streamConflict) {
        yield {'type': 'chunk', 'content': 'Obsolete '};
        yield {'type': 'chunk', 'content': 'partial reply'};
        yield {
          'type': 'error',
          'code': 'interview_turn_superseded',
          'message': 'A newer interview reply has taken over.',
        };
        return;
      }
      throw ApiError(
        message: 'This interview question is no longer active.',
        code: uncodedConflict ? null : 'stale_interview_question',
        statusCode: 409,
      );
    }

    kickoffs++;
    final first = kickoffs == 1;
    yield {
      'type': 'chunk',
      'content': first
          ? 'Who keeps you accountable?'
          : 'What is the current constraint?',
    };
    yield {
      'type': 'done',
      'turn': first ? 1 : 2,
      'max_turns': 5,
      'phase_transition': false,
      'question_id': first ? 'question-1' : 'question-2',
      'response_ui': {
        'version': 1,
        'kind': 'single_choice',
        'options': first ? ['A peer', 'A mentor'] : ['Time', 'Money'],
      },
    };
  }
}

class _InvalidHoursRepository extends Fake implements SessionRepository {
  int kickoffs = 0;
  final answers = <String>[];
  final answeredQuestionIds = <String?>[];

  Session get _session => const Session(
    id: 'session-1',
    phase: SessionPhase.interview,
    userAge: 28,
    userFinancialStatus: 'employed',
    userInterests: ['Technology'],
  );

  @override
  Future<Session> getSession(String sessionId) async => _session;

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
    String? questionId,
  }) async* {
    if (!isKickoff) {
      answers.add(content);
      answeredQuestionIds.add(questionId);
      if (content == 'I am not sure') {
        throw const ApiError(
          message: 'Choose a weekly commitment between 3 and 60 hours.',
          code: 'invalid_interview_answer',
          statusCode: 409,
        );
      }
      yield {'type': 'chunk', 'content': 'That is a workable commitment.'};
      yield {
        'type': 'done',
        'turn': 4,
        'max_turns': 8,
        'phase_transition': true,
      };
      return;
    }

    kickoffs++;
    yield {
      'type': 'chunk',
      'content': 'How many focused hours can you protect each week?',
    };
    yield {
      'type': 'done',
      'turn': 3,
      'max_turns': 8,
      'phase_transition': false,
      'question_id': 'hours-question',
      'response_ui': {
        'version': 1,
        'kind': 'number',
        'min': 3,
        'max': 60,
        'step': 1,
        'initial': 8,
        'unit': 'hours per week',
      },
    };
  }
}
