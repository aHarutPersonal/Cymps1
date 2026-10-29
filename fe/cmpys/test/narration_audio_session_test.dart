import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_book_audio_player.dart';

// The app's muted background videos ask video_player for `mixWithOthers`,
// which on iOS changes the shared audio session to mix with other apps.
// Narration must re-apply its own session every time it starts playing, so
// it keeps interrupting other apps' audio as it did before the videos.

class _Repository extends Fake implements ContentResourcesRepository {
  @override
  Future<BookNarrationAudio> prepareNarration(
    String resourceId, {
    required String text,
    required String style,
    String? narratorProfile,
  }) async => BookNarrationAudio(
    audioUri: Uri.parse('https://audio.example.test/${text.hashCode}.wav'),
    style: 'expressive',
    voice: 'Expressive narrator',
    provider: 'gemini',
    duration: const Duration(seconds: 20),
    alignment: const [],
    isAiGenerated: true,
  );
}

void main() {
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  late FakeBookAudioPlayer player;
  late List<String> log;
  late ExpressiveBookNarrator narrator;

  setUp(() {
    player = FakeBookAudioPlayer();
    log = [];
    narrator = ExpressiveBookNarrator(
      repository: _Repository(),
      resourceId: 'book',
      audioPlayer: player,
      configureAudioSession: () async => log.add('session@${player.plays}'),
    );
  });

  tearDown(() => narrator.dispose());

  test('track playback re-applies the narration session before each '
      'play', () async {
    await narrator.initialize(speed: 1);
    expect(log, ['session@0']);
    await narrator.loadTrack(
      sessionId: 1,
      chapters: [
        BookNarrationDocument.fromMarkdown('First passage.\n\nSecond.'),
      ],
      initialChapterIndex: 0,
      initialSegmentIndex: 0,
    );

    await narrator.playTrack();
    await flush();
    expect(player.plays, 1);
    // Applied again, before the player started.
    expect(log, ['session@0', 'session@0']);

    await narrator.pauseTrack();
    await narrator.playTrack();
    await flush();
    expect(player.plays, 2);
    expect(log, ['session@0', 'session@0', 'session@1']);
  });

  test('sentence playback re-applies the session before playing', () async {
    await narrator.initialize(speed: 1);
    await narrator.speak('First passage.');
    expect(player.plays, 1);
    expect(log, ['session@0', 'session@0']);
  });

  test('a failing session call never blocks playback', () async {
    var calls = 0;
    final own = FakeBookAudioPlayer();
    final failing = ExpressiveBookNarrator(
      repository: _Repository(),
      resourceId: 'book',
      audioPlayer: own,
      configureAudioSession: () async {
        if (calls++ > 0) throw StateError('session busy');
      },
    );
    addTearDown(failing.dispose);
    await failing.initialize(speed: 1);
    await failing.speak('First passage.');
    expect(own.plays, 1);
    expect(calls, 2);
  });
}
