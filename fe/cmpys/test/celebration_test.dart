import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/presentation/achievement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// CMPYS v3 celebration overlay and "Suggested achievement" sheet
// (`Celebration` / `AchievementSheet` in `v3/app.jsx`).

Future<void> _host(
  WidgetTester tester,
  WidgetBuilder builder, {
  bool reduced = false,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: app!,
      ),
      home: Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: Builder(builder: builder)),
      ),
    ),
  );
}

/// Opens [celebration] from an "Open" button and records what it returns.
Future<void> _openCelebration(
  WidgetTester tester,
  Celebration celebration,
  List<CelebrationResult> results, {
  bool reduced = false,
  Size size = const Size(390, 844),
}) async {
  await _host(
    tester,
    (context) => TextButton(
      onPressed: () async =>
          results.add(await showCelebration(context, celebration)),
      child: const Text('Open'),
    ),
    reduced: reduced,
    size: size,
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  // Fade-in (.4 s) plus the staged entrances (the last starts at .85 s and
  // runs .7 s; the count-up ends at 1.3 s). Frame by frame, so every delayed
  // animation gets frames after its timer fires.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _achievementText =
    'Computed owner earnings for two businesses from their figures';

Celebration _tutorial({String? achievement = _achievementText}) =>
    Celebration.tutorial(
      completed: 4,
      total: 8,
      nextTitle: 'Maintenance versus growth capex',
      achievement: achievement,
    );

/// Opens the real "Suggested achievement" sheet from an "Open" button.
Future<void> _openSheet(
  WidgetTester tester, {
  String initial = 'Computed owner earnings',
  int? age = 24,
  required Future<void> Function(String title, String category) onSave,
  Future<AchievementSuggestion> Function()? loadSuggestion,
  List<bool?>? popped,
}) async {
  await _host(
    tester,
    (context) => TextButton(
      onPressed: () async {
        final saved = await AchievementSheet.show(
          context,
          initial: initial,
          age: age,
          onSave: onSave,
          loadSuggestion: loadSuggestion,
        );
        popped?.add(saved);
      },
      child: const Text('Open'),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder get _confirm => find.widgetWithText(V3Button, 'Confirm achievement');

void main() {
  group('Celebration copy', () {
    test('day celebration uses the design copy and streak + 1', () {
      final c = Celebration.day(6);
      expect(c.kind, CelebrationKind.day);
      expect(c.title, 'Today’s habits are done.');
      expect(c.sub, 'Recorded for today. They’ll be waiting again tomorrow.');
      expect(c.stat, 7);
      expect(c.statLabel, 'day streak');
      expect(c.achievement, isNull);
    });

    test('tutorial celebration names the next tutorial', () {
      final c = _tutorial();
      expect(c.kind, CelebrationKind.tutorial);
      expect(c.title, 'Tutorial 4 complete');
      expect(
        c.sub,
        'Both cases accepted. Tutorial 5, Maintenance versus growth capex, '
        'is now open.',
      );
      expect(c.stat, 4);
      expect(c.statLabel, 'of 8 tutorials');
      expect(c.achievement, _achievementText);
    });

    test('the last tutorial says the mission’s tutorials are done', () {
      for (final next in ['', '  ', 'Anything']) {
        final c = Celebration.tutorial(completed: 8, total: 8, nextTitle: next);
        expect(c.title, 'Tutorial 8 complete');
        expect(
          c.sub,
          'Both cases accepted. This mission’s tutorials are done.',
        );
        expect(c.statLabel, 'of 8 tutorials');
        expect(c.achievement, isNull);
      }
    });

    test('a blank next title never claims the tutorials are done', () {
      expect(
        Celebration.tutorial(completed: 2, total: 8, nextTitle: ' ').sub,
        'Both cases accepted. Tutorial 3 is now open.',
      );
    });

    test('a next tutorial still being written is "being prepared"', () {
      final c = Celebration.tutorial(
        completed: 2,
        total: 8,
        nextTitle: 'Cash and accrual on one page',
        nextReady: false,
      );
      expect(c.sub, 'Both cases accepted. Tutorial 3 is being prepared.');
      // The last one has no next tutorial to wait for.
      expect(
        Celebration.tutorial(
          completed: 8,
          total: 8,
          nextTitle: '',
          nextReady: false,
        ).sub,
        'Both cases accepted. This mission’s tutorials are done.',
      );
    });

    test('a blank achievement is no achievement', () {
      expect(_tutorial(achievement: '   ').achievement, isNull);
      expect(_tutorial(achievement: '   ').offersAchievement, isFalse);
      expect(_tutorial().offersAchievement, isTrue);
    });
  });

  group('showCelebration', () {
    testWidgets('tutorial_celebration_offers_add_to_record', (tester) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, _tutorial(), results);

      expect(find.text('Tutorial 4 complete'), findsOneWidget);
      expect(
        find.text(
          'Both cases accepted. Tutorial 5, Maintenance versus growth capex, '
          'is now open.',
        ),
        findsOneWidget,
      );
      // CountUp has landed on the stat; the label is uppercase.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('OF 8 TUTORIALS'), findsOneWidget);
      expect(find.byType(V3Confetti), findsOneWidget);

      final add = tester.widget<V3Button>(
        find.widgetWithText(V3Button, 'Add to your record'),
      );
      expect(add.kind, V3ButtonKind.primary);
      expect(add.icon, V3Icons.trophy);
      expect(add.full, isTrue);
      final keep = tester.widget<V3Button>(
        find.widgetWithText(V3Button, 'Continue'),
      );
      expect(keep.kind, V3ButtonKind.glass);

      // The overlay hands the choice back to the caller.
      await tester.tap(find.text('Add to your record'));
      await tester.pumpAndSettle();
      expect(results, [CelebrationResult.addToRecord]);
      expect(find.text('Tutorial 4 complete'), findsNothing);
    });

    testWidgets('continue returns continued even when it offers a record', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, _tutorial(), results);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(results, [CelebrationResult.continued]);
      expect(find.text('Tutorial 4 complete'), findsNothing);
    });

    testWidgets('without an achievement there is one light Continue', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, _tutorial(achievement: null), results);

      expect(find.text('Add to your record'), findsNothing);
      expect(find.byType(V3Button), findsOneWidget);
      expect(
        tester.widget<V3Button>(find.byType(V3Button)).kind,
        V3ButtonKind.light,
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(results, [CelebrationResult.continued]);
    });

    testWidgets('day celebration shows the flame, streak and design copy', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, Celebration.day(6), results);

      expect(find.text('Today’s habits are done.'), findsOneWidget);
      expect(
        find.text('Recorded for today. They’ll be waiting again tomorrow.'),
        findsOneWidget,
      );
      expect(find.text('7'), findsOneWidget);
      expect(find.text('DAY STREAK'), findsOneWidget);
      expect(find.text('Add to your record'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('closing with the system back button counts as continue', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, _tutorial(), results);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(results, [CelebrationResult.continued]);
    });

    testWidgets('reduced motion: no confetti, no breathing, final stat', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      await _host(
        tester,
        (context) => TextButton(
          onPressed: () async =>
              results.add(await showCelebration(context, _tutorial())),
          child: const Text('Open'),
        ),
        reduced: true,
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      // Everything is on screen on the first settled frame, with the stat at
      // its final value.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Tutorial 4 complete'), findsOneWidget);
      expect(find.text('Add to your record'), findsOneWidget);

      // No confetti, no halo, and (once the count-up's own clock has run
      // out) nothing keeps animating: the glow does not breathe.
      expect(find.byType(V3Confetti), findsNothing);
      expect(find.byKey(CelebrationOverlay.haloKey), findsNothing);
      expect(find.byKey(CelebrationOverlay.glowKey), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('4'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(results, [CelebrationResult.continued]);
    });

    testWidgets('motion on: the glow breathes and the halo plays', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, _tutorial(), results);

      expect(find.byKey(CelebrationOverlay.glowKey), findsOneWidget);
      expect(find.byKey(CelebrationOverlay.haloKey), findsOneWidget);
      // Both loop forever.
      expect(tester.hasRunningAnimations, isTrue);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    });

    testWidgets('a short screen keeps the content clear of the buttons', (
      tester,
    ) async {
      final results = <CelebrationResult>[];
      // iPhone SE sized, with the long tutorial copy and two buttons.
      await _openCelebration(
        tester,
        _tutorial(),
        results,
        size: const Size(320, 568),
      );

      // The content area (it scrolls if the copy is taller) ends above the
      // buttons and starts below the top edge, however long the copy is.
      final add = tester.getRect(find.byType(V3Button).first);
      final area = tester.getRect(find.byType(SingleChildScrollView));
      expect(area.top, greaterThanOrEqualTo(0));
      expect(area.bottom, lessThanOrEqualTo(add.top));
      expect(area.width, lessThanOrEqualTo(320));

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    });

    testWidgets('the overlay is a night, full-screen surface', (tester) async {
      final results = <CelebrationResult>[];
      await _openCelebration(tester, Celebration.day(0), results);

      final size = tester.view.physicalSize;
      final overlay = tester.getRect(find.byKey(CelebrationOverlay.pageKey));
      expect(overlay.size, size);
      expect(
        tester.widget<ColoredBox>(find.byKey(CelebrationOverlay.pageKey)).color,
        AppColors.night,
      );
      // 44 pt buttons clear of the content above them.
      final continueRect = tester.getRect(find.byType(V3Button));
      expect(continueRect.height, greaterThanOrEqualTo(44));
      expect(continueRect.bottom, lessThanOrEqualTo(size.height - 44 + 0.5));
      final title = tester.getRect(find.text('Today’s habits are done.'));
      expect(title.bottom, lessThan(continueRect.top));

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    });
  });

  group('AchievementSheet', () {
    testWidgets('shows the design copy, field and tags', (tester) async {
      await _openSheet(tester, onSave: (_, _) async {});

      expect(find.text('Suggested achievement'), findsOneWidget);
      expect(
        find.text(
          'Based on the work you just completed. Edit it so it’s true in '
          'your words.',
        ),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Computed owner earnings');
      expect(field.minLines, 2);
      expect(field.maxLines, 2);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Age 24'), findsOneWidget);
      expect(find.text('From plan completion'), findsOneWidget);
      expect(find.text('Confirm achievement'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('an unknown age leaves the age tag out', (tester) async {
      await _openSheet(tester, age: null, onSave: (_, _) async {});
      expect(find.textContaining('Age'), findsNothing);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('From plan completion'), findsOneWidget);
    });

    testWidgets('achievement_confirm_disabled_under_6_chars', (tester) async {
      final saved = <String>[];
      await _openSheet(
        tester,
        initial: '',
        onSave: (title, _) async => saved.add(title),
      );

      Future<void> type(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
      }

      // A disabled V3Button fades to .38 and drops its tap handler.
      bool enabled() =>
          tester
              .widget<AnimatedOpacity>(
                find.descendant(
                  of: _confirm,
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .opacity ==
          1;

      // Empty, five characters, and five characters padded with spaces
      // (length is counted after trimming) all stay disabled.
      for (final text in ['', 'abcde', '  abcde  ', '     ']) {
        await type(text);
        expect(enabled(), isFalse, reason: '"$text"');
        await tester.tap(_confirm, warnIfMissed: false);
        await tester.pump();
        expect(saved, isEmpty, reason: '"$text"');
      }

      // Six trimmed characters enable it, and the trimmed text is saved.
      await type('  abcdef ');
      expect(enabled(), isTrue);
      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(saved, ['abcdef']);
    });

    testWidgets('saving shows loading, ignores taps, then toasts and closes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final calls = <(String, String)>[];
      final popped = <bool?>[];
      await _openSheet(
        tester,
        popped: popped,
        onSave: (title, category) {
          calls.add((title, category));
          return gate.future;
        },
      );

      await tester.tap(_confirm);
      await tester.pump();
      // Loading: spinner instead of the label; further taps do nothing.
      expect(
        find.descendant(
          of: find.byType(V3Button).first,
          matching: find.byType(V3Spinner),
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm achievement'), findsNothing);
      await tester.tap(find.byType(V3Button).first, warnIfMissed: false);
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single, ('Computed owner earnings', 'other'));
      // Nothing closes the sheet mid-save, so the toast is never skipped:
      // Skip is disabled and the system back gesture is vetoed.
      await tester.tap(find.text('Skip'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Suggested achievement'), findsOneWidget);
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Suggested achievement'), findsOneWidget);
      expect(popped, isEmpty);

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(popped, [true]);
      expect(find.text('Suggested achievement'), findsNothing);
      expect(find.text('Achievement saved'), findsOneWidget);

      // Let the toast time out.
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
      expect(find.text('Achievement saved'), findsNothing);
    });

    testWidgets('a failed save keeps the sheet open with an inline error', (
      tester,
    ) async {
      var attempts = 0;
      final popped = <bool?>[];
      await _openSheet(
        tester,
        popped: popped,
        onSave: (_, _) async {
          attempts++;
          if (attempts == 1) throw Exception('offline');
        },
      );

      await tester.tap(_confirm);
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(popped, isEmpty);
      expect(find.text('Suggested achievement'), findsOneWidget);
      expect(find.text('Couldn\'t save - try again.'), findsOneWidget);
      expect(find.text('Achievement saved'), findsNothing);
      // Back to a usable button, with the text untouched.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Computed owner earnings',
      );
      expect(find.byType(V3Spinner), findsNothing);

      // Editing clears the error; retrying succeeds and closes.
      await tester.enterText(find.byType(TextField), 'Computed it again');
      await tester.pump();
      expect(find.text('Couldn\'t save - try again.'), findsNothing);
      await tester.tap(_confirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 2);
      expect(popped, [true]);

      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
    });

    testWidgets('skip closes without saving', (tester) async {
      var saves = 0;
      final popped = <bool?>[];
      await _openSheet(tester, popped: popped, onSave: (_, _) async => saves++);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(popped, [false]);
      expect(find.text('Suggested achievement'), findsNothing);
      expect(find.text('Achievement saved'), findsNothing);
    });

    testWidgets('the AI suggestion fills the field until the user types', (
      tester,
    ) async {
      final suggestion = Completer<AchievementSuggestion>();
      final calls = <(String, String)>[];
      await _openSheet(
        tester,
        onSave: (title, category) async => calls.add((title, category)),
        loadSuggestion: () => suggestion.future,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Computed owner earnings',
      );

      suggestion.complete((
        title: 'Valued two businesses from their statements',
        category: 'finance',
      ));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Valued two businesses from their statements',
      );

      await tester.tap(_confirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(calls, [
        ('Valued two businesses from their statements', 'finance'),
      ]);
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
    });

    testWidgets('a late suggestion never overwrites what the user typed', (
      tester,
    ) async {
      final suggestion = Completer<AchievementSuggestion>();
      await _openSheet(
        tester,
        onSave: (_, _) async {},
        loadSuggestion: () => suggestion.future,
      );

      await tester.enterText(find.byType(TextField), 'My own words here');
      await tester.pump();
      suggestion.complete((title: 'Late AI line', category: 'finance'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My own words here',
      );
    });

    testWidgets('a failed suggestion is silent', (tester) async {
      await _openSheet(
        tester,
        onSave: (_, _) async {},
        loadSuggestion: () async => throw Exception('no suggestion'),
      );
      expect(find.text('Suggested achievement'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Computed owner earnings',
      );
    });
  });
}
