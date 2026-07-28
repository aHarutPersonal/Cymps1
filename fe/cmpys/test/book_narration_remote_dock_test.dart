import 'dart:async';

import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'remote ownership prevents stale readers from mutating a new session',
    () async {
      final controller = BookNarrationRemoteController();
      addTearDown(controller.dispose);
      final firstOwner = Object();
      final secondOwner = Object();
      var firstToggleCalls = 0;
      var secondToggleCalls = 0;
      var firstStopCalls = 0;
      var firstReplacementCalls = 0;
      final firstStop = Completer<void>();
      double? soughtProgress;

      controller.attach(
        ownerToken: firstOwner,
        onToggle: () async => firstToggleCalls++,
        onPrevious: () async {},
        onNext: () async {},
        onSeek: (_) async {},
        onStyleChanged: (_) async {},
        onSpeedChanged: (_) async {},
        onStop: () async => firstStopCalls++,
        onReplaced: () {
          firstReplacementCalls++;
          return firstStop.future;
        },
        semanticText: 'First book',
      );
      controller.attach(
        ownerToken: secondOwner,
        onToggle: () async => secondToggleCalls++,
        onPrevious: () async {},
        onNext: () async {},
        onSeek: (progress) async => soughtProgress = progress,
        onStyleChanged: (_) async {},
        onSpeedChanged: (_) async {},
        onStop: () async {},
        progress: .25,
        semanticText: 'Second book',
        branchIndex: 3,
      );

      expect(controller.update(ownerToken: firstOwner, playing: true), isFalse);
      expect(controller.release(firstOwner), isFalse);
      expect(controller.semanticText, 'Second book');
      expect(controller.branchIndex, 3);
      expect(firstStopCalls, 0);
      expect(firstReplacementCalls, 1);

      firstStop.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.active, isTrue);
      expect(controller.semanticText, 'Second book');

      await controller.toggle();
      await controller.seek(2);

      expect(firstToggleCalls, 0);
      expect(secondToggleCalls, 1);
      expect(soughtProgress, 1);
      expect(controller.progress, 1);
    },
  );

  testWidgets(
    'dock is text-free, accessible, tappable, and uses 44px targets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final controller = BookNarrationRemoteController();
      addTearDown(controller.dispose);
      final owner = Object();
      double? soughtProgress;
      BookNarrationStyle? selectedStyle;
      controller.attach(
        ownerToken: owner,
        onToggle: () async {},
        onPrevious: () async {},
        onNext: () async {},
        onSeek: (progress) async => soughtProgress = progress,
        onStyleChanged: (style) async => selectedStyle = style,
        onSpeedChanged: (_) async {},
        onStop: () async {},
        progress: .35,
        semanticText: 'Chapter one, sentence four',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: BookNarrationDock(
                controller: controller,
                margin: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final player = find.byKey(const Key('book-narration-player'));
      expect(player, findsOneWidget);
      expect(
        find.descendant(of: player, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byTooltip('Previous sentence'), findsOneWidget);
      expect(find.byTooltip('Play narration'), findsOneWidget);
      expect(find.byTooltip('Next sentence'), findsOneWidget);
      expect(find.bySemanticsLabel('Audiobook controls'), findsOneWidget);

      for (final key in const [
        'book-narration-previous',
        'book-narration-play-pause',
        'book-narration-next',
        'book-narration-style',
        'book-narration-speed',
        'book-narration-options',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(44), reason: key);
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
      }

      final progress = find.byKey(const Key('book-narration-progress'));
      final progressRect = tester.getRect(progress);
      expect(progressRect.height, greaterThanOrEqualTo(44));
      final progressFill = find.byKey(
        const Key('book-narration-progress-fill'),
      );
      expect(tester.getSize(progressFill).height, 4);
      expect(
        tester.getSize(progressFill).width,
        closeTo((progressRect.width - 32) * .35, .01),
      );
      await tester.tapAt(
        Offset(
          progressRect.left + progressRect.width * .75,
          progressRect.top + 8,
        ),
      );
      await tester.pumpAndSettle();
      expect(soughtProgress, closeTo(.75, .01));

      await tester.tap(find.byKey(const Key('book-narration-style')));
      await tester.pumpAndSettle();
      expect(find.text('Warm'), findsOneWidget);
      expect(
        find.descendant(of: player, matching: find.byType(Text)),
        findsNothing,
      );
      await tester.tap(find.text('Warm'));
      await tester.pumpAndSettle();
      expect(selectedStyle, BookNarrationStyle.warm);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
