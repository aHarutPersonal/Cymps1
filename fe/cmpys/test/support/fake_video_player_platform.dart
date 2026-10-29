// A fake video_player platform for widget tests: no real video runs.
//
// Install it in setUp (`FakeVideoPlayerPlatform.install()`), then drive
// each player from the test:
//
// - `initialize(id)` sends the "initialized" event (or pass
//   `autoInitialize: true` to do it as soon as the player is created);
// - `fail(id)` sends a platform error;
// - `renderFrame(id)` moves the playback position past zero, which is what
//   `V3LoopVideo` treats as "a frame has played" (or pass
//   `autoFrames: true` to do it on every `play`). The controller polls the
//   position every 100 ms while playing, so pump at least that long.
//
// `created`, `isPlaying(id)`, `volumes`, `looping` and `calls` record what
// the app asked for.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({
    this.autoInitialize = false,
    this.autoFrames = false,
  });

  /// Installs a fresh fake as the platform and returns it.
  static FakeVideoPlayerPlatform install({
    bool autoInitialize = false,
    bool autoFrames = false,
  }) {
    final fake = FakeVideoPlayerPlatform(
      autoInitialize: autoInitialize,
      autoFrames: autoFrames,
    );
    VideoPlayerPlatform.instance = fake;
    return fake;
  }

  final bool autoInitialize;
  final bool autoFrames;

  /// Every call, in order (`create:asset`, `play:1`, `pause:1`, …).
  final List<String> calls = [];

  /// Player id → the asset it was created for.
  final Map<int, String> created = {};
  final Set<int> disposed = {};
  final Map<int, double> volumes = {};
  final Map<int, bool> looping = {};
  final Map<int, Duration> _positions = {};
  final Set<int> _playing = {};
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextId = 1;

  bool isPlaying(int id) => _playing.contains(id);

  /// The ids of the players created for [asset], oldest first.
  List<int> idsFor(String asset) => [
    for (final e in created.entries)
      if (e.value == asset) e.key,
  ];

  /// Sends the "initialized" event for [id] (a 720×1280, 8 s video).
  void initialize(int id) => _events[id]?.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 8),
      size: const Size(720, 1280),
    ),
  );

  /// Sends a platform error for [id].
  void fail(int id) => _events[id]?.addError(
    PlatformException(code: 'VideoError', message: 'fake failure'),
  );

  /// Moves [id]'s position past zero: a frame has played.
  void renderFrame(int id) {
    final now = _positions[id] ?? Duration.zero;
    _positions[id] = now + const Duration(milliseconds: 40);
  }

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    final asset = options.dataSource.asset ?? options.dataSource.uri ?? '';
    created[id] = asset;
    calls.add('create:$asset');
    _events[id] = StreamController<VideoEvent>(
      onListen: autoInitialize
          ? () => scheduleMicrotask(() => initialize(id))
          : null,
      // A cancel future from this zone: the default one belongs to the root
      // zone, which a widget test's fake clock never runs, so the
      // controller's dispose would never reach `dispose()` here.
      onCancel: () => Future<void>.value(),
    );
    return id;
  }

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
    VideoCreationOptions(
      dataSource: dataSource,
      viewType: VideoViewType.textureView,
    ),
  );

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose:$playerId');
    disposed.add(playerId);
    _playing.remove(playerId);
    // Not awaited: `done` waits for a listener that has already gone.
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play:$playerId');
    _playing.add(playerId);
    if (autoFrames) renderFrame(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause:$playerId');
    _playing.remove(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      this.looping[playerId] = looping;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes[playerId] = volume;

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _positions[playerId] = position;

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async =>
      calls.add('mixWithOthers:$mixWithOthers');

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
    key: ValueKey<String>('fake-video-${options.playerId}'),
    color: const Color(0xFF223344),
  );

  @override
  Widget buildView(int playerId) =>
      buildViewWithOptions(VideoViewOptions(playerId: playerId));
}
