import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/onboarding_flow.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/personalize_step.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// CMPYS v3 personal context (`v3/onboard.jsx` Context + AgeWheel): four steps
// (name + age wheel, interests, goal, situation) with a 4-segment progress bar
// and an "N / 4" counter. The situation answers travel in POST /sessions.

class _Sessions extends Fake implements SessionRepository {
  final created = <Map<String, dynamic>>[];

  @override
  Future<Session?> getLatestSession() async => null;

  @override
  Future<void> abandonCurrentSession() async {}

  @override
  Future<Session> createSession(SessionCreateRequest request) async {
    created.add(request.toJson());
    return const Session(
      id: 'new-session',
      phase: SessionPhase.idolSelection,
      userAge: 24,
      userFinancialStatus: '',
      userInterests: [],
    );
  }

  @override
  Future<List<IdolSuggestion>> suggestIdols(String id) async => [
    IdolSuggestion.fromJson({
      'name': 'John D. Rockefeller',
      'domains': ['business'],
      'confidence': 0.95,
    }),
  ];
}

Future<void> _mountStep(
  WidgetTester tester,
  CmpysOnboardingDraft draft, {
  VoidCallback? onDone,
  VoidCallback? onBack,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: CmpysPersonalizeStep(
          draft: draft,
          onUpdate: (_) {},
          onDone: onDone ?? () {},
          onBack: onBack,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _continueDisabled(WidgetTester tester) =>
    tester.widget<V3Button>(find.byType(V3Button)).disabled;

Future<void> _tapContinue(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  // The next step slides in over .55 s and its chips rise in a stagger.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Distance from [offset] to the nearest multiple of the 58 pt number width.
/// The ballistic spring settles within one pixel of the target.
double _offSnap(double offset) {
  final rest = offset % CmpysAgeWheel.itemWidth;
  return math.min(rest, CmpysAgeWheel.itemWidth - rest);
}

Finder _wheelSemantics() => find.descendant(
  of: find.byType(CmpysAgeWheel),
  matching: find.bySemanticsLabel('Age'),
);

void main() {
  testWidgets('continue_disabled_until_step_valid', (tester) async {
    final draft = CmpysOnboardingDraft();
    var done = 0;
    await _mountStep(tester, draft, onDone: () => done++);

    // Step 1: a name (the wheel already holds 24).
    expect(find.text('1 / 4'), findsOneWidget);
    expect(_continueDisabled(tester), isTrue);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget, reason: 'blocked without name');
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(_continueDisabled(tester), isTrue, reason: 'blank name');
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    expect(_continueDisabled(tester), isFalse);
    await _tapContinue(tester, 'Continue');

    // Step 2: at least one interest.
    expect(find.text('2 / 4'), findsOneWidget);
    expect(_continueDisabled(tester), isTrue);
    await tester.tap(find.text('Investing'));
    await tester.pump();
    expect(_continueDisabled(tester), isFalse);
    await tester.tap(find.text('Investing'));
    await tester.pump();
    expect(_continueDisabled(tester), isTrue, reason: 'deselected again');
    await tester.tap(find.text('Investing'));
    await tester.pump();
    await _tapContinue(tester, 'Continue');

    // Step 3: a goal longer than four trimmed characters.
    expect(find.text('3 / 4'), findsOneWidget);
    expect(_continueDisabled(tester), isTrue);
    await tester.enterText(find.byType(TextField), '  abcd  ');
    await tester.pump();
    expect(_continueDisabled(tester), isTrue, reason: '4 trimmed characters');
    await tester.enterText(find.byType(TextField), '  abcde  ');
    await tester.pump();
    expect(_continueDisabled(tester), isFalse);
    await _tapContinue(tester, 'Continue');

    // Step 4: always valid, and the last button has its own label.
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(_continueDisabled(tester), isFalse);
    expect(done, 0);
    await tester.tap(find.text('Find my mentors'));
    await tester.pump();
    expect(done, 1);

    expect(draft.name, 'Ada');
    expect(draft.age, 24);
    expect(draft.interests, {'Investing'});
    expect(draft.goal.trim(), 'abcde');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('continue_disabled_until_step_valid: suggestion fills the goal', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()
      ..name = 'Ada'
      ..interests = {'Writing'};
    await _mountStep(tester, draft);
    await _tapContinue(tester, 'Continue');
    await _tapContinue(tester, 'Continue');

    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.text('Or start from'.toUpperCase()), findsOneWidget);
    expect(_continueDisabled(tester), isTrue);
    await tester.tap(find.text('Become a sharper decision-maker'));
    await tester.pump();
    expect(_continueDisabled(tester), isFalse);
    expect(draft.goal, 'Become a sharper decision-maker');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Become a sharper decision-maker',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back steps backwards and step 0 only leaves when asked', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()
      ..name = 'Ada'
      ..interests = {'Writing'};
    var left = 0;
    await _mountStep(tester, draft);
    // As before, the first step has no back button unless the flow gives one.
    expect(find.byType(V3IconButton), findsNothing);
    await _tapContinue(tester, 'Continue');
    expect(find.text('2 / 4'), findsOneWidget);
    await tester.tap(find.byType(V3IconButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await _mountStep(tester, draft, onBack: () => left++);
    await tester.tap(find.byType(V3IconButton));
    await tester.pump();
    expect(left, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('steps slide in 40 px from the side they came from', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()
      ..name = 'Ada'
      ..interests = {'Writing'};
    await _mountStep(tester, draft);
    await _tapContinue(tester, 'Continue');
    final settled = tester.getTopLeft(find.text('Investing')).dx;

    // Back: the earlier step comes in from the left.
    await tester.tap(find.byType(V3IconButton));
    await tester.pump();
    await tester.pump();
    final nameAtStart = tester.getTopLeft(find.text('First name')).dx;
    await tester.pumpAndSettle();
    final nameSettled = tester.getTopLeft(find.text('First name')).dx;
    expect(nameAtStart, closeTo(nameSettled - 40, 1));

    // Forward: the next step comes in from the right and settles in .55 s.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Investing')).dx,
      closeTo(settled + 40, 1),
    );
    await tester.pump(const Duration(milliseconds: 550));
    expect(tester.getTopLeft(find.text('Investing')).dx, closeTo(settled, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows each step in place at once', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()
      ..name = 'Ada'
      ..interests = {'Writing'};
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: CmpysPersonalizeStep(
            draft: draft,
            onUpdate: (_) {},
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('2 / 4'), findsOneWidget);
    // 24 pt gutter + the chip's 1 pt border and 15 pt padding.
    expect(tester.getTopLeft(find.text('Investing')).dx, closeTo(40, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('age_wheel_snaps_and_updates', (tester) async {
    final draft = CmpysOnboardingDraft();
    await _mountStep(tester, draft);

    double sizeOf(String n) => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(n),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style
        .fontSize!;
    Color colorOf(String n) => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(n),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style
        .color!;

    final wheel = find.byType(ListWheelScrollView);
    expect(wheel, findsOneWidget);
    final controller =
        tester.widget<ListWheelScrollView>(wheel).controller!
            as FixedExtentScrollController;

    // Starts on the stored age: 30 pt white on the pill, the rest 20 pt ink3.
    expect(controller.selectedItem, 24 - 14);
    expect(sizeOf('24'), 30);
    expect(colorOf('24'), Colors.white);
    expect(sizeOf('23'), 20);
    expect(colorOf('23'), AppColors.ink3);
    expect(
      find.text(
        'Age is context for comparison: what your mentor had done by 24. '
        'It is never used to rank you.',
      ),
      findsOneWidget,
    );

    // A drag that stops between numbers snaps onto one and updates the age.
    await tester.drag(wheel, const Offset(-100, 0));
    await tester.pumpAndSettle();
    final snapped = controller.selectedItem + 14;
    expect(snapped, greaterThan(24), reason: 'dragging left raises the age');
    expect(_offSnap(controller.offset), lessThan(1), reason: 'snaps to 58 pt');
    expect(draft.age, snapped);
    expect(sizeOf('$snapped'), 30);
    expect(sizeOf('24'), 20);
    expect(find.textContaining('had done by $snapped.'), findsOneWidget);

    // Dragging back lowers it again.
    await tester.drag(wheel, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(draft.age, lessThan(snapped));
    expect(_offSnap(controller.offset), lessThan(1));
    expect(draft.age, controller.selectedItem + 14);

    // The ends are 14 and 80.
    await tester.fling(wheel, const Offset(3000, 0), 6000);
    await tester.pumpAndSettle();
    expect(draft.age, 14);
    await tester.fling(wheel, const Offset(-9000, 0), 9000);
    await tester.pumpAndSettle();
    expect(draft.age, 80);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('age wheel starts on the stored age and exposes semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final draft = CmpysOnboardingDraft()..age = 41;
    await _mountStep(tester, draft);
    final controller =
        tester
                .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
                .controller!
            as FixedExtentScrollController;
    expect(controller.selectedItem, 41 - 14);

    final node = tester.getSemantics(_wheelSemantics());
    expect(
      node,
      matchesSemantics(
        label: 'Age',
        value: '41',
        increasedValue: '42',
        decreasedValue: '40',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    void perform(ui.SemanticsAction action) {
      tester.binding.performSemanticsAction(
        ui.SemanticsActionEvent(
          type: action,
          nodeId: tester.getSemantics(_wheelSemantics()).id,
          viewId: tester.view.viewId,
        ),
      );
    }

    perform(ui.SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(draft.age, 42);
    perform(ui.SemanticsAction.decrease);
    await tester.pumpAndSettle();
    perform(ui.SemanticsAction.decrease);
    await tester.pumpAndSettle();
    expect(draft.age, 40);
    expect(_offSnap(controller.offset), lessThan(1));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stored age outside 14-80 is clamped onto the wheel', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()..age = 9;
    await _mountStep(tester, draft);
    final controller =
        tester
                .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
                .controller!
            as FixedExtentScrollController;
    expect(controller.selectedItem, 0);
    expect(draft.age, 14);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('situation_sent_in_session_create', (tester) async {
    // Wide enough for the discovery screen (restyled in C4) not to overflow
    // under the test font.
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Sessions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: CmpysOnboardingFlow()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await _tapContinue(tester, 'Continue');
    await tester.tap(find.text('Writing'));
    await tester.tap(find.text('Investing'));
    await tester.pump();
    await _tapContinue(tester, 'Continue');
    await tester.enterText(find.byType(TextField), 'Write clearer memos');
    await tester.pump();
    await _tapContinue(tester, 'Continue');

    expect(find.text('4 / 4'), findsOneWidget);
    await tester.tap(find.text('I work full-time'));
    await tester.tap(find.text('Evenings are best'));
    await tester.tap(find.text('I’m a student'));
    await tester.tap(find.text('I’m a student'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  Two kids at home.  ');
    await tester.pump();
    await tester.tap(find.text('Find my mentors'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
    final body = repo.created.single;
    expect(body['age'], 24);
    expect(body['interests'], unorderedEquals(['Writing', 'Investing']));
    expect(body['goal'], 'Write clearer memos');
    expect(body['financial_status'], 'not_specified');
    expect(body['situation'], ['I work full-time', 'Evenings are best']);
    expect(body['situation_note'], 'Two kids at home.');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a goal that is a known goal still derives financial status', (
    tester,
  ) async {
    // Wide enough for the discovery screen (restyled in C4) not to overflow
    // under the test font.
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Sessions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          currentUserProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: CmpysOnboardingFlow()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await _tapContinue(tester, 'Continue');
    await tester.tap(find.text('Writing'));
    await tester.pump();
    await _tapContinue(tester, 'Continue');
    await tester.enterText(find.byType(TextField), 'Build wealth');
    await tester.pump();
    await _tapContinue(tester, 'Continue');
    await tester.tap(find.text('Find my mentors'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final body = repo.created.single;
    expect(body['financial_status'], 'building_wealth');
    expect(body['goal'], 'Build wealth');
    // Nothing chosen on the last step: the optional fields stay out.
    expect(body.containsKey('situation'), isFalse);
    expect(body.containsKey('situation_note'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('SessionCreateRequest keeps situation inside the backend limits', () {
    final json = SessionCreateRequest(
      age: 30,
      financialStatus: 'not_specified',
      interests: const ['Writing'],
      goal: '  ${'g' * 300}  ',
      situation: ['  ', ...List.generate(10, (i) => 'Item $i'), 'x' * 90],
      situationNote: 'n' * 600,
    ).toJson();
    expect((json['goal'] as String).length, 200);
    final situation = json['situation'] as List;
    expect(situation, hasLength(8));
    expect(situation.first, 'Item 0');
    expect(situation.every((s) => (s as String).trim().isNotEmpty), isTrue);
    expect((json['situation_note'] as String).length, 500);

    final blank = const SessionCreateRequest(
      age: 30,
      financialStatus: 'not_specified',
      interests: ['Writing'],
      situation: ['   '],
      situationNote: '   ',
    ).toJson();
    expect(blank.containsKey('situation'), isFalse);
    expect(blank.containsKey('situation_note'), isFalse);
  });

  for (final height in [667.0, 844.0]) {
    testWidgets(
      'fields stay visible above the footer while the keyboard is open '
      '(${height.toInt()} pt)',
      (tester) async {
        const keyboard = 336.0;
        final draft = CmpysOnboardingDraft()
          ..name = 'Ada'
          ..interests = {'Writing'}
          ..goal = 'Write clearer memos';
        await _mountStep(tester, draft, size: Size(390, height));
        addTearDown(tester.view.resetViewInsets);

        for (var step = 0; step < 4; step++) {
          final fields = find.byType(TextField);
          if (step != 1) {
            // Scroll the page to its end, as a user reaching the field would.
            final page = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(SingleChildScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            page.position.jumpTo(page.position.maxScrollExtent);
            await tester.pumpAndSettle();
            await tester.tap(fields);
            await tester.pump();
            tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
            await tester.pump();
            await tester.pumpAndSettle();
            final field = tester.getRect(find.byType(V3Field));
            final button = tester.getRect(find.byType(V3Button));
            expect(
              field.bottom,
              lessThanOrEqualTo(button.top),
              reason:
                  'step ${step + 1}: field $field is under the button $button',
            );
            expect(button.bottom, lessThanOrEqualTo(height - keyboard));
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();
          }
          if (step < 3) await _tapContinue(tester, 'Continue');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('all four steps fit a narrow phone at 200% text', (tester) async {
    final draft = CmpysOnboardingDraft()
      ..name = 'Ada'
      ..interests = {'Writing'}
      ..goal = 'Write clearer memos';
    await _mountStep(tester, draft, size: const Size(320, 568), textScale: 2);
    for (var i = 0; i < 4; i++) {
      expect(find.text('${i + 1} / 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (i < 3) await _tapContinue(tester, 'Continue');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
