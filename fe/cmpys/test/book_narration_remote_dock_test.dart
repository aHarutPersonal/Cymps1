import 'dart:async';

import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the player names the tab the reader was opened in (R3-M9)', () {
    expect(bookNarrationOrigin(0), 'Today');
    expect(bookNarrationOrigin(1), 'Plan');
    expect(bookNarrationOrigin(4), 'You');
    // Unknown (an older session): the Plan, as before.
    expect(bookNarrationOrigin(null), 'Plan');
  });

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

  testWidgets('dock shows the book, stays accessible and keeps 44 pt '
      'targets on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    final controller = BookNarrationRemoteController();
    addTearDown(controller.dispose);
    final owner = Object();
    var toggles = 0;
    var opened = 0;
    controller.attach(
      ownerToken: owner,
      onToggle: () async => toggles++,
      onPrevious: () async {},
      onNext: () async {},
      onSeek: (_) async {},
      onStyleChanged: (_) async {},
      onSpeedChanged: (_) async {},
      onStop: () async {},
      progress: .35,
      semanticText: 'Chapter one, sentence four',
      resourceId: 'book-1',
      title: 'A very long book title that has to be cut to fit the dock',
      author: 'A. Author',
      chapterIndex: 0,
      duration: const Duration(minutes: 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: BookNarrationDock(
                controller: controller,
                onOpen: () => opened++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final player = find.byKey(BookNarrationDock.dockKey);
    expect(player, findsOneWidget);
    expect(tester.getSize(player).height, BookNarrationDock.preferredHeight);
    expect(find.text('Ch. 1 · 1:03 / 3:00 · 1×'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Audiobook controls' &&
            (widget.properties.value ?? '').contains('Chapter one'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    final play = find.byKey(const Key('book-narration-play-pause'));
    expect(tester.getSize(play).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(play).height, greaterThanOrEqualTo(44));

    await tester.tap(play);
    await tester.pump();
    expect(toggles, 1);
    expect(opened, 0);
    await tester.tap(player);
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
