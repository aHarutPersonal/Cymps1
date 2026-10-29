import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A remote session like the reader attaches: [duration] of narration, at
/// [progress], recording what the controls ask for.
class _Session {
  _Session(
    this.remote, {
    double progress = .25,
    bool playing = false,
    double speed = 1,
    String author = 'Warren Buffett',
    Duration duration = const Duration(seconds: 100),
    Future<void> Function()? onChapters,
  }) {
    remote.attach(
      ownerToken: owner,
      onToggle: () async {
        toggles++;
        remote.update(ownerToken: owner, playing: !remote.playing);
      },
      onPrevious: () async {},
      onNext: () async {},
      onSeek: (value) async => seeks.add(value),
      onStyleChanged: (_) async {},
      onSpeedChanged: (value) async => speeds.add(value),
      onStop: () async => stops++,
      onChapters: () async {
        chapters++;
        await onChapters?.call();
      },
      playing: playing,
      progress: progress,
      speed: speed,
      resourceId: 'essays',
      title: 'The Essays of Warren Buffett',
      author: author,
      chapterIndex: 5,
      chapterTitle: 'Owner earnings',
      duration: duration,
    );
  }

  final BookNarrationRemoteController remote;
  final Object owner = Object();
  final List<double> seeks = [];
  final List<double> speeds = [];
  int toggles = 0;
  int stops = 0;
  int chapters = 0;
}

Future<void> _mount(
  WidgetTester tester,
  BookNarrationRemoteController remote, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookNarrationRemoteControllerProvider.overrideWith((ref) => remote),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BookNarrationDock(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openPlayer(WidgetTester tester) async {
  // The cover side of the dock: the play button handles its own taps.
  final dock = tester.getRect(find.byKey(BookNarrationDock.dockKey));
  await tester.tapAt(Offset(dock.left + 30, dock.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('speed_cycles_in_design_order', (tester) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote);
    await _mount(tester, remote);
    await _openPlayer(tester);

    final speed = find.byKey(BookNarrationFullPlayer.speedKey);
    expect(
      find.descendant(of: speed, matching: find.text('1×')),
      findsOneWidget,
    );
    const labels = ['1.25×', '1.5×', '2×', '0.75×', '1×'];
    await tester.ensureVisible(speed);
    await tester.pumpAndSettle();
    for (final label in labels) {
      await tester.tap(speed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: speed, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(session.speeds, [1.25, 1.5, 2.0, 0.75, 1.0]);
    expect(nextBookNarrationSpeed(1), 1.25);
    // A speed outside the cycle (an old saved value) starts it again.
    expect(nextBookNarrationSpeed(1.75), 1);
  });

  testWidgets('dock_opens_full_player', (tester) async {
    final remote = BookNarrationRemoteController();
    _Session(remote, progress: .3);
    await _mount(tester, remote);

    final dock = find.byKey(BookNarrationDock.dockKey);
    expect(dock, findsOneWidget);
    expect(
      find.descendant(
        of: dock,
        matching: find.text('The Essays of Warren Buffett'),
      ),
      // The title line and the cover's printed title.
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dock, matching: find.text('Ch. 6 · 0:30 / 1:40 · 1×')),
      findsOneWidget,
    );
    expect(find.text('Now listening'), findsNothing);

    await _openPlayer(tester);
    expect(find.text('Now listening'), findsOneWidget);
    expect(find.byType(BookNarrationFullPlayer), findsOneWidget);
    expect(find.text('Chapter 6 · Owner earnings'), findsOneWidget);
    expect(find.byType(V3Cover), findsWidgets);
    expect(find.byType(BookNarrationWaves), findsWidgets);
    // Elapsed and −remaining, as the design's fmtT.
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('−1:10'), findsOneWidget);
    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(
      find.text('AI-generated voice. Not Warren Buffett’s voice.'),
      findsOneWidget,
    );

    // The chevron closes it again; narration keeps going.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Now listening'), findsNothing);
    expect(remote.active, isTrue);
  });

  testWidgets('dock play button toggles without opening the player', (
    tester,
  ) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote);
    await _mount(tester, remote);
    final play = find.byKey(const Key('book-narration-play-pause'));
    final size = tester.getSize(play);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tap(play);
    await tester.pump();
    expect(session.toggles, 1);
    expect(find.text('Now listening'), findsNothing);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
  });

  testWidgets('the dock hairline shows progress', (tester) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote, progress: .4);
    await _mount(tester, remote);
    final dock = tester.getRect(find.byKey(BookNarrationDock.dockKey));
    final hairline = tester.getRect(
      find.byKey(BookNarrationDock.hairlineKey),
    );
    expect(hairline.height, 2);
    expect(hairline.bottom, dock.bottom);
    expect(hairline.width, closeTo(dock.width * .4, .5));
    remote.update(ownerToken: session.owner, progress: .8);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(BookNarrationDock.hairlineKey)).width,
      closeTo(dock.width * .8, .5),
    );
  });

  testWidgets('±15 s clamps at the ends', (tester) async {
    final remote = BookNarrationRemoteController();
    // 5 s into a 100 s session: back 15 s stops at the start.
    final session = _Session(remote, progress: .05);
    await _mount(tester, remote);
    await _openPlayer(tester);
    await tester.tap(find.bySemanticsLabel('Back 15 seconds'));
    await tester.pumpAndSettle();
    expect(session.seeks.last, 0);

    // 30 s in: forward 15 s lands on 45 s.
    remote.update(ownerToken: session.owner, progress: .3);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Forward 15 seconds'));
    await tester.pumpAndSettle();
    expect(session.seeks.last, closeTo(.45, 1e-9));

    // 95 s in: forward 15 s stops at the end.
    remote.update(ownerToken: session.owner, progress: .95);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Forward 15 seconds'));
    await tester.pumpAndSettle();
    expect(session.seeks.last, 1);
    expect(find.text('1:40'), findsOneWidget);
    expect(find.text('−0:00'), findsOneWidget);
  });

  testWidgets('tapping the seek bar seeks to that point', (tester) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote);
    await _mount(tester, remote);
    await _openPlayer(tester);
    final bar = tester.getRect(find.byKey(BookNarrationFullPlayer.seekKey));
    expect(bar.height, greaterThanOrEqualTo(44));
    await tester.tapAt(Offset(bar.left + bar.width * .6, bar.center.dy));
    await tester.pumpAndSettle();
    expect(session.seeks.last, closeTo(.6, .01));
  });

  testWidgets('Stop closes the player and stops narration', (tester) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote);
    await _mount(tester, remote);
    await _openPlayer(tester);
    await tester.ensureVisible(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(session.stops, 1);
    expect(remote.active, isFalse);
    expect(find.text('Now listening'), findsNothing);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
  });

  testWidgets('Chapters closes the player and opens the contents', (
    tester,
  ) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote);
    await _mount(tester, remote);
    await _openPlayer(tester);
    await tester.ensureVisible(find.text('Chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapters'));
    await tester.pumpAndSettle();
    expect(find.text('Now listening'), findsNothing);
    expect(session.chapters, 1);
    expect(remote.active, isTrue);
  });

  testWidgets('an unknown author drops the name from the voice line', (
    tester,
  ) async {
    final remote = BookNarrationRemoteController();
    _Session(remote, author: '  ');
    await _mount(tester, remote);
    await _openPlayer(tester);
    expect(find.text('AI-generated voice.'), findsOneWidget);
    expect(find.textContaining('’s voice'), findsNothing);
  });

  testWidgets('playing waves animate, and hold still under reduced motion', (
    tester,
  ) async {
    final remote = BookNarrationRemoteController();
    _Session(remote, playing: true);
    await _mount(tester, remote);
    // Animated while playing: frames keep coming.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await _mount(tester, remote, reduceMotion: true);
    await _openPlayer(tester);
    // Static: the reduced-motion player settles while playing.
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Now listening'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsWidgets);
  });

  testWidgets('Chapters over a real root sheet closes the player, and Back '
      'and Stop still work', (tester) async {
    final remote = BookNarrationRemoteController();
    late BuildContext appContext;
    final session = _Session(
      remote,
      onChapters: () => showV3Sheet<void>(
        appContext,
        title: 'Contents',
        builder: (_) => const Text('Chapter list'),
      ),
    );
    await _mount(tester, remote);
    appContext = tester.element(find.byType(Scaffold));

    await _openPlayer(tester);
    await tester.ensureVisible(find.text('Chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapters'));
    await tester.pumpAndSettle();
    expect(session.chapters, 1);
    expect(find.byType(BookNarrationFullPlayer), findsNothing);
    expect(find.text('Chapter list'), findsOneWidget);
    Navigator.of(appContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(find.text('Chapter list'), findsNothing);

    await _openPlayer(tester);
    expect(find.byType(BookNarrationFullPlayer), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(BookNarrationFullPlayer), findsNothing);

    await _openPlayer(tester);
    await tester.ensureVisible(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(session.stops, 1);
    expect(find.byType(BookNarrationFullPlayer), findsNothing);
    expect(find.byKey(BookNarrationDock.dockKey), findsNothing);
  });

  testWidgets('times follow the speed: remaining at 2× is half', (
    tester,
  ) async {
    final remote = BookNarrationRemoteController();
    _Session(remote, progress: .3, speed: 2);
    await _mount(tester, remote);
    expect(find.text('Ch. 6 · 0:15 / 0:50 · 2×'), findsOneWidget);
    await _openPlayer(tester);
    expect(find.text('0:15'), findsOneWidget);
    expect(find.text('−0:35'), findsOneWidget);
    expect(remote.listeningDuration, const Duration(seconds: 50));
  });

  testWidgets('the seek bar is an adjustable slider for screen readers', (
    tester,
  ) async {
    final remote = BookNarrationRemoteController();
    final session = _Session(remote, progress: .35);
    await _mount(tester, remote);
    await _openPlayer(tester);
    final slider = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Audiobook progress',
      ),
    );
    expect(slider.properties.slider, isTrue);
    expect(slider.properties.value, '35 percent');
    expect(slider.properties.increasedValue, '40 percent');
    expect(slider.properties.decreasedValue, '30 percent');
    slider.properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(session.seeks.last, closeTo(.40, 1e-9));
    final next = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Audiobook progress',
      ),
    );
    next.properties.onDecrease!();
    await tester.pumpAndSettle();
    expect(session.seeks.last, closeTo(.35, 1e-9));
  });

  testWidgets('the dock labels its open-player action', (tester) async {
    final remote = BookNarrationRemoteController();
    _Session(remote);
    await _mount(tester, remote);
    expect(
      find.bySemanticsLabel('Open player, The Essays of Warren Buffett'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
  });
}
