// Native AVPlayer/Flutter smoke. Uses generated WAV and synthetic book data;
// no account, paid synthesis or production learner state is touched.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _passage = 'Alpha beta gamma delta epsilon zeta eta theta iota kappa.';

class _NativeRepository extends Fake implements ContentResourcesRepository {
  _NativeRepository(this.uri);
  final Uri uri;
  int requests = 0;
  bool sparseAlignment = false;
  bool pendingFirstAlignment = false;
  final serviceTimes = <int>[];
  final resource = const ContentResource(
    id: 'native-narration-fixture',
    kind: 'llm_book_summary',
    canonicalKey: 'native-narration-fixture',
    title: 'Playback verification',
    isSaved: false,
    progressPercent: 0,
    licenseStatus: 'test_fixture',
    contentMarkdown:
        '## First chapter\n\n$_passage\n\n## Second chapter\n\n$_passage',
  );

  @override
  Future<BookNarrationAudio> prepareNarration(
    String resourceId, {
    required String text,
    required String style,
    String? narratorProfile,
  }) async {
    requests++;
    final clock = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    serviceTimes.add(clock.elapsedMilliseconds);
    final words = RegExp(r'\S+').allMatches(text).toList();
    final pending = pendingFirstAlignment && requests == 1;
    return BookNarrationAudio(
      audioUri: uri,
      style: style,
      voice: 'Synthetic fixture',
      provider: 'test',
      duration: const Duration(seconds: 4),
      sourceTextHash: 'native-synthetic-passage',
      alignmentPending: pending,
      alignmentSource: 'transcription',
      alignment: pending
          ? const []
          : sparseAlignment
          ? [
              BookNarrationCue(
                start: words.first.start,
                end: words.first.end,
                startTime: const Duration(milliseconds: 200),
                endTime: const Duration(milliseconds: 600),
              ),
              BookNarrationCue(
                start: words.last.start,
                end: words.last.end,
                startTime: const Duration(milliseconds: 2000),
                endTime: const Duration(milliseconds: 2600),
              ),
            ]
          : [
              for (var i = 0; i < words.length; i++)
                BookNarrationCue(
                  start: words[i].start,
                  end: words[i].end,
                  startTime: Duration(milliseconds: i * 4000 ~/ words.length),
                  endTime: Duration(
                    milliseconds: (i + 1) * 4000 ~/ words.length,
                  ),
                ),
            ],
      alignmentGranularity: BookNarrationAlignmentGranularity.word,
      isAiGenerated: false,
    );
  }

  @override
  Future<ContentResource> getResource(String resourceId) async => resource;
  @override
  Future<List<ContentHighlight>> listHighlights(String resourceId) async => [];
  @override
  Future<ContentResource> updateProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async => resource;
}

class _MeasuredPlayer extends AudioPlayer {
  final sourceTimes = <int>[];
  final seekTimes = <int>[];
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    final clock = Stopwatch()..start();
    final duration = await super.setAudioSources(
      sources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
    sourceTimes.add(clock.elapsedMilliseconds);
    return duration;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    final clock = Stopwatch()..start();
    await super.seek(position, index: index);
    seekTimes.add(clock.elapsedMilliseconds);
  }
}

Future<Uri> _makeWav() async {
  const rate = 24000, samples = rate * 4;
  final data = ByteData(44 + samples * 2);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    // Quiet, deterministic pulses; cue timestamps are fixture truth.
    final sample = i % 9600 < 1200
        ? (sin(i * 440 * 2 * pi / rate) * 700).round()
        : 0;
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  final file = File('${Directory.systemTemp.path}/cmpys-narration-fixture.wav');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file.uri;
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  int milliseconds = 10000,
}) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsedMilliseconds < milliseconds) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Native operation exceeded ${milliseconds}ms',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native playback continues when delayed alignment becomes available',
    (tester) async {
      final repo = _NativeRepository(await _makeWav())
        ..pendingFirstAlignment = true;
      final player = _MeasuredPlayer();
      final narrator = ExpressiveBookNarrator(
        repository: repo,
        resourceId: repo.resource.id,
        audioPlayer: player,
      );
      addTearDown(narrator.dispose);
      var alignedWhilePlaying = false;
      narrator.setTrackHandler((event) {
        if (event.phase == BookNarrationPlaybackPhase.playing &&
            event.audio?.alignmentPending == false &&
            event.highlightStart != null) {
          alignedWhilePlaying = true;
        }
      });
      await narrator.initialize(speed: 1);
      await narrator.loadTrack(
        sessionId: 1,
        chapters: [BookNarrationDocument.fromMarkdown(_passage)],
        initialChapterIndex: 0,
        initialSegmentIndex: 0,
      );
      expect(repo.requests, 1);
      await narrator.playTrack();
      await _until(tester, () => player.position.inMilliseconds > 250);
      final beforeAlignment = player.position;
      final sourceLoads = player.sourceTimes.length;
      final seeks = player.seekTimes.length;
      await _until(tester, () => alignedWhilePlaying);
      expect(player.position, greaterThan(beforeAlignment));
      expect(player.playing, isTrue);
      expect(player.sourceTimes.length, sourceLoads);
      expect(player.seekTimes.length, seeks);
      expect(repo.requests, 2);
      debugPrint('NARRATION_DELAYED_ALIGNMENT_PASSED without reload or seek');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets(
    'native playback timing, resume, speed and reader controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _NativeRepository(await _makeWav());
      final player = _MeasuredPlayer();
      final narrator = ExpressiveBookNarrator(
        repository: repo,
        resourceId: repo.resource.id,
        audioPlayer: player,
      );
      await narrator.initialize(speed: 1);
      final metrics = <String, Object>{};
      final document = BookNarrationDocument.fromMarkdown(_passage);
      for (final speed in [1.0, 1.5, 2.0]) {
        final clock = Stopwatch()..start();
        int? playingAt;
        final lag = <double>[];
        final seen = <int>{};
        narrator.setTrackHandler((event) {
          if (event.phase != BookNarrationPlaybackPhase.playing) return;
          playingAt ??= clock.elapsedMilliseconds;
          final start = event.highlightStart;
          if (start == null || !seen.add(start)) return;
          final cue = event.audio!.alignment.firstWhere(
            (cue) => cue.start == start,
          );
          lag.add(
            (player.position - cue.startTime).inMicroseconds / 1000 / speed,
          );
        });
        await narrator.setSpeed(speed);
        await narrator.loadTrack(
          sessionId: (speed * 10).round(),
          chapters: [document],
          initialChapterIndex: 0,
          initialSegmentIndex: 0,
        );
        final preparedAt = clock.elapsedMilliseconds;
        await narrator.playTrack();
        await _until(
          tester,
          () => player.processingState == ProcessingState.completed,
        );
        lag.sort();
        expect(lag.length, greaterThanOrEqualTo(9));
        expect(lag.last, lessThan(250));
        metrics['speed_$speed'] = {
          'prepared_ms': preparedAt,
          'first_playing_ms': playingAt,
          'observed_words': lag.length,
          'highlight_lag_p95_ms': lag[(lag.length * .95).ceil() - 1],
          'highlight_lag_max_ms': lag.last,
        };
      }
      final seekCount = player.seekTimes.length;
      final resumeClock = Stopwatch()..start();
      await narrator.loadTrack(
        sessionId: 40,
        chapters: [document],
        initialChapterIndex: 0,
        initialSegmentIndex: 0,
        initialCharacterOffset: 18,
      );
      metrics['restore_ms'] = resumeClock.elapsedMilliseconds;
      metrics['restore_extra_seeks'] = player.seekTimes.length - seekCount;
      expect(player.position.inMilliseconds, closeTo(1200, 120));
      metrics['service_fixture_ms'] = repo.serviceTimes;
      metrics['native_source_load_ms'] = player.sourceTimes;
      metrics['native_seek_ms'] = player.seekTimes;
      debugPrint('NARRATION_NATIVE_METRICS ${jsonEncode(metrics)}');
      await narrator.loadTrack(
        sessionId: 50,
        chapters: [
          BookNarrationDocument.fromMarkdown(
            '$_passage\n\n$_passage\n\n$_passage',
          ),
        ],
        initialChapterIndex: 0,
        initialSegmentIndex: 0,
      );
      await narrator.playTrack();
      await _until(tester, () => player.sequence.length == 3);
      await narrator.seekToSentence(chapterIndex: 0, segmentIndex: 2);
      expect(player.currentIndex, 2);
      await narrator.pauseTrack();
      await narrator.seekToSentence(chapterIndex: 0, segmentIndex: 1);
      expect(player.currentIndex, 1);
      expect(player.playing, isFalse);
      await Future.wait([
        narrator.seekToSentence(chapterIndex: 0, segmentIndex: 2),
        narrator.seekToSentence(chapterIndex: 0, segmentIndex: 0),
      ]);
      expect(player.currentIndex, 0);
      expect(player.playing, isFalse);
      await narrator.dispose();

      repo.sparseAlignment = true;
      final uiPlayer = AudioPlayer();
      final uiNarrator = ExpressiveBookNarrator(
        repository: repo,
        resourceId: repo.resource.id,
        audioPlayer: uiPlayer,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentResourcesRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: BookReaderScreen(
              resourceId: repo.resource.id,
              fallbackTitle: repo.resource.title,
              narrator: uiNarrator,
            ),
          ),
        ),
      );
      await _until(
        tester,
        () => find.byKey(const Key('book-listen-button')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('book-listen-button')));
      await _until(
        tester,
        () => uiPlayer.playing && uiPlayer.position.inMilliseconds > 250,
      );
      bool highlighted(InlineSpan span) =>
          span.style?.backgroundColor == AppColors.green ||
          span.style?.backgroundColor == AppColors.greenSoft ||
          (span is TextSpan && (span.children?.any(highlighted) ?? false));
      final highlights = find.byWidgetPredicate(
        (widget) => widget is RichText && highlighted(widget.text),
      );
      await _until(tester, () => uiPlayer.position.inMilliseconds > 900);
      expect(
        highlights,
        findsNothing,
        reason: 'No word or sentence highlight inside a transcription gap',
      );
      await _until(tester, () => uiPlayer.position.inMilliseconds > 2200);
      expect(
        highlights,
        findsWidgets,
        reason: 'Highlight returns only for the next measured cue',
      );
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await _until(tester, () => !uiPlayer.playing);
      // `playing` changes optimistically; AVPlayer acknowledges pause and its
      // final position through a later platform event.
      await tester.pump(const Duration(milliseconds: 200));
      final paused = uiPlayer.position;
      expect(
        highlights,
        findsNothing,
        reason: 'Paused text is not presented as current speech',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect((uiPlayer.position - paused).inMilliseconds.abs(), lessThan(30));
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await _until(
        tester,
        () => uiPlayer.playing && uiPlayer.position > paused,
      );
      await _until(tester, () => uiPlayer.currentIndex == 1);
      await tester.tap(find.byKey(const Key('book-narration-play-pause')));
      await _until(tester, () => !uiPlayer.playing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Second chapter'), findsWidgets);
      if (const bool.fromEnvironment('CAPTURE_READER')) {
        debugPrint('NARRATION_UI_READY_FOR_INSPECTION');
        await tester.pump(const Duration(seconds: 20));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
