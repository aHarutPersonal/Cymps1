import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Native transport boundary only. Production narration queue/state logic runs
/// unchanged around this player; no audio or synthesis network calls occur.
class FakeBookAudioPlayer extends Fake implements AudioPlayer {
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final indexes = StreamController<int?>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final sources = <AudioSource>[];
  int loads = 0, plays = 0, pauses = 0;
  Object? playError;
  Completer<void>? nextAddGate;
  Completer<void>? nextSeekGate;
  Completer<void>? nextPositionCancellationGate;
  int adds = 0, seeks = 0;
  int? repeatedIndexOnPause;

  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration = const Duration(seconds: 20);
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<int?> get currentIndexStream => indexes.stream;
  @override
  Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 200),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) {
    final gate = nextPositionCancellationGate;
    nextPositionCancellationGate = null;
    return gate == null
        ? positions.stream
        : _CancellationGateStream(positions.stream, gate);
  }

  void emitState(ProcessingState state) {
    processingState = state;
    states.add(PlayerState(playing, state));
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loads++;
    sources
      ..clear()
      ..addAll(audioSources);
    emitState(ProcessingState.ready);
    return duration;
  }

  @override
  Future<void> addAudioSource(AudioSource source) async {
    adds++;
    final gate = nextAddGate;
    nextAddGate = null;
    if (gate != null) await gate.future;
    sources.add(source);
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> stop() async {
    playing = false;
    emitState(ProcessingState.idle);
  }

  @override
  Future<void> play() async {
    plays++;
    if (playError case final error?) throw error;
    playing = true;
    emitState(ProcessingState.ready);
  }

  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
    if (repeatedIndexOnPause case final index?) indexes.add(index);
    emitState(processingState);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks++;
    final gate = nextSeekGate;
    nextSeekGate = null;
    if (gate != null) await gate.future;
    this.position = position ?? Duration.zero;
    if (index != null) indexes.add(index);
    positions.add(this.position);
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      errors.close(),
      states.close(),
      indexes.close(),
      positions.close(),
    ]);
  }
}

class _CancellationGateStream<T> extends Fake implements Stream<T> {
  _CancellationGateStream(this.inner, this.gate);
  final Stream<T> inner;
  final Completer<void> gate;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _CancellationGateSubscription(
    inner.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
    gate,
  );
}

class _CancellationGateSubscription<T> extends Fake
    implements StreamSubscription<T> {
  _CancellationGateSubscription(this.inner, this.gate);
  final StreamSubscription<T> inner;
  final Completer<void> gate;
  bool held = false;
  @override
  Future<void> cancel() async {
    if (!held) {
      held = true;
      await gate.future;
    }
    await inner.cancel();
  }
}
