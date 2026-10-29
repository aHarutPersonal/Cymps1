import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'buttons.dart';
import 'icons.dart';
import 'keyframes.dart';
import 'motion_fx.dart';
import 'surfaces.dart';
import 'video.dart';

// `WeekUnlock` from `v3/app.jsx`: the full-screen moment when a new week of
// the plan opens. The caller decides when (once per week and account, see
// the store's week-unlock ledger) and what the buttons lead to.

/// What the user chose on the "Week unlocked" moment.
enum WeekUnlockResult {
  /// "Start week {n}".
  start,

  /// "Later", or the overlay was closed some other way (system back).
  later,
}

/// Shows "Week [week] unlocked" as a full-screen night route that fades in
/// over .5 s, and returns the user's choice.
///
/// [title] is the week's real title, [totalWeeks] the plan's real week
/// count, and [missionsReady] whether the backend reports the week's
/// missions ready: only then does the body say the mentor has prepared
/// them.
///
/// With reduced motion there is no video, the title fades instead of
/// resolving word by word, and nothing loops.
Future<WeekUnlockResult> showWeekUnlock(
  BuildContext context, {
  required int week,
  required String title,
  required int totalWeeks,
  required bool missionsReady,
  bool useRootNavigator = true,
}) async {
  final result = await Navigator.of(context, rootNavigator: useRootNavigator)
      .push<WeekUnlockResult>(
        PageRouteBuilder<WeekUnlockResult>(
          opaque: true,
          // `fade .5s both`; a fade is kept with reduced motion (fades only).
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) =>
              V3WeekUnlockOverlay(
                week: week,
                title: title,
                totalWeeks: totalWeeks,
                missionsReady: missionsReady,
                onResult: (result) => Navigator.of(context).pop(result),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: animation.drive(CurveTween(curve: Curves.ease)),
                child: child,
              ),
        ),
      );
  return result ?? WeekUnlockResult.later;
}

/// The "Week unlocked" page itself (what [showWeekUnlock] pushes). Public
/// so tests and previews can host it directly.
///
/// It runs in three phases: 0 (the video or glow alone), 1 (the pill,
/// kicker, title and body come in) and 2 (the buttons come in and become
/// tappable). With the video playing, phase 1 starts at 1.8 s and phase 2
/// at 2.8 s; without it (it failed, isn't ready by .6 s, or reduced
/// motion), at .6 s and 1.4 s.
class V3WeekUnlockOverlay extends StatefulWidget {
  const V3WeekUnlockOverlay({
    super.key,
    required this.week,
    required this.title,
    required this.totalWeeks,
    required this.missionsReady,
    required this.onResult,
  });

  /// Key on the full-screen night surface.
  static const pageKey = ValueKey<String>('week-unlock-page');

  final int week;
  final String title;
  final int totalWeeks;
  final bool missionsReady;

  /// Called once with the user's choice.
  final ValueChanged<WeekUnlockResult> onResult;

  /// The body copy for [week] (honest about whether the missions are
  /// ready).
  static String bodyFor(int week, {required bool missionsReady}) =>
      missionsReady
      ? 'Week ${week - 1} is complete. Your mentor has prepared the next '
            'missions.'
      : 'Week ${week - 1} is complete. Its missions are being prepared.';

  @override
  State<V3WeekUnlockOverlay> createState() => _V3WeekUnlockOverlayState();
}

// oklch(0.7 0.14 70 / .55) and oklch(0.85 0.12 80), in sRGB.
const Color _weekGlow = Color(0x8CD58D25);
const Color _unlockGold = Color(0xFFF7C56D);
const Color _white = Color(0xFFFFFFFF);

// `linear-gradient(180deg, rgba(14,12,20,.35) 0%, rgba(14,12,20,0) 30%,
// rgba(14,12,20,.35) 55%, rgba(14,12,20,.95) 85%)`.
const LinearGradient _shade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x590E0C14),
    Color(0x000E0C14),
    Color(0x590E0C14),
    Color(0xF20E0C14),
  ],
  stops: [0, 0.3, 0.55, 0.85],
);

const double _buttonsBottom = 44;
const double _buttonsGap = 10;

/// The text block sits 170 pt from the bottom when the buttons sit at 44.
const double _textAboveButtons = 170 - _buttonsBottom;

class _V3WeekUnlockOverlayState extends State<V3WeekUnlockOverlay> {
  int _phase = 0;
  bool _closing = false;
  bool _started = false;

  /// Whether the video timings apply; null until decided.
  bool? _withVideo;
  final List<Timer> _videoTimers = [];
  final List<Timer> _plainTimers = [];
  Timer? _decide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Both timelines are counted from the page opening; the one that
    // applies is kept once it is known whether the video plays.
    _videoTimers.addAll([
      Timer(const Duration(milliseconds: 1800), () => _toPhase(1)),
      Timer(const Duration(milliseconds: 2800), () => _toPhase(2)),
    ]);
    _plainTimers.addAll([
      Timer(const Duration(milliseconds: 600), () => _toPhase(1)),
      Timer(const Duration(milliseconds: 1400), () => _toPhase(2)),
    ]);
    if (!MotionConfig.enabled(context)) {
      _commit(withVideo: false);
    } else {
      // The plain timeline's first step: if the video isn't playing by then,
      // it won't set the pace.
      _decide = Timer(
        const Duration(milliseconds: 600),
        () => _commit(withVideo: false),
      );
    }
  }

  void _commit({required bool withVideo}) {
    if (_withVideo != null) return;
    _withVideo = withVideo;
    _decide?.cancel();
    for (final t in withVideo ? _plainTimers : _videoTimers) {
      t.cancel();
    }
  }

  void _toPhase(int phase) {
    if (!mounted || phase <= _phase) return;
    setState(() => _phase = phase);
  }

  void _onVideo(bool playing) {
    if (playing) _commit(withVideo: true);
  }

  void _finish(WeekUnlockResult result) {
    if (_closing || _phase < 2) return;
    _closing = true;
    widget.onResult(result);
  }

  @override
  void dispose() {
    _decide?.cancel();
    for (final t in [..._videoTimers, ..._plainTimers]) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.week;
    final media = MediaQuery.of(context);
    final bottom = math.max(_buttonsBottom, media.padding.bottom + 16);
    final textBottom = bottom + _textAboveButtons;
    final shown = _phase > 0;
    final buttonsOn = _phase >= 2;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Week $n unlocked',
        child: ColoredBox(
          key: V3WeekUnlockOverlay.pageKey,
          color: AppColors.night,
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: AppTypography.sans(16).copyWith(color: _white),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  V3LoopVideo(
                    asset: AppAssets.videoWeekUnlock,
                    fallback: const V3BreathingGlow(
                      color: _weekGlow,
                      centerY: 0.4,
                      period: Duration(seconds: 4),
                    ),
                    // `kbIn 6s ease-out both`.
                    initialScale: 1.12,
                    scale: 1,
                    scaleDuration: const Duration(seconds: 6),
                    scaleCurve: Curves.easeOut,
                    onReady: _onVideo,
                  ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: shown ? 1 : 0.4,
                      duration: const Duration(seconds: 1),
                      curve: Curves.ease,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(gradient: _shade),
                      ),
                    ),
                  ),
                  const V3Grain(),
                  Positioned(
                    left: 26,
                    right: 26,
                    bottom: textBottom,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Enter(
                          show: shown,
                          duration: const Duration(milliseconds: 700),
                          curve: AppMotion.spring,
                          offset: 10,
                          fromScale: 0.9,
                          child: _Pill(week: n),
                        ),
                        const SizedBox(height: 18),
                        _Enter(
                          show: shown,
                          duration: const Duration(milliseconds: 800),
                          delay: const Duration(milliseconds: 200),
                          child: Text(
                            'Week $n of ${widget.totalWeeks}',
                            textAlign: TextAlign.center,
                            style: AppTypography.sans(
                              13,
                              FontWeight.w500,
                            ).copyWith(color: const Color(0x99FFFFFF)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Semantics(
                          header: true,
                          child: V3BlurWords(
                            text: widget.title,
                            show: shown,
                            delay: const Duration(milliseconds: 250),
                            step: const Duration(milliseconds: 90),
                            textAlign: TextAlign.center,
                            style: AppTypography.display(44).copyWith(
                              color: _white,
                              height: 1.02,
                              shadows: const [
                                Shadow(
                                  color: Color(0x80000000),
                                  offset: Offset(0, 4),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Enter(
                          show: shown,
                          duration: const Duration(milliseconds: 800),
                          delay: const Duration(milliseconds: 700),
                          child: Text(
                            V3WeekUnlockOverlay.bodyFor(
                              n,
                              missionsReady: widget.missionsReady,
                            ),
                            textAlign: TextAlign.center,
                            style: AppTypography.sans(14.5).copyWith(
                              color: const Color(0xC7FFFFFF),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: bottom,
                    child: IgnorePointer(
                      ignoring: !buttonsOn,
                      child: ExcludeSemantics(
                        excluding: !buttonsOn,
                        child: _Enter(
                          show: buttonsOn,
                          duration: const Duration(milliseconds: 700),
                          curve: AppMotion.out,
                          offset: 20,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              V3Button(
                                full: true,
                                iconRight: V3Icons.arrowR,
                                onPressed: () =>
                                    _finish(WeekUnlockResult.start),
                                child: Text('Start week $n'),
                              ),
                              const SizedBox(height: _buttonsGap),
                              V3Button(
                                full: true,
                                kind: V3ButtonKind.glass,
                                onPressed: () =>
                                    _finish(WeekUnlockResult.later),
                                child: const Text('Later'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Week {n} unlocked" pill: 32 pt, frosted `rgba(255,255,255,.12)`
/// with a 10 px backdrop blur, a gold unlock icon and 12.5 pt w600 text.
class _Pill extends StatelessWidget {
  const _Pill({required this.week});

  final int week;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: const Color(0x1FFFFFFF),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const V3Icon(V3Icons.unlock, size: 15, color: _unlockGold),
              const SizedBox(width: 7),
              Text(
                'Week $week unlocked',
                style: AppTypography.sans(
                  12.5,
                  FontWeight.w600,
                ).copyWith(color: _white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A CSS transition to the shown state when [show] turns true: from
/// [offset] pt down, [fromScale] and transparent, over [duration] on
/// [curve] after [delay]. With reduced motion it is the fade alone.
class _Enter extends StatefulWidget {
  const _Enter({
    required this.show,
    required this.child,
    required this.duration,
    this.delay = Duration.zero,
    this.curve = Curves.ease,
    this.offset = 0,
    this.fromScale = 1,
  });

  final bool show;
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final double offset;
  final double fromScale;

  @override
  State<_Enter> createState() => _EnterState();
}

class _EnterState extends State<_Enter> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.show ? 1 : 0,
  );
  Timer? _timer;

  @override
  void didUpdateWidget(_Enter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.show == widget.show) return;
    _timer?.cancel();
    if (widget.show) {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = _controller.value;
        final opacity = Curves.ease.transform(v);
        if (!motion) return Opacity(opacity: opacity, child: child);
        final t = widget.curve.transform(v);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: Transform.scale(
              scale: widget.fromScale + (1 - widget.fromScale) * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
