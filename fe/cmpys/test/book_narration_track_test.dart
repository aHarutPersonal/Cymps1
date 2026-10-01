import 'dart:async';

import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'support/fake_book_audio_player.dart';

BookNarrationAudio _audio(String text) => BookNarrationAudio(
  audioUri: Uri.parse('https://audio.example.test/${text.hashCode}.wav'),
  style: 'expressive',
  voice: 'Expressive narrator',
  provider: 'gemini',
  duration: const Duration(seconds: 20),
  alignment: const [],
  isAiGenerated: true,
);

class _AudioRepository extends Fake implements ContentResourcesRepository {
  final lateChunk = Completer<BookNarrationAudio>();
  int requests = 0;
  final texts = <String>[];
  bool holdSecond = false;
  BookNarrationAudio? preparedAudio;
  @override
  Future<BookNarrationAudio> prepareNarration(
    String resourceId, {
    required String text,
    required String style,
    String? narratorProfile,
  }) async {
    requests++;
    texts.add(text);
    if (holdSecond && text.startsWith('Second')) return lateChunk.future;
    return preparedAudio ?? _audio(text);
  }
}

void main() {
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> load(ExpressiveBookNarrator narrator, {int session = 1}) =>
      narrator.loadTrack(
        sessionId: session,
        chapters: [
          BookNarrationDocument.fromMarkdown(
            'First passage.\n\nSecond passage.',
          ),
        ],
        initialChapterIndex: 0,
        initialSegmentIndex: 0,
      );

  test(
    'WAV track prepares one clip, then a rolling two-clip lookahead',
    () async {
      final player = FakeBookAudioPlayer();
      final repo = _AudioRepository();
      final narrator = ExpressiveBookNarrator(
        repository: repo,
        resourceId: 'book',
        audioPlayer: player,
      );
      addTearDown(narrator.dispose);
      final chapters = [
        BookNarrationDocument.fromMarkdown(
          List.generate(8, (index) => 'Passage $index is useful.').join('\n\n'),
        ),
      ];
      await narrator.loadTrack(
        sessionId: 1,
        chapters: chapters,
        initialChapterIndex: 0,
        initialSegmentIndex: 0,
      );
      await flush();
      expect(repo.requests, 1);
      expect(
        (player.sources.single as UriAudioSource).uri.path,
        endsWith('.wav'),
      );

      await narrator.playTrack();
      await flush();
      expect(repo.requests, 3);
      expect(player.sources, hasLength(3));
      await narrator.pauseTrack();
      await player.seek(Duration.zero, index: 1);
      await flush();
      expect(repo.requests, 3);

      await narrator.playTrack();
      await flush();
      expect(repo.requests, 4);
      await player.seek(Duration.zero, index: 2);
      await flush();
      expect(repo.requests, 5);
      await narrator.pauseTrack();

      // The reader reloads an unprepared target instead of filling every gap.
      await expectLater(
        narrator.seekToSentence(chapterIndex: 0, segmentIndex: 7),
        throwsRangeError,
      );
      await narrator.loadTrack(
        sessionId: 2,
        chapters: chapters,
        initialChapterIndex: 0,
        initialSegmentIndex: 7,
      );
      await flush();
      expect(repo.requests, 6);
      expect(repo.texts.last, 'Passage 7 is useful.');
      expect(repo.texts, isNot(contains('Passage 5 is useful.')));
      expect(repo.texts, isNot(contains('Passage 6 is useful.')));
      expect(player.playing, isFalse);
    },
  );

  test(
    'pausing an in-flight window starts no more synthesis; resume fills it',
    () async {
      final player = FakeBookAudioPlayer();
      final repo = _AudioRepository()..holdSecond = true;
      final narrator = ExpressiveBookNarrator(
        repository: repo,
        resourceId: 'book',
        audioPlayer: player,
      );
      addTearDown(narrator.dispose);
      await narrator.loadTrack(
        sessionId: 1,
        chapters: [
          BookNarrationDocument.fromMarkdown(
            'First passage.\n\nSecond passage.\n\nThird passage.\n\nFourth passage.',
          ),
        ],
        initialChapterIndex: 0,
        initialSegmentIndex: 0,
      );
      await narrator.playTrack();
      expect(repo.requests, 3);
      await narrator.pauseTrack();
      repo.lateChunk.complete(_audio('Second passage.'));
      await flush();
      expect(repo.requests, 3);
      expect(player.sources, hasLength(2));
      expect(player.playing, isFalse);

      await narrator.playTrack();
      await flush();
      expect(player.sources, hasLength(3));
      expect(repo.requests, 3);
      await player.seek(Duration.zero, index: 1);
      await flush();
      expect(repo.requests, 4);
      expect(player.sources, hasLength(4));
    },
  );

  test('a superseded load cannot prepare an obsolete passage', () async {
    final player = FakeBookAudioPlayer();
    final repo = _AudioRepository();
    final narrator = ExpressiveBookNarrator(
      repository: repo,
      resourceId: 'book',
      audioPlayer: player,
    );
    addTearDown(narrator.dispose);
    final first = load(narrator);
    final latest = narrator.loadTrack(
      sessionId: 2,
      chapters: [BookNarrationDocument.fromMarkdown('Latest passage.')],
      initialChapterIndex: 0,
      initialSegmentIndex: 0,
    );
    await Future.wait([first, latest]);
    expect(repo.texts, ['Latest passage.']);
    expect(player.loads, 1);
  });

  for (final operation in ['provider', 'add', 'seek']) {
    test(
      'pause during native $operation cannot restart an exhausted queue',
      () async {
        final player = FakeBookAudioPlayer();
        final repo = _AudioRepository()..holdSecond = true;
        final narrator = ExpressiveBookNarrator(
          repository: repo,
          resourceId: 'book',
          audioPlayer: player,
        );
        addTearDown(narrator.dispose);
        await load(narrator);
        await narrator.playTrack();
        player.emitState(ProcessingState.completed);
        if (operation == 'provider') {
          await narrator.pauseTrack();
          repo.lateChunk.complete(_audio('Second passage.'));
          await flush();
        } else {
          final gate = Completer<void>();
          if (operation == 'add') {
            player.nextAddGate = gate;
          } else {
            player.nextSeekGate = gate;
          }
          repo.lateChunk.complete(_audio('Second passage.'));
          await flush();
          expect(operation == 'add' ? player.adds : player.seeks, 1);
          await narrator.pauseTrack();
          gate.complete();
          await flush();
        }
        expect(player.plays, 1);
        expect(player.playing, isFalse);
        if (operation != 'seek') expect(player.seeks, 0);
        await narrator.playTrack();
        expect(player.plays, 2);
        expect(player.seeks, 1);
        expect(player.playing, isTrue);
      },
    );
  }

  test('a delayed stop cannot clear or stop a newer track', () async {
    final cancellation = Completer<void>();
    final player = FakeBookAudioPlayer()
      ..nextPositionCancellationGate = cancellation;
    final narrator = ExpressiveBookNarrator(
      repository: _AudioRepository(),
      resourceId: 'book',
      audioPlayer: player,
    );
    addTearDown(narrator.dispose);
    await load(narrator);
    await narrator.playTrack();
    final stop = narrator.stop();
    await flush();
    await load(narrator, session: 2);
    await narrator.playTrack();
    cancellation.complete();
    await stop;
    expect(player.playing, isTrue);
    expect(player.errors.hasListener, isTrue);
    await narrator.seekToSentence(chapterIndex: 0, segmentIndex: 0);
    expect(player.playing, isTrue);
  });

  for (final timed in [false, true]) {
    test(
      'pause maps ${timed ? 'timed' : 'estimated'} position after a duplicate clip index',
      () async {
        final player = FakeBookAudioPlayer()..repeatedIndexOnPause = 0;
        final repository = _AudioRepository();
        final narrator = ExpressiveBookNarrator(
          repository: repository,
          resourceId: 'book',
          audioPlayer: player,
        );
        addTearDown(narrator.dispose);
        final document = BookNarrationDocument.fromMarkdown(
          'The first sentence introduces this guide. '
          'The second sentence explains the useful decision clearly.',
        );
        expect(document.chunks, hasLength(1));
        if (timed) {
          final start = document.chunks.single.segments.last.start + 4;
          repository.preparedAudio = BookNarrationAudio(
            audioUri: Uri.parse('https://audio.example.test/timed.wav'),
            style: 'expressive',
            voice: 'Expressive narrator',
            duration: const Duration(seconds: 20),
            alignment: [
              BookNarrationCue(
                start: start,
                end: start + 6,
                startTime: const Duration(seconds: 10),
                endTime: const Duration(seconds: 20),
              ),
            ],
            alignmentGranularity: BookNarrationAlignmentGranularity.word,
            isAiGenerated: true,
          );
        }
        final events = <BookNarrationTrackEvent>[];
        narrator.setTrackHandler(events.add);
        await narrator.loadTrack(
          sessionId: 1,
          chapters: [document],
          initialChapterIndex: 0,
          initialSegmentIndex: 0,
        );
        await narrator.playTrack();
        // The native clock can advance between periodic position notifications.
        player.position = const Duration(seconds: 15);
        await narrator.pauseTrack();
        final paused = events.last;
        expect(paused.phase, BookNarrationPlaybackPhase.paused);
        expect(paused.segmentIndex, 1);
        expect(paused.highlightStart, greaterThan(0));
        player.indexes.add(0);
        expect(events.last.segmentIndex, paused.segmentIndex);
        expect(events.last.highlightStart, paused.highlightStart);
        await narrator.playTrack();
        expect(events.last.phase, BookNarrationPlaybackPhase.playing);
        expect(events.last.segmentIndex, paused.segmentIndex);
        expect(events.last.highlightStart, paused.highlightStart);
        expect(player.seeks, 0);
      },
    );
  }

  test(
    'native errors retire buffering and pending appends; manual reload works',
    () async {
      final player = FakeBookAudioPlayer();
      final repo = _AudioRepository()..holdSecond = true;
      final narrator = ExpressiveBookNarrator(
        repository: repo,
        resourceId: 'book',
        audioPlayer: player,
      );
      addTearDown(narrator.dispose);
      final events = <BookNarrationTrackEvent>[];
      final failures = <Object>[];
      narrator.setTrackHandler(events.add);
      narrator.setErrorHandler(failures.add);
      await load(narrator);
      await narrator.playTrack();
      player.emitState(ProcessingState.buffering);
      expect(events.last.phase, BookNarrationPlaybackPhase.buffering);
      final failure = PlayerException(-11800, 'Native stream failed', 0);
      player.errors.add(failure);
      expect(failures, [failure]);
      expect(player.playing, isFalse);
      final eventCount = events.length;

      // Late events and queued synthesis cannot restart a retired track.
      player.emitState(ProcessingState.buffering);
      player.errors.add(failure);
      repo.lateChunk.complete(_audio('Second passage.'));
      await flush();
      expect(events.length, eventCount);
      expect(failures, hasLength(1));
      expect(player.sources, hasLength(1));

      await load(narrator, session: 2);
      await narrator.playTrack();
      await flush();
      expect(events.last.sessionId, 2);
      expect(events.last.phase, BookNarrationPlaybackPhase.playing);
      expect(player.sources, hasLength(2));
      expect(repo.requests, 2); // Retry reuses prepared clips.
      await narrator.stop();
      expect(player.errors.hasListener, isFalse);
      player.errors.add(failure);
      expect(failures, hasLength(1));
    },
  );

  test(
    'an asynchronous play rejection is surfaced once and can be retried',
    () async {
      final player = FakeBookAudioPlayer();
      final narrator = ExpressiveBookNarrator(
        repository: _AudioRepository(),
        resourceId: 'book',
        audioPlayer: player,
      );
      addTearDown(narrator.dispose);
      final failures = <Object>[];
      narrator.setErrorHandler(failures.add);
      await load(narrator);
      final failure = PlayerException(-1, 'Player unavailable', 0);
      player.playError = failure;
      await narrator.playTrack();
      await flush();
      player.errors.add(failure);
      expect(failures, [failure]);
      await expectLater(narrator.playTrack(), throwsA(same(failure)));
      player.playError = null;
      await load(narrator, session: 2);
      await narrator.playTrack();
      expect(player.playing, isTrue);
    },
  );

  test('disposal removes the native error listener', () async {
    final player = FakeBookAudioPlayer();
    final narrator = ExpressiveBookNarrator(
      repository: _AudioRepository(),
      resourceId: 'book',
      audioPlayer: player,
    );
    await load(narrator);
    expect(player.errors.hasListener, isTrue);
    await narrator.dispose();
    expect(player.errors.hasListener, isFalse);
    expect(player.errors.isClosed, isTrue);
  });
}
