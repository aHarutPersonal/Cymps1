import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';

// `LoopVideo` from `v3/core.jsx`: the app's only video widget. Bundled
// assets only (no streaming), muted and looping, faded in once a frame has
// played, with the current design as the fallback.

/// Plays one bundled video [asset] as a muted, looping background, over
/// [fallback] (the current design for this spot).
///
/// - The fallback shows until a frame of the video has actually played; the
///   video then fades in to [opacity] over [opacityDuration] (1.2 s on
///   `--out`, the prototype's `transition: opacity 1.2s var(--out)`), after
///   which the fallback is taken offstage (its state is kept, its tickers
///   stop). It never shows a black box or a spinner instead.
/// - On an error, or when it isn't playing within [readyTimeout] (6 s) of
///   loading or of being asked to play, it gives up for good: the fallback
///   stays and [onReady] gets `false`.
/// - It plays only while [playing] is true, it is on screen (its route is
///   current and its tab is selected, see [TickerMode]; at least part of it
///   is inside every enclosing scroll view and the screen), the app is in the
///   foreground, and no other [V3LoopVideo] started after it is playing
///   ([V3VideoCoordinator]: one video at a time). Otherwise it pauses on its
///   current frame.
/// - With reduced motion ([MotionConfig]) it never creates a player: the
///   fallback shows, static (owner rule: no autoplay, no loops).
///
/// [saturation], [brightness] and [blur] filter the video (CSS
/// `saturate() brightness() blur()`), animating over [filterDuration];
/// [scale] zooms it, animating over [scaleDuration]. [initialScale] (when
/// set) is where the zoom starts on mount, so `initialScale: 1.12, scale: 1`
/// is the design's Ken Burns `kbIn`. All of these apply to the video only,
/// never to the fallback.
class V3LoopVideo extends StatefulWidget {
  const V3LoopVideo({
    super.key,
    required this.asset,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.playing = true,
    this.opacity = 1,
    this.opacityDuration = const Duration(milliseconds: 1200),
    this.opacityCurve = AppMotion.out,
    this.saturation = 1,
    this.brightness = 1,
    this.blur = 0,
    this.filterDuration = const Duration(milliseconds: 800),
    this.filterCurve = Curves.ease,
    this.scale = 1,
    this.initialScale,
    this.scaleDuration = const Duration(milliseconds: 600),
    this.scaleCurve = AppMotion.out,
    this.readyTimeout = const Duration(seconds: 6),
    this.onReady,
  });

  /// Key on the faded video layer (an [AnimatedOpacity]), for tests.
  static const layerKey = ValueKey<String>('v3-loop-video-layer');

  /// A bundled asset path (`AppAssets.video*`). Never a URL.
  final String asset;

  /// What shows until the video plays, and for good if it can't.
  final Widget fallback;
  final BoxFit fit;

  /// False pauses the video on its current frame.
  final bool playing;

  /// The video's opacity once it plays (the prototype's `dim`).
  final double opacity;
  final Duration opacityDuration;
  final Curve opacityCurve;

  /// CSS `saturate()`: 1 is unchanged, 0 is grey.
  final double saturation;

  /// CSS `brightness()`: 1 is unchanged.
  final double brightness;

  /// CSS `blur()` in logical pixels: 0 is sharp.
  final double blur;
  final Duration filterDuration;
  final Curve filterCurve;

  /// The video's zoom about its centre.
  final double scale;

  /// The zoom on mount, animating to [scale]; null starts at [scale].
  final double? initialScale;
  final Duration scaleDuration;
  final Curve scaleCurve;

  /// How long loading, or getting a first frame once asked to play, may
  /// take before the video gives up and the fallback stays.
  final Duration readyTimeout;

  /// `true` when the video starts fading in; `false` when it gives up
  /// (error, timeout) or stops showing (reduced motion turned on).
  final ValueChanged<bool>? onReady;

  @override
  State<V3LoopVideo> createState() => _V3LoopVideoState();
}

/// The single app-wide rule that only one [V3LoopVideo] plays at a time.
///
/// A video asks to play when it becomes able to (loaded, [V3LoopVideo.playing],
/// on screen) and withdraws when it no longer is. The latest one to ask
/// plays; every other one pauses. When the playing one withdraws, the most
/// recent remaining one resumes. While the app is in the background none
/// plays.
class V3VideoCoordinator with WidgetsBindingObserver {
  V3VideoCoordinator._();

  static final V3VideoCoordinator instance = V3VideoCoordinator._();

  final List<_V3LoopVideoState> _queue = [];
  _V3LoopVideoState? _active;
  bool _observing = false;
  bool _foreground = true;

  /// How many videos are waiting to play or playing (for tests).
  @visibleForTesting
  int get debugWaiting => _queue.length;

  /// Whether a video is playing now (for tests).
  @visibleForTesting
  bool get debugHasActive => _active != null;

  /// Forgets the app lifecycle state (for tests that simulate it).
  @visibleForTesting
  void debugReset() {
    _foreground = true;
    _apply();
  }

  void _ensureObserving() {
    if (_observing) return;
    _observing = true;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _foreground = _isForeground(binding.lifecycleState);
  }

  static bool _isForeground(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _request(_V3LoopVideoState video) {
    _ensureObserving();
    _queue
      ..remove(video)
      ..add(video);
    _apply();
  }

  void _release(_V3LoopVideoState video) {
    if (!_queue.remove(video)) return;
    if (identical(_active, video)) {
      _active = null;
      video._setActive(false);
    }
    _apply();
  }

  void _apply() {
    final next = _foreground && _queue.isNotEmpty ? _queue.last : null;
    if (identical(next, _active)) return;
    final previous = _active;
    _active = next;
    previous?._setActive(false);
    next?._setActive(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = _isForeground(state);
    if (foreground == _foreground) return;
    _foreground = foreground;
    _apply();
  }
}

/// Swallows a player future's error: a failed play or pause leaves the
/// fallback in place, it never surfaces as an uncaught error.
void _quietly(Future<void> future) =>
    unawaited(future.then((_) {}, onError: (Object _) {}));

class _V3LoopVideoState extends State<V3LoopVideo> {
  VideoPlayerController? _controller;

  /// Bumped whenever the controller is replaced, so a late callback from
  /// an old one is ignored.
  int _generation = 0;

  bool _initialized = false;

  /// A frame has played: the video is fading in (or in).
  bool _ready = false;

  /// The fade-in finished: the fallback is offstage.
  bool _shown = false;

  /// Gave up (error or timeout); the fallback stays.
  bool _failed = false;

  /// Asked the coordinator to play.
  bool _requested = false;

  /// The coordinator's pick.
  bool _active = false;

  Timer? _timeout;

  bool _motion = true;
  bool _routeVisible = true;
  bool _inViewport = true;
  Size? _screen;
  final List<ScrollableState> _scrollables = [];
  final List<ScrollPosition> _positions = [];
  bool _viewportCheckPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionConfig.enabled(context);
    _routeVisible =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    _screen = MediaQuery.maybeSizeOf(context);
    _listenToScrollables();
    if (_motion) {
      _ensureController();
    } else if (_controller != null) {
      _stop();
    }
    _scheduleViewportCheck();
    _sync();
  }

  @override
  void didUpdateWidget(V3LoopVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _stop();
      _failed = false;
      if (_motion) _ensureController();
    }
    _sync();
  }

  @override
  void dispose() {
    for (final p in _positions) {
      p.removeListener(_scheduleViewportCheck);
    }
    _positions.clear();
    _scrollables.clear();
    _teardown();
    super.dispose();
  }

  // ── controller ──

  void _ensureController() {
    if (_controller != null || _failed) return;
    final generation = ++_generation;
    final controller = VideoPlayerController.asset(
      widget.asset,
      // Mix with other audio: a muted background loop must never stop the
      // user's music. Backgrounding is handled by the coordinator, not the
      // plugin's own observer (which would resume a video it paused).
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: true,
      ),
    );
    _controller = controller;
    // Applied to the player as soon as it is created, before any frame.
    _quietly(controller.setVolume(0));
    _quietly(controller.setLooping(true));
    controller.addListener(_onValue);
    _armTimeout();
    controller.initialize().then(
      (_) {
        if (!mounted || generation != _generation) return;
        _disarmTimeout();
        setState(() => _initialized = true);
        _sync();
      },
      onError: (Object _) {
        if (!mounted || generation != _generation) return;
        _fail();
      },
    );
  }

  void _onValue() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError) {
      _fail();
      return;
    }
    // A frame has been shown once the position moves while playing (the
    // prototype waits for `onPlaying`); until then the fallback stays, so
    // there is never a black frame.
    if (!_ready &&
        value.isInitialized &&
        value.isPlaying &&
        value.position > Duration.zero) {
      _disarmTimeout();
      _ready = true;
      final generation = _generation;
      _whenSafe(() {
        if (generation != _generation) return;
        setState(() {});
        widget.onReady?.call(true);
      });
    }
  }

  /// Runs [action] now, or after the frame when a build or layout is under
  /// way (a player can notify while the coordinator pauses or plays it from
  /// another video's build). Skipped once unmounted.
  void _whenSafe(VoidCallback action) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) action();
      });
    } else if (mounted) {
      action();
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    _teardown();
    _whenSafe(() {
      setState(() {});
      widget.onReady?.call(false);
    });
  }

  /// Drops the player without giving up for good (reduced motion turned
  /// on, or a new asset). Called from didChangeDependencies and
  /// didUpdateWidget, so a build follows; the parent hears after the frame.
  void _stop() {
    final wasReady = _ready;
    _teardown();
    if (wasReady) _whenSafe(() => widget.onReady?.call(false));
  }

  void _teardown() {
    _disarmTimeout();
    final controller = _controller;
    _controller = null;
    _generation++;
    _initialized = false;
    _ready = false;
    _shown = false;
    if (_requested) {
      _requested = false;
      V3VideoCoordinator.instance._release(this);
    }
    _active = false;
    if (controller != null) {
      controller.removeListener(_onValue);
      _quietly(controller.dispose());
    }
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(widget.readyTimeout, () {
      _timeout = null;
      if (mounted && !_ready) _fail();
    });
  }

  void _disarmTimeout() {
    _timeout?.cancel();
    _timeout = null;
  }

  // ── playing ──

  bool get _wantsToPlay =>
      _motion &&
      widget.playing &&
      _initialized &&
      !_failed &&
      _routeVisible &&
      _inViewport;

  void _sync() {
    final want = mounted && _wantsToPlay;
    if (want == _requested) return;
    _requested = want;
    if (want) {
      V3VideoCoordinator.instance._request(this);
    } else {
      V3VideoCoordinator.instance._release(this);
    }
  }

  /// Called by the coordinator.
  void _setActive(bool active) {
    if (_active == active) return;
    _active = active;
    final controller = _controller;
    if (controller == null) return;
    if (active) {
      _quietly(controller.play());
      if (!_ready) _armTimeout();
    } else {
      _quietly(controller.pause());
      _disarmTimeout();
    }
  }

  // ── viewport ──

  /// Follows every enclosing scroll view (nearest first), re-checking the
  /// viewport whenever one scrolls.
  void _listenToScrollables() {
    final found = <ScrollableState>[];
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      found.add(scrollable);
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    final positions = [for (final s in found) s.position];
    if (listEquals(positions, _positions)) return;
    for (final p in _positions) {
      p.removeListener(_scheduleViewportCheck);
    }
    _scrollables
      ..clear()
      ..addAll(found);
    _positions
      ..clear()
      ..addAll(positions);
    for (final p in _positions) {
      p.addListener(_scheduleViewportCheck);
    }
  }

  /// Re-checks the viewport after the next frame is laid out (scrolling,
  /// first layout). Scroll offsets change before layout, so the check waits
  /// for the frame.
  void _scheduleViewportCheck() {
    if (_viewportCheckPending) return;
    _viewportCheckPending = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _viewportCheckPending = false;
        if (!mounted) return;
        final inViewport = _computeInViewport();
        if (inViewport == _inViewport) return;
        _inViewport = inViewport;
        _sync();
      })
      ..ensureVisualUpdate();
  }

  bool _computeInViewport() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return true;
    var rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    bool empty(Rect r) => r.width <= 0 || r.height <= 0;
    for (final scrollable in _scrollables) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
        continue;
      }
      rect = rect.intersect(
        MatrixUtils.transformRect(
          viewport.getTransformTo(null),
          Offset.zero & viewport.size,
        ),
      );
      if (empty(rect)) return false;
    }
    final screen = _screen;
    if (screen != null && empty(rect.intersect(Offset.zero & screen))) {
      return false;
    }
    return true;
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept mounted (state and layout) but offstage once the video is in,
        // so a looping fallback stops costing frames.
        Visibility(
          visible: !_shown,
          maintainState: true,
          child: widget.fallback,
        ),
        if (controller != null)
          ExcludeSemantics(
            child: IgnorePointer(
              child: ClipRect(child: _videoLayer(controller)),
            ),
          ),
      ],
    );
  }

  Widget _videoLayer(VideoPlayerController controller) {
    final value = controller.value;
    final size = value.size;
    final Widget picture = _initialized
        ? FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              // 720×1280 (every bundled video) until the size is known.
              width: size.width > 0 ? size.width : 720,
              height: size.height > 0 ? size.height : 1280,
              child: VideoPlayer(controller),
            ),
          )
        : const SizedBox.expand();

    return AnimatedOpacity(
      key: V3LoopVideo.layerKey,
      opacity: _ready ? widget.opacity.clamp(0.0, 1.0) : 0,
      duration: widget.opacityDuration,
      curve: widget.opacityCurve,
      onEnd: () {
        if (mounted && _ready && !_shown) setState(() => _shown = true);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: widget.initialScale ?? widget.scale,
          end: widget.scale,
        ),
        duration: widget.scaleDuration,
        curve: widget.scaleCurve,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: TweenAnimationBuilder<_Filter>(
          tween: _FilterTween(
            begin: _Filter(widget.saturation, widget.brightness, widget.blur),
            end: _Filter(widget.saturation, widget.brightness, widget.blur),
          ),
          duration: widget.filterDuration,
          curve: widget.filterCurve,
          builder: (context, filter, child) => ImageFiltered(
            enabled: !filter.isColorIdentity,
            imageFilter: ColorFilter.matrix(filter.matrix),
            child: ImageFiltered(
              enabled: filter.blur > 0.01,
              imageFilter: ImageFilter.blur(
                sigmaX: filter.blur,
                sigmaY: filter.blur,
                tileMode: TileMode.clamp,
              ),
              child: child,
            ),
          ),
          child: picture,
        ),
      ),
    );
  }
}

/// CSS `saturate(s) brightness(b) blur(r)` as one animatable value.
@immutable
class _Filter {
  const _Filter(this.saturation, this.brightness, this.blur);

  final double saturation;
  final double brightness;
  final double blur;

  @override
  bool operator ==(Object other) =>
      other is _Filter &&
      other.saturation == saturation &&
      other.brightness == brightness &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(saturation, brightness, blur);

  bool get isColorIdentity =>
      (saturation - 1).abs() < 0.001 && (brightness - 1).abs() < 0.001;

  /// The CSS filter-effects `saturate()` matrix, then `brightness()`.
  List<double> get matrix {
    final s = saturation;
    final b = brightness;
    return [
      b * (0.213 + 0.787 * s),
      b * (0.715 - 0.715 * s),
      b * (0.072 - 0.072 * s),
      0,
      0, //
      b * (0.213 - 0.213 * s),
      b * (0.715 + 0.285 * s),
      b * (0.072 - 0.072 * s),
      0,
      0,
      b * (0.213 - 0.213 * s),
      b * (0.715 - 0.715 * s),
      b * (0.072 + 0.928 * s),
      0,
      0,
      0, 0, 0, 1, 0,
    ];
  }
}

class _FilterTween extends Tween<_Filter> {
  _FilterTween({required super.begin, required super.end});

  @override
  _Filter lerp(double t) {
    final a = begin!;
    final b = end!;
    double mix(double x, double y) => x + (y - x) * t;
    return _Filter(
      mix(a.saturation, b.saturation),
      mix(a.brightness, b.brightness),
      mix(a.blur, b.blur),
    );
  }
}
