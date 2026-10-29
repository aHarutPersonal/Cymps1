import 'package:cmpys/app/assets.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/presentation/book_narration_dock.dart';
import 'package:cmpys/features/plan/state/book_narration_remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_player_platform.dart';

// SPEC §10: the full listening player plays the `listen` loop only while it
// is open and the narration plays; the mini dock never gets a video.

final Object _owner = Object();

void _attach(BookNarrationRemoteController remote, {bool playing = false}) {
  remote.attach(
    ownerToken: _owner,
    onToggle: () async =>
        remote.update(ownerToken: _owner, playing: !remote.playing),
    onPrevious: () async {},
    onNext: () async {},
    onSeek: (_) async {},
    onStyleChanged: (_) async {},
    onSpeedChanged: (_) async {},
    onStop: () async {},
    onChapters: () async {},
    playing: playing,
    progress: .25,
    speed: 1,
    resourceId: 'essays',
    title: 'The Essays of Warren Buffett',
    author: 'Warren Buffett',
    chapterIndex: 5,
    chapterTitle: 'Owner earnings',
    duration: const Duration(seconds: 100),
  );
}

Future<void> _mount(
  WidgetTester tester,
  BookNarrationRemoteController remote, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

/// Lets player events, futures and the 100 ms position poll run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 110));
  }
}

Future<void> _openPlayer(WidgetTester tester) async {
  final dock = tester.getRect(find.byKey(BookNarrationDock.dockKey));
  await tester.tapAt(Offset(dock.left + 30, dock.center.dy));
  // The .6 s slide up.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await _settle(tester);
}

Future<void> _togglePlay(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('book-narration-full-play-pause')));
  await _settle(tester);
}

double _scaleOf(WidgetTester tester) => tester
    .widget<AnimatedScale>(
      find
          .ancestor(
            of: find.byType(V3Cover),
            matching: find.byType(AnimatedScale),
          )
          .first,
    )
    .scale;

void main() {
  late FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = FakeVideoPlayerPlatform.install(
      autoInitialize: true,
      autoFrames: true,
    );
  });
  tearDown(() => V3VideoCoordinator.instance.debugReset());

  testWidgets('the video plays only while the narration plays, and stops '
      'when the player closes', (tester) async {
    final remote = BookNarrationRemoteController();
    _attach(remote);
    await _mount(tester, remote);
    // The mini dock has no video.
    expect(fake.created, isEmpty);

    await _openPlayer(tester);
    final ids = fake.idsFor(AppAssets.videoListening);
    expect(ids, hasLength(1));
    final id = ids.single;
    // Open but paused: loaded, not playing, today's design shows.
    expect(fake.isPlaying(id), isFalse);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(BookNarrationFullPlayer.videoOverlayKey),
          )
          .opacity,
      0,
    );

    await _togglePlay(tester);
    expect(remote.playing, isTrue);
    expect(fake.isPlaying(id), isTrue);
    // Shown at .75 with its gradient once a frame has played.
    expect(tester.widget<V3LoopVideo>(find.byType(V3LoopVideo)).opacity, .75);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(BookNarrationFullPlayer.videoOverlayKey),
          )
          .opacity,
      1,
    );
    expect(_scaleOf(tester), 1);

    await _togglePlay(tester);
    expect(remote.playing, isFalse);
    expect(fake.isPlaying(id), isFalse);
    final paused = tester.widget<V3LoopVideo>(find.byType(V3LoopVideo));
    expect(paused.opacity, .4);
    expect(paused.saturation, .5);
    expect(paused.scale, 1.06);
    expect(_scaleOf(tester), .92);

    // Playing again, then closing the player: the video stops and goes.
    await _togglePlay(tester);
    expect(fake.isPlaying(id), isTrue);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    // Mid-slide: no longer the current route, so it pauses at once.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(V3LoopVideo), findsOneWidget);
    expect(fake.isPlaying(id), isFalse);
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(find.byType(V3LoopVideo), findsNothing);
    expect(fake.disposed, contains(id));
    // The narration itself keeps playing under the dock.
    expect(remote.playing, isTrue);
    expect(
      find.text('AI-generated voice. Not Warren Buffett’s voice.'),
      findsNothing,
    );
  });

  testWidgets('keeps the AI-voice disclosure over the video', (tester) async {
    final remote = BookNarrationRemoteController();
    _attach(remote, playing: true);
    await _mount(tester, remote);
    await _openPlayer(tester);
    expect(
      find.text('AI-generated voice. Not Warren Buffett’s voice.'),
      findsOneWidget,
    );
  });

  testWidgets('reduced motion: no video and a static cover', (tester) async {
    final remote = BookNarrationRemoteController();
    _attach(remote);
    await _mount(tester, remote, reduceMotion: true);
    await _openPlayer(tester);
    expect(find.byType(V3LoopVideo), findsNothing);
    expect(fake.created, isEmpty);
    expect(_scaleOf(tester), 1);
    await _togglePlay(tester);
    expect(fake.created, isEmpty);
    expect(_scaleOf(tester), 1);
  });
}
