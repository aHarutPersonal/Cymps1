import 'dart:async';
import 'dart:collection';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:markdown/markdown.dart' as md;

import '../../session/data/content_resources_repository.dart';

typedef BookNarrationProgressHandler =
    void Function(int start, int end, String word);
typedef BookNarrationErrorHandler = void Function(Object error);
typedef BookNarrationVoiceHandler = void Function(BookNarrationVoiceKind voice);
typedef BookNarrationTrackHandler =
    void Function(BookNarrationTrackEvent event);

enum BookNarrationStyle {
  expressive(
    apiName: 'expressive',
    label: 'Expressive',
    description: 'Dynamic pacing and emotion that follow the meaning.',
  ),
  warm(
    apiName: 'warm',
    label: 'Warm',
    description: 'Intimate, encouraging, and softly expressive.',
  ),
  grounded(
    apiName: 'grounded',
    label: 'Grounded',
    description: 'Thoughtful, calm, and naturally varied.',
  );

  const BookNarrationStyle({
    required this.apiName,
    required this.label,
    required this.description,
  });

  final String apiName;
  final String label;
  final String description;
}

enum BookNarrationVoiceKind { expressiveAi, device }

enum BookNarrationPlaybackPhase {
  preparing,
  buffering,
  playing,
  paused,
  completed,
}

@immutable
class BookNarrationTrackEvent {
  const BookNarrationTrackEvent({
    required this.sessionId,
    required this.phase,
    required this.chapterIndex,
    required this.segmentIndex,
    this.highlightStart,
    this.highlightEnd,
    this.alignmentGranularity = BookNarrationAlignmentGranularity.none,
    this.audio,
  });

  final int sessionId;
  final BookNarrationPlaybackPhase phase;
  final int chapterIndex;
  final int segmentIndex;

  /// Exact range inside the active visual sentence. This can be a word,
  /// provider phrase, or sentence depending on [alignmentGranularity]. A null
  /// range means the media position is currently in silence or buffering.
  final int? highlightStart;
  final int? highlightEnd;
  final BookNarrationAlignmentGranularity alignmentGranularity;
  final BookNarrationAudio? audio;
}

/// Optional capability used by the reader to prepare upcoming sentences while
/// the current one plays, avoiding mechanical gaps between clips.
abstract interface class BookNarrationPreloader {
  Future<void> prepare(String text);
}

/// Optional controls implemented by the adaptive production narrator. Keeping
/// this separate leaves small test and accessibility narrators simple.
abstract interface class BookNarrationStyleController {
  BookNarrationStyle get style;

  BookNarrationVoiceKind get voiceKind;

  void setVoiceHandler(BookNarrationVoiceHandler? handler);

  Future<void> setStyle(BookNarrationStyle style);
}

/// Gap-minimizing playback used by the production AI narrator. Sentences remain
/// navigation/highlight units, while longer chunks are synthesized and queued
/// as one continuous audio track.
abstract interface class BookNarrationTrackController {
  void setTrackHandler(BookNarrationTrackHandler? handler);

  Future<void> loadTrack({
    required int sessionId,
    required List<BookNarrationDocument> chapters,
    required int initialChapterIndex,
    required int initialSegmentIndex,
  });

  Future<void> playTrack();

  Future<void> pauseTrack();

  Future<void> seekToSentence({
    required int chapterIndex,
    required int segmentIndex,
  });
}

/// Small boundary around the platform speech engine so the reader can be
/// exercised without a native plugin in widget tests.
abstract interface class BookNarrator {
  void setProgressHandler(BookNarrationProgressHandler? handler);

  void setErrorHandler(BookNarrationErrorHandler? handler);

  Future<void> initialize({required double speed});

  Future<void> setSpeed(double speed);

  /// Completes when [text] has finished speaking.
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

/// Human-style narration backed by cached speech audio and precise word cues.
final class ExpressiveBookNarrator
    implements
        BookNarrator,
        BookNarrationPreloader,
        BookNarrationTrackController {
  ExpressiveBookNarrator({
    required ContentResourcesRepository repository,
    required String resourceId,
    this.narratorProfile = 'expressive_narrator',
  }) : _repository = repository,
       _resourceId = resourceId;

  final ContentResourcesRepository _repository;
  final String _resourceId;
  final String narratorProfile;
  final LinkedHashMap<String, Future<BookNarrationAudio>> _prepared =
      LinkedHashMap();
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<int?>? _trackIndexSubscription;
  StreamSubscription<PlayerState>? _trackStateSubscription;
  BookNarrationProgressHandler? _progressHandler;
  BookNarrationErrorHandler? _errorHandler;
  BookNarrationTrackHandler? _trackHandler;
  BookNarrationStyle _style = BookNarrationStyle.expressive;
  double _speed = 1;
  int _playRun = 0;
  int _lastCueStart = -1;
  int _trackRun = 0;
  int _trackSessionId = 0;
  int _trackQueueIndex = 0;
  int _trackSegmentIndex = 0;
  bool _trackWantsPlayback = false;
  String _lastTrackEventKey = '';
  List<_NarrationTrackEntry> _trackEntries = const [];
  final List<BookNarrationAudio> _trackAssets = [];
  final List<Completer<void>> _queuedChunks = [];

  BookNarrationStyle get style => _style;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    _progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    _errorHandler = handler;
  }

  @override
  void setTrackHandler(BookNarrationTrackHandler? handler) {
    _trackHandler = handler;
  }

  Future<void> setStyle(BookNarrationStyle style) async {
    if (_style == style) return;
    _style = style;
    await stop();
  }

  @override
  Future<void> initialize({required double speed}) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    _player ??= AudioPlayer();
    await setSpeed(speed);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player?.setSpeed(speed);
  }

  @override
  Future<void> prepare(String text) async {
    await _load(text);
  }

  Future<BookNarrationAudio> _load(String text) {
    final key = '${_style.apiName}\u0000$narratorProfile\u0000$text';
    final existing = _prepared.remove(key);
    if (existing != null) {
      _prepared[key] = existing;
      return existing;
    }
    if (_prepared.length >= 12) {
      _prepared.remove(_prepared.keys.first);
    }

    late final Future<BookNarrationAudio> request;
    request = () async {
      try {
        return await _repository.prepareNarration(
          _resourceId,
          text: text,
          style: _style.apiName,
          narratorProfile: narratorProfile,
        );
      } catch (_) {
        if (identical(_prepared[key], request)) _prepared.remove(key);
        rethrow;
      }
    }();
    _prepared[key] = request;
    return request;
  }

  @override
  Future<void> loadTrack({
    required int sessionId,
    required List<BookNarrationDocument> chapters,
    required int initialChapterIndex,
    required int initialSegmentIndex,
  }) async {
    if (_player == null) await initialize(speed: _speed);
    final run = ++_trackRun;
    _playRun++;
    _trackWantsPlayback = false;
    _releaseQueuedChunks();
    await _positionSubscription?.cancel();
    await _trackIndexSubscription?.cancel();
    await _trackStateSubscription?.cancel();
    _positionSubscription = null;
    _trackIndexSubscription = null;
    _trackStateSubscription = null;
    await _player!.stop();

    _trackSessionId = sessionId;
    _trackQueueIndex = 0;
    _trackSegmentIndex = initialSegmentIndex;
    _lastTrackEventKey = '';
    _trackAssets.clear();
    _trackEntries = _buildTrackEntries(
      chapters: chapters,
      initialChapterIndex: initialChapterIndex,
      initialSegmentIndex: initialSegmentIndex,
    );
    if (_trackEntries.isEmpty) {
      throw StateError('Narration track has no readable chunks');
    }
    _queuedChunks.addAll(
      List<Completer<void>>.generate(
        _trackEntries.length,
        (_) => Completer<void>(),
      ),
    );
    _emitTrackEvent(
      phase: BookNarrationPlaybackPhase.preparing,
      chapterIndex: initialChapterIndex,
      segmentIndex: initialSegmentIndex,
    );

    _warmTrackAhead(0);
    final firstAudio = await _load(_trackEntries.first.chunk.text);
    if (run != _trackRun) return;
    final player = _player!;
    await player.setAudioSources([
      AudioSource.uri(firstAudio.audioUri, tag: _trackEntries.first),
    ]);
    if (run != _trackRun) return;
    _trackAssets.add(firstAudio);
    _queuedChunks.first.complete();
    await player.setSpeed(_speed);

    _trackIndexSubscription = player.currentIndexStream.listen((index) {
      if (run != _trackRun || index == null) return;
      _trackQueueIndex = index.clamp(0, _trackEntries.length - 1).toInt();
      final entry = _trackEntries[_trackQueueIndex];
      _trackSegmentIndex = entry.chunk.segments.first.segmentIndex;
      if (player.playing && player.processingState == ProcessingState.ready) {
        _emitTrackPosition(player.position, run: run);
      } else {
        _emitTrackEvent(
          phase: player.playing
              ? BookNarrationPlaybackPhase.buffering
              : BookNarrationPlaybackPhase.paused,
          chapterIndex: entry.chapterIndex,
          segmentIndex: _trackSegmentIndex,
          audio: _trackAudioAt(_trackQueueIndex),
        );
      }
    });
    _trackStateSubscription = player.playerStateStream.listen((state) {
      if (run != _trackRun) return;
      _handleTrackPlayerState(state, run: run);
    });
    _positionSubscription = player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 45),
          maxPeriod: const Duration(milliseconds: 100),
        )
        .listen((position) {
          if (run != _trackRun ||
              !player.playing ||
              player.processingState != ProcessingState.ready) {
            return;
          }
          _emitTrackPosition(position, run: run);
        });

    final initialPosition = _positionForSegment(
      firstAudio,
      _trackEntries.first.chunk,
      initialSegmentIndex,
    );
    if (initialPosition > Duration.zero) {
      await player.seek(initialPosition, index: 0);
    }
    if (run != _trackRun) return;
    _emitTrackEvent(
      phase: BookNarrationPlaybackPhase.paused,
      chapterIndex: initialChapterIndex,
      segmentIndex: initialSegmentIndex,
      audio: firstAudio,
    );
    unawaited(_appendRemainingTrack(run));
  }

  @override
  Future<void> playTrack() async {
    if (_trackEntries.isEmpty || _player == null) {
      throw StateError('Narration track is not loaded');
    }
    _trackWantsPlayback = true;
    final run = _trackRun;
    unawaited(
      _player!.play().catchError((Object error, StackTrace _) {
        if (run == _trackRun) _errorHandler?.call(error);
      }),
    );
  }

  @override
  Future<void> pauseTrack() async {
    _trackWantsPlayback = false;
    await _player?.pause();
    if (_trackEntries.isEmpty) return;
    final entry = _trackEntries[_trackQueueIndex];
    _emitTrackEvent(
      phase: BookNarrationPlaybackPhase.paused,
      chapterIndex: entry.chapterIndex,
      segmentIndex: _trackSegmentIndex,
      audio: _trackAudioAt(_trackQueueIndex),
    );
  }

  @override
  Future<void> seekToSentence({
    required int chapterIndex,
    required int segmentIndex,
  }) async {
    final targetIndex = _trackEntries.indexWhere(
      (entry) =>
          entry.chapterIndex == chapterIndex &&
          entry.chunk.containsSegment(segmentIndex),
    );
    if (targetIndex < 0) {
      throw RangeError('Sentence is outside the loaded narration track');
    }
    final run = _trackRun;
    if (!_queuedChunks[targetIndex].isCompleted) {
      final entry = _trackEntries[targetIndex];
      await _player?.pause();
      _emitTrackEvent(
        phase: BookNarrationPlaybackPhase.buffering,
        chapterIndex: entry.chapterIndex,
        segmentIndex: segmentIndex,
      );
      await _queuedChunks[targetIndex].future;
    }
    if (run != _trackRun || targetIndex >= _trackAssets.length) return;
    final asset = _trackAssets[targetIndex];
    final entry = _trackEntries[targetIndex];
    _trackQueueIndex = targetIndex;
    _trackSegmentIndex = segmentIndex;
    await _player!.seek(
      _positionForSegment(asset, entry.chunk, segmentIndex),
      index: targetIndex,
    );
    if (run != _trackRun) return;
    if (_trackWantsPlayback) {
      _emitTrackPosition(_player!.position, run: run, force: true);
    } else {
      _emitTrackEvent(
        phase: BookNarrationPlaybackPhase.paused,
        chapterIndex: entry.chapterIndex,
        segmentIndex: segmentIndex,
        audio: asset,
        force: true,
      );
    }
    if (_trackWantsPlayback && !_player!.playing) {
      unawaited(_player!.play());
    }
  }

  void _warmTrackAhead(int index) {
    for (
      var candidate = index;
      candidate < _trackEntries.length && candidate <= index + 2;
      candidate++
    ) {
      unawaited(_load(_trackEntries[candidate].chunk.text));
    }
  }

  Future<void> _appendRemainingTrack(int run) async {
    try {
      for (var index = 1; index < _trackEntries.length; index++) {
        if (run != _trackRun) return;
        _warmTrackAhead(index);
        final audio = await _load(_trackEntries[index].chunk.text);
        if (run != _trackRun) return;
        final player = _player!;
        final resumeFromExhaustedQueue =
            _trackWantsPlayback &&
            player.processingState == ProcessingState.completed;
        await player.addAudioSource(
          AudioSource.uri(audio.audioUri, tag: _trackEntries[index]),
        );
        if (run != _trackRun) return;
        _trackAssets.add(audio);
        if (!_queuedChunks[index].isCompleted) {
          _queuedChunks[index].complete();
        }
        if (resumeFromExhaustedQueue) {
          _trackQueueIndex = index;
          _trackSegmentIndex =
              _trackEntries[index].chunk.segments.first.segmentIndex;
          await player.seek(Duration.zero, index: index);
          if (run != _trackRun) return;
          unawaited(player.play());
        }
      }
    } catch (error) {
      if (run != _trackRun) return;
      final pending = _queuedChunks.where((waiter) => !waiter.isCompleted);
      for (final waiter in pending) {
        waiter.complete();
      }
      _errorHandler?.call(error);
    }
  }

  void _handleTrackPlayerState(PlayerState state, {required int run}) {
    if (_trackEntries.isEmpty || run != _trackRun) return;
    final entry = _trackEntries[_trackQueueIndex];
    switch (state.processingState) {
      case ProcessingState.loading:
      case ProcessingState.buffering:
        _emitTrackEvent(
          phase: BookNarrationPlaybackPhase.buffering,
          chapterIndex: entry.chapterIndex,
          segmentIndex: _trackSegmentIndex,
          audio: _trackAudioAt(_trackQueueIndex),
        );
        return;
      case ProcessingState.completed:
        if (_trackAssets.length < _trackEntries.length) {
          _emitTrackEvent(
            phase: BookNarrationPlaybackPhase.buffering,
            chapterIndex: entry.chapterIndex,
            segmentIndex: _trackSegmentIndex,
            audio: _trackAudioAt(_trackQueueIndex),
          );
        } else {
          _emitTrackEvent(
            phase: BookNarrationPlaybackPhase.completed,
            chapterIndex: entry.chapterIndex,
            segmentIndex: _trackSegmentIndex,
            audio: _trackAudioAt(_trackQueueIndex),
          );
        }
        return;
      case ProcessingState.ready:
        if (state.playing) {
          _emitTrackPosition(_player!.position, run: run, force: true);
        } else {
          _emitTrackEvent(
            phase: BookNarrationPlaybackPhase.paused,
            chapterIndex: entry.chapterIndex,
            segmentIndex: _trackSegmentIndex,
            audio: _trackAudioAt(_trackQueueIndex),
          );
        }
        return;
      case ProcessingState.idle:
        _emitTrackEvent(
          phase: BookNarrationPlaybackPhase.preparing,
          chapterIndex: entry.chapterIndex,
          segmentIndex: _trackSegmentIndex,
          audio: _trackAudioAt(_trackQueueIndex),
        );
        return;
    }
  }

  void _emitTrackPosition(
    Duration position, {
    required int run,
    bool force = false,
  }) {
    if (run != _trackRun ||
        _trackQueueIndex < 0 ||
        _trackQueueIndex >= _trackEntries.length) {
      return;
    }
    final entry = _trackEntries[_trackQueueIndex];
    final audio = _trackAudioAt(_trackQueueIndex);
    if (audio == null) return;
    final cue = activeBookNarrationCueAt(audio.alignment, position);
    if (cue == null) {
      _emitTrackEvent(
        phase: BookNarrationPlaybackPhase.playing,
        chapterIndex: entry.chapterIndex,
        segmentIndex: _trackSegmentIndex,
        audio: audio,
        force: force,
      );
      return;
    }
    final slice = entry.chunk.segmentAtOffset(cue.start);
    if (slice == null) {
      _emitTrackEvent(
        phase: BookNarrationPlaybackPhase.playing,
        chapterIndex: entry.chapterIndex,
        segmentIndex: _trackSegmentIndex,
        audio: audio,
        force: force,
      );
      return;
    }
    _trackSegmentIndex = slice.segmentIndex;
    final highlightStart = (slice.segmentStart + cue.start - slice.start)
        .clamp(slice.segmentStart, slice.segmentEnd)
        .toInt();
    final highlightEnd = (slice.segmentStart + cue.end - slice.start)
        .clamp(highlightStart, slice.segmentEnd)
        .toInt();
    _emitTrackEvent(
      phase: BookNarrationPlaybackPhase.playing,
      chapterIndex: entry.chapterIndex,
      segmentIndex: slice.segmentIndex,
      highlightStart: highlightStart,
      highlightEnd: highlightEnd,
      alignmentGranularity: audio.alignmentGranularity,
      audio: audio,
      force: force,
    );
  }

  void _emitTrackEvent({
    required BookNarrationPlaybackPhase phase,
    required int chapterIndex,
    required int segmentIndex,
    int? highlightStart,
    int? highlightEnd,
    BookNarrationAlignmentGranularity alignmentGranularity =
        BookNarrationAlignmentGranularity.none,
    BookNarrationAudio? audio,
    bool force = false,
  }) {
    final key =
        '$phase/$chapterIndex/$segmentIndex/'
        '$highlightStart/$highlightEnd/${audio?.audioUri}';
    if (!force && key == _lastTrackEventKey) return;
    _lastTrackEventKey = key;
    _trackHandler?.call(
      BookNarrationTrackEvent(
        sessionId: _trackSessionId,
        phase: phase,
        chapterIndex: chapterIndex,
        segmentIndex: segmentIndex,
        highlightStart: highlightStart,
        highlightEnd: highlightEnd,
        alignmentGranularity: alignmentGranularity,
        audio: audio,
      ),
    );
  }

  BookNarrationAudio? _trackAudioAt(int index) =>
      index >= 0 && index < _trackAssets.length ? _trackAssets[index] : null;

  Duration _positionForSegment(
    BookNarrationAudio audio,
    BookNarrationChunk chunk,
    int segmentIndex,
  ) {
    final slice = chunk.segments.firstWhere(
      (candidate) => candidate.segmentIndex == segmentIndex,
      orElse: () => chunk.segments.first,
    );
    for (final cue in audio.alignment) {
      if (cue.end > slice.start && cue.start < slice.end) {
        return cue.startTime;
      }
    }
    final duration = audio.duration;
    if (duration == null || chunk.text.isEmpty) return Duration.zero;
    return Duration(
      microseconds: duration.inMicroseconds * slice.start ~/ chunk.text.length,
    );
  }

  void _releaseQueuedChunks() {
    for (final waiter in _queuedChunks) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _queuedChunks.clear();
  }

  @override
  Future<void> speak(String text) async {
    if (_player == null) await initialize(speed: _speed);
    final run = ++_playRun;
    _lastCueStart = -1;
    try {
      final audio = await _load(text);
      if (run != _playRun) return;
      final player = _player!;
      final loadedDuration = await player.setUrl(audio.audioUri.toString());
      if (run != _playRun) return;
      await player.setSpeed(_speed);
      final duration = loadedDuration ?? audio.duration ?? player.duration;
      await _positionSubscription?.cancel();
      _positionSubscription = player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 45),
            maxPeriod: const Duration(milliseconds: 100),
          )
          .listen((position) {
            if (run != _playRun) return;
            _emitProgress(
              text: text,
              position: position,
              duration: duration,
              alignment: audio.alignment,
            );
          });
      _emitProgress(
        text: text,
        position: Duration.zero,
        duration: duration,
        alignment: audio.alignment,
      );
      await player.play();
    } catch (error) {
      // An adaptive narrator suppresses this handler while it transparently
      // switches to the device voice. Direct consumers still receive it.
      _errorHandler?.call(error);
      rethrow;
    } finally {
      if (run == _playRun) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
      }
    }
  }

  void _emitProgress({
    required String text,
    required Duration position,
    required Duration? duration,
    required List<BookNarrationCue> alignment,
  }) {
    final cue = alignment.isNotEmpty
        ? _alignedCue(alignment, position)
        : _estimatedCue(text, position, duration);
    if (cue == null || cue.start == _lastCueStart) return;
    _lastCueStart = cue.start;
    _progressHandler?.call(
      cue.start,
      cue.end,
      text.substring(cue.start, cue.end),
    );
  }

  _LocalNarrationCue? _alignedCue(
    List<BookNarrationCue> alignment,
    Duration position,
  ) {
    var low = 0;
    var high = alignment.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final cue = alignment[middle];
      if (position < cue.startTime) {
        high = middle - 1;
      } else if (position >= cue.endTime) {
        low = middle + 1;
      } else {
        return _LocalNarrationCue(cue.start, cue.end);
      }
    }
    final nearest = (high < 0 ? 0 : high)
        .clamp(0, alignment.length - 1)
        .toInt();
    final cue = alignment[nearest];
    return _LocalNarrationCue(cue.start, cue.end);
  }

  _LocalNarrationCue? _estimatedCue(
    String text,
    Duration position,
    Duration? duration,
  ) {
    if (duration == null || duration <= Duration.zero) return null;
    final words = RegExp(r'\S+').allMatches(text).toList(growable: false);
    if (words.isEmpty) return null;
    final total = duration.inMicroseconds;
    final current = position.inMicroseconds.clamp(0, total);
    var totalWeight = 0;
    final weights = <int>[];
    for (final word in words) {
      final value = word.group(0)!;
      var weight = value.length.clamp(1, 14);
      if (RegExp(r'[,;:]$').hasMatch(value)) weight += 3;
      if (RegExp(r'[.!?]$').hasMatch(value)) weight += 6;
      weights.add(weight);
      totalWeight += weight;
    }
    var elapsedWeight = 0;
    for (var index = 0; index < words.length; index++) {
      elapsedWeight += weights[index];
      if (current * totalWeight <= total * elapsedWeight) {
        return _LocalNarrationCue(words[index].start, words[index].end);
      }
    }
    return _LocalNarrationCue(words.last.start, words.last.end);
  }

  @override
  Future<void> stop() async {
    _playRun++;
    _trackRun++;
    _trackWantsPlayback = false;
    _releaseQueuedChunks();
    await _positionSubscription?.cancel();
    await _trackIndexSubscription?.cancel();
    await _trackStateSubscription?.cancel();
    _positionSubscription = null;
    _trackIndexSubscription = null;
    _trackStateSubscription = null;
    _trackEntries = const [];
    _trackAssets.clear();
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    _progressHandler = null;
    _errorHandler = null;
    _trackHandler = null;
    await stop();
    await _player?.dispose();
    _player = null;
  }
}

/// Uses expressive narration whenever the network/provider is available and
/// silently preserves listening with the installed device voice otherwise.
final class AdaptiveBookNarrator
    implements
        BookNarrator,
        BookNarrationPreloader,
        BookNarrationStyleController,
        BookNarrationTrackController {
  AdaptiveBookNarrator({
    required ExpressiveBookNarrator expressive,
    required SystemBookNarrator device,
  }) : _expressive = expressive,
       _device = device {
    _expressive.setProgressHandler((start, end, word) {
      if (!_usingDevice) _progressHandler?.call(start, end, word);
    });
    _device.setProgressHandler((start, end, word) {
      if (_usingDevice) _progressHandler?.call(start, end, word);
    });
    _expressive.setTrackHandler((event) {
      if (!_usingDevice) _trackHandler?.call(event);
    });
    // Legacy sentence playback handles errors by switching sources in speak().
    // Track playback cannot silently switch engines without losing its queued
    // media position, so surface those errors to the reader instead.
    _expressive.setErrorHandler((error) {
      if (_trackActive) _errorHandler?.call(error);
    });
    _device.setErrorHandler((error) => _errorHandler?.call(error));
  }

  final ExpressiveBookNarrator _expressive;
  final SystemBookNarrator _device;
  BookNarrationProgressHandler? _progressHandler;
  BookNarrationErrorHandler? _errorHandler;
  BookNarrationVoiceHandler? _voiceHandler;
  BookNarrationTrackHandler? _trackHandler;
  bool _usingDevice = false;
  bool _expressiveReady = false;
  bool _deviceReady = false;
  bool _trackActive = false;
  double _speed = 1;

  @override
  BookNarrationStyle get style => _expressive.style;

  @override
  BookNarrationVoiceKind get voiceKind => _usingDevice
      ? BookNarrationVoiceKind.device
      : BookNarrationVoiceKind.expressiveAi;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    _progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    _errorHandler = handler;
  }

  @override
  void setVoiceHandler(BookNarrationVoiceHandler? handler) {
    _voiceHandler = handler;
  }

  @override
  void setTrackHandler(BookNarrationTrackHandler? handler) {
    _trackHandler = handler;
  }

  @override
  Future<void> initialize({required double speed}) async {
    _speed = speed;
    try {
      await _expressive.initialize(speed: speed);
      _expressiveReady = true;
    } catch (_) {
      await _switchToDevice();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_expressiveReady) await _expressive.setSpeed(speed);
    if (_deviceReady) await _device.setSpeed(speed);
  }

  @override
  Future<void> setStyle(BookNarrationStyle style) async {
    await _expressive.setStyle(style);
    if (_usingDevice) {
      _usingDevice = false;
      _voiceHandler?.call(voiceKind);
    }
  }

  @override
  Future<void> loadTrack({
    required int sessionId,
    required List<BookNarrationDocument> chapters,
    required int initialChapterIndex,
    required int initialSegmentIndex,
  }) async {
    _trackActive = true;
    if (!_expressiveReady) {
      await _expressive.initialize(speed: _speed);
      _expressiveReady = true;
    }
    if (_usingDevice) {
      _usingDevice = false;
      _voiceHandler?.call(voiceKind);
    }
    await _expressive.loadTrack(
      sessionId: sessionId,
      chapters: chapters,
      initialChapterIndex: initialChapterIndex,
      initialSegmentIndex: initialSegmentIndex,
    );
  }

  @override
  Future<void> playTrack() => _expressive.playTrack();

  @override
  Future<void> pauseTrack() => _expressive.pauseTrack();

  @override
  Future<void> seekToSentence({
    required int chapterIndex,
    required int segmentIndex,
  }) => _expressive.seekToSentence(
    chapterIndex: chapterIndex,
    segmentIndex: segmentIndex,
  );

  @override
  Future<void> prepare(String text) async {
    if (_usingDevice) return;
    try {
      await _expressive.prepare(text);
    } catch (_) {
      // speak() performs the visible, deterministic fallback. A speculative
      // prefetch failure should not interrupt the sentence already playing.
    }
  }

  @override
  Future<void> speak(String text) async {
    _trackActive = false;
    if (!_usingDevice) {
      try {
        if (!_expressiveReady) {
          await _expressive.initialize(speed: _speed);
          _expressiveReady = true;
        }
        await _expressive.speak(text);
        return;
      } catch (_) {
        await _expressive.stop();
        await _switchToDevice();
      }
    }
    await _device.speak(text);
  }

  Future<void> _switchToDevice() async {
    if (!_deviceReady) {
      await _device.initialize(speed: _speed);
      _deviceReady = true;
    }
    if (!_usingDevice) {
      _usingDevice = true;
      _voiceHandler?.call(voiceKind);
    }
  }

  @override
  Future<void> stop() async {
    _trackActive = false;
    await Future.wait<void>([_expressive.stop(), _device.stop()]);
  }

  @override
  Future<void> dispose() async {
    _progressHandler = null;
    _errorHandler = null;
    _voiceHandler = null;
    _trackHandler = null;
    await Future.wait<void>([_expressive.dispose(), _device.dispose()]);
  }
}

final class _LocalNarrationCue {
  const _LocalNarrationCue(this.start, this.end);

  final int start;
  final int end;
}

/// Returns a cue only while media time is inside that cue. Natural pauses,
/// initial buffering silence, and trailing silence deliberately return null so
/// the UI never pretends a word or phrase is being spoken.
@visibleForTesting
BookNarrationCue? activeBookNarrationCueAt(
  List<BookNarrationCue> alignment,
  Duration position,
) {
  var low = 0;
  var high = alignment.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final cue = alignment[middle];
    if (position < cue.startTime) {
      high = middle - 1;
    } else if (position >= cue.endTime) {
      low = middle + 1;
    } else if (cue.start < cue.end && cue.startTime < cue.endTime) {
      return cue;
    } else {
      return null;
    }
  }
  return null;
}

/// Device-local narration using the installed system voices. No network or
/// generated audio is required.
final class SystemBookNarrator implements BookNarrator {
  SystemBookNarrator({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts() {
    _flutterTts.setProgressHandler((_, start, end, word) {
      _progressHandler?.call(start, end, word);
    });
    _flutterTts.setErrorHandler((message) {
      _errorHandler?.call(StateError(message.toString()));
    });
  }

  final FlutterTts _flutterTts;
  BookNarrationProgressHandler? _progressHandler;
  BookNarrationErrorHandler? _errorHandler;
  bool _initialized = false;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    _progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    _errorHandler = handler;
  }

  @override
  Future<void> initialize({required double speed}) async {
    if (!_initialized) {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setVolume(1);
      await _flutterTts.setPitch(1);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      }
      _initialized = true;
    }
    await setSpeed(speed);
  }

  @override
  Future<void> setSpeed(double speed) async {
    // flutter_tts exposes a normalized 0…1 platform rate. In both supported
    // native readers, 0.5 is the natural system speaking rate.
    final platformRate = (speed * 0.5).clamp(0.25, 1.0).toDouble();
    await _flutterTts.setSpeechRate(platformRate);
  }

  @override
  Future<void> speak(String text) async {
    await _flutterTts.speak(text, focus: true);
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  @override
  Future<void> dispose() async {
    _progressHandler = null;
    _errorHandler = null;
    await stop();
  }
}

enum BookNarrationBlockKind { paragraph, heading, listItem, quote, code }

@immutable
class BookNarrationBlock {
  const BookNarrationBlock({
    required this.text,
    required this.kind,
    required this.firstSegmentIndex,
    required this.segmentCount,
    this.headingLevel = 0,
    this.listMarker,
  });

  final String text;
  final BookNarrationBlockKind kind;
  final int firstSegmentIndex;
  final int segmentCount;
  final int headingLevel;
  final String? listMarker;

  bool get containsSpeech => segmentCount > 0;
}

@immutable
class BookNarrationSegment {
  const BookNarrationSegment({
    required this.index,
    required this.blockIndex,
    required this.start,
    required this.end,
    required this.text,
  });

  final int index;
  final int blockIndex;
  final int start;
  final int end;
  final String text;
}

@immutable
class BookNarrationChunkSegment {
  const BookNarrationChunkSegment({
    required this.segmentIndex,
    required this.start,
    required this.end,
    required this.segmentStart,
    required this.segmentEnd,
  });

  final int segmentIndex;
  final int start;
  final int end;
  final int segmentStart;
  final int segmentEnd;
}

@immutable
class BookNarrationChunk {
  const BookNarrationChunk({
    required this.index,
    required this.text,
    required this.segments,
  });

  final int index;
  final String text;
  final List<BookNarrationChunkSegment> segments;

  bool containsSegment(int segmentIndex) =>
      segments.any((slice) => slice.segmentIndex == segmentIndex);

  BookNarrationChunkSegment? segmentAtOffset(int offset) {
    for (final slice in segments) {
      if (offset >= slice.start && offset < slice.end) return slice;
    }
    return null;
  }
}

/// A speech-friendly view of the same Markdown used by the visual reader.
/// Sentences remain stable navigation/highlight units. Playback uses longer
/// paragraph-aware [chunks], which lets the AI preserve prosody and gives the
/// audio player enough material to buffer the following chunk without gaps.
@immutable
class BookNarrationDocument {
  const BookNarrationDocument({
    required this.blocks,
    required this.segments,
    required this.chunks,
  });

  factory BookNarrationDocument.fromMarkdown(String markdown) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ).parse(markdown);
    final drafts = <_NarrationBlockDraft>[];

    void appendNode(md.Node node, {String? listMarker}) {
      if (node is md.Text) {
        final text = _readableText(node);
        if (text.isNotEmpty) {
          drafts.add(
            _NarrationBlockDraft(
              text: text,
              kind: BookNarrationBlockKind.paragraph,
            ),
          );
        }
        return;
      }
      if (node is! md.Element) return;

      switch (node.tag) {
        case 'hr':
          return;
        case 'ul':
        case 'ol':
          final ordered = node.tag == 'ol';
          var ordinal = int.tryParse(node.attributes['start'] ?? '') ?? 1;
          for (final child in node.children ?? const <md.Node>[]) {
            if (child is! md.Element || child.tag != 'li') continue;
            appendNode(child, listMarker: ordered ? '${ordinal++}.' : '•');
          }
          return;
        case 'li':
          final nestedLists = <md.Element>[];
          final visibleChildren = <md.Node>[];
          for (final child in node.children ?? const <md.Node>[]) {
            if (child is md.Element &&
                (child.tag == 'ul' || child.tag == 'ol')) {
              nestedLists.add(child);
            } else {
              visibleChildren.add(child);
            }
          }
          final text = _readableNodes(visibleChildren);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.listItem,
                listMarker: listMarker ?? '•',
              ),
            );
          }
          for (final nested in nestedLists) {
            appendNode(nested);
          }
          return;
        case 'blockquote':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.quote,
              ),
            );
          }
          return;
        case 'pre':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.code,
              ),
            );
          }
          return;
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.heading,
                headingLevel: int.parse(node.tag.substring(1)),
              ),
            );
          }
          return;
        case 'p':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.paragraph,
              ),
            );
          }
          return;
        default:
          final children = node.children ?? const <md.Node>[];
          final containsBlocks = children.any(
            (child) => child is md.Element && _blockTags.contains(child.tag),
          );
          if (containsBlocks) {
            for (final child in children) {
              appendNode(child);
            }
          } else {
            final text = _readableText(node);
            if (text.isNotEmpty) {
              drafts.add(
                _NarrationBlockDraft(
                  text: text,
                  kind: BookNarrationBlockKind.paragraph,
                ),
              );
            }
          }
      }
    }

    for (final node in nodes) {
      appendNode(node);
    }

    final blocks = <BookNarrationBlock>[];
    final segments = <BookNarrationSegment>[];
    for (var blockIndex = 0; blockIndex < drafts.length; blockIndex++) {
      final draft = drafts[blockIndex];
      final ranges = _sentenceRanges(draft.text);
      final firstSegment = segments.length;
      for (final range in ranges) {
        segments.add(
          BookNarrationSegment(
            index: segments.length,
            blockIndex: blockIndex,
            start: range.start,
            end: range.end,
            text: draft.text.substring(range.start, range.end),
          ),
        );
      }
      blocks.add(
        BookNarrationBlock(
          text: draft.text,
          kind: draft.kind,
          firstSegmentIndex: firstSegment,
          segmentCount: ranges.length,
          headingLevel: draft.headingLevel,
          listMarker: draft.listMarker,
        ),
      );
    }
    return BookNarrationDocument(
      blocks: blocks,
      segments: segments,
      chunks: _buildNarrationChunks(blocks, segments),
    );
  }

  final List<BookNarrationBlock> blocks;
  final List<BookNarrationSegment> segments;
  final List<BookNarrationChunk> chunks;
}

const _narrationChunkMinCharacters = 600;
const _narrationChunkPreferredMaxCharacters = 1200;
const _narrationChunkHardMaxCharacters = 1800;

List<BookNarrationChunk> _buildNarrationChunks(
  List<BookNarrationBlock> blocks,
  List<BookNarrationSegment> segments,
) {
  if (segments.isEmpty) return const [];
  final parts = <_NarrationSegmentPart>[];
  for (final segment in segments) {
    var start = 0;
    while (start < segment.text.length) {
      var end = (start + _narrationChunkHardMaxCharacters)
          .clamp(start, segment.text.length)
          .toInt();
      if (end < segment.text.length) {
        var boundary = end;
        final minimumBoundary = start + (_narrationChunkHardMaxCharacters ~/ 2);
        while (boundary > minimumBoundary &&
            !_isWhitespace(segment.text[boundary - 1])) {
          boundary--;
        }
        if (boundary > minimumBoundary) end = boundary;
      }
      while (end > start && _isWhitespace(segment.text[end - 1])) {
        end--;
      }
      if (end <= start) {
        end = (start + _narrationChunkHardMaxCharacters)
            .clamp(start + 1, segment.text.length)
            .toInt();
      }
      parts.add(
        _NarrationSegmentPart(
          segment: segment,
          segmentStart: start,
          segmentEnd: end,
        ),
      );
      start = end;
      while (start < segment.text.length &&
          _isWhitespace(segment.text[start])) {
        start++;
      }
    }
  }

  final chunks = <BookNarrationChunk>[];
  var buffer = StringBuffer();
  var slices = <BookNarrationChunkSegment>[];
  _NarrationSegmentPart? previous;

  void flush() {
    if (buffer.isEmpty) return;
    chunks.add(
      BookNarrationChunk(
        index: chunks.length,
        text: buffer.toString(),
        segments: List.unmodifiable(slices),
      ),
    );
    buffer = StringBuffer();
    slices = <BookNarrationChunkSegment>[];
    previous = null;
  }

  String separatorFor(
    _NarrationSegmentPart before,
    _NarrationSegmentPart after,
  ) {
    if (before.segment.index == after.segment.index) {
      return before.segment.text.substring(
        before.segmentEnd,
        after.segmentStart,
      );
    }
    if (before.segment.blockIndex != after.segment.blockIndex) return '\n\n';
    final block = blocks[before.segment.blockIndex];
    final gapStart = before.segment.end;
    final gapEnd = after.segment.start;
    if (gapStart >= gapEnd) return ' ';
    return block.text.substring(gapStart, gapEnd);
  }

  for (final part in parts) {
    var separator = previous == null ? '' : separatorFor(previous!, part);
    var candidateLength = buffer.length + separator.length + part.text.length;
    final beginsNewBlock =
        previous != null &&
        previous!.segment.blockIndex != part.segment.blockIndex;
    final shouldPreferBoundary =
        buffer.length >= _narrationChunkMinCharacters &&
        (beginsNewBlock ||
            candidateLength > _narrationChunkPreferredMaxCharacters);
    if (buffer.isNotEmpty &&
        (shouldPreferBoundary ||
            candidateLength > _narrationChunkHardMaxCharacters)) {
      flush();
      separator = '';
      candidateLength = part.text.length;
    }
    assert(candidateLength <= _narrationChunkHardMaxCharacters);
    buffer.write(separator);
    final sliceStart = buffer.length;
    buffer.write(part.text);
    slices.add(
      BookNarrationChunkSegment(
        segmentIndex: part.segment.index,
        start: sliceStart,
        end: buffer.length,
        segmentStart: part.segmentStart,
        segmentEnd: part.segmentEnd,
      ),
    );
    previous = part;
  }
  flush();
  return List.unmodifiable(chunks);
}

List<_NarrationTrackEntry> _buildTrackEntries({
  required List<BookNarrationDocument> chapters,
  required int initialChapterIndex,
  required int initialSegmentIndex,
}) {
  final entries = <_NarrationTrackEntry>[];
  for (
    var chapterIndex = initialChapterIndex;
    chapterIndex < chapters.length;
    chapterIndex++
  ) {
    final document = chapters[chapterIndex];
    var firstChunk = 0;
    if (chapterIndex == initialChapterIndex) {
      final located = document.chunks.indexWhere(
        (chunk) => chunk.containsSegment(initialSegmentIndex),
      );
      if (located >= 0) firstChunk = located;
    }
    for (
      var chunkIndex = firstChunk;
      chunkIndex < document.chunks.length;
      chunkIndex++
    ) {
      entries.add(
        _NarrationTrackEntry(
          chapterIndex: chapterIndex,
          chunk: document.chunks[chunkIndex],
        ),
      );
    }
  }
  return List.unmodifiable(entries);
}

final class _NarrationSegmentPart {
  const _NarrationSegmentPart({
    required this.segment,
    required this.segmentStart,
    required this.segmentEnd,
  });

  final BookNarrationSegment segment;
  final int segmentStart;
  final int segmentEnd;

  String get text => segment.text.substring(segmentStart, segmentEnd);
}

final class _NarrationTrackEntry {
  const _NarrationTrackEntry({required this.chapterIndex, required this.chunk});

  final int chapterIndex;
  final BookNarrationChunk chunk;
}

const _blockTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'blockquote',
  'pre',
  'table',
};

String _readableText(md.Node node) => _readableNodes([node]);

String _readableNodes(List<md.Node> nodes) {
  final buffer = StringBuffer();

  void writeNode(md.Node node) {
    if (node is md.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! md.Element) return;
    if (node.tag == 'br') {
      buffer.write(' ');
      return;
    }
    if (node.tag == 'img') {
      buffer.write(node.attributes['alt'] ?? '');
      return;
    }
    final separatesText = const {
      'p',
      'div',
      'td',
      'th',
      'tr',
    }.contains(node.tag);
    if (separatesText && buffer.isNotEmpty) buffer.write(' ');
    for (final child in node.children ?? const <md.Node>[]) {
      writeNode(child);
    }
    if (separatesText) buffer.write(' ');
  }

  for (final node in nodes) {
    writeNode(node);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<_TextRange> _sentenceRanges(String text) {
  final ranges = <_TextRange>[];
  var start = 0;

  bool isTerminator(String character) => '.!?…。！？'.contains(character);
  bool isClosingMark(String character) => '”’"\')]}'.contains(character);

  bool isAbbreviation(int end) {
    final start = (end - 8).clamp(0, end).toInt();
    final prefix = text.substring(start, end).toLowerCase();
    return const [
      'e.g.',
      'i.e.',
      'mr.',
      'mrs.',
      'ms.',
      'dr.',
      'prof.',
      'vs.',
    ].any(prefix.endsWith);
  }

  void addRange(int rawStart, int rawEnd) {
    var rangeStart = rawStart;
    var rangeEnd = rawEnd;
    while (rangeStart < rangeEnd && _isWhitespace(text[rangeStart])) {
      rangeStart++;
    }
    while (rangeEnd > rangeStart && _isWhitespace(text[rangeEnd - 1])) {
      rangeEnd--;
    }
    if (rangeStart < rangeEnd) {
      ranges.add(_TextRange(rangeStart, rangeEnd));
    }
  }

  for (var index = 0; index < text.length; index++) {
    if (!isTerminator(text[index])) continue;
    var end = index + 1;
    while (end < text.length && isTerminator(text[end])) {
      end++;
    }
    while (end < text.length && isClosingMark(text[end])) {
      end++;
    }
    if (end < text.length && !_isWhitespace(text[end])) continue;
    if (end < text.length && isAbbreviation(end)) continue;
    addRange(start, end);
    start = end;
  }
  addRange(start, text.length);

  if (ranges.isEmpty && text.trim().isNotEmpty) {
    final first = text.indexOf(text.trimLeft());
    ranges.add(_TextRange(first, first + text.trim().length));
  }
  return ranges;
}

bool _isWhitespace(String character) => character.trim().isEmpty;

final class _NarrationBlockDraft {
  const _NarrationBlockDraft({
    required this.text,
    required this.kind,
    this.headingLevel = 0,
    this.listMarker,
  });

  final String text;
  final BookNarrationBlockKind kind;
  final int headingLevel;
  final String? listMarker;
}

final class _TextRange {
  const _TextRange(this.start, this.end);

  final int start;
  final int end;
}
