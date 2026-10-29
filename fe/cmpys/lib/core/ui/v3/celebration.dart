import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'buttons.dart';
import 'feedback.dart';
import 'icons.dart';
import 'keyframes.dart';
import 'motion.dart';
import 'progress.dart';
import 'video.dart';

// `Celebration` from `v3/app.jsx`: the full-screen night moment that follows
// a finished tutorial or a finished day of habits.

/// Which celebration: a finished tutorial (sage glow, trophy) or a finished
/// day of habits (ember glow, flame).
enum CelebrationKind { tutorial, day }

/// What the user chose on the celebration, so the caller decides what opens
/// next (the "Suggested achievement" sheet, say).
enum CelebrationResult {
  /// "Continue", or the overlay was dismissed some other way.
  continued,

  /// "Add to your record".
  addToRecord,
}

/// The copy and numbers for one celebration (the design's `c` object:
/// `{kind, title, sub, stat, statL, achievement?}`).
///
/// Build one with [Celebration.tutorial] or [Celebration.day], which carry
/// the design's wording, or directly for another moment.
@immutable
class Celebration {
  Celebration({
    required this.kind,
    required this.title,
    required this.sub,
    required this.stat,
    required this.statLabel,
    String? achievement,
  }) : achievement = (achievement == null || achievement.trim().isEmpty)
           ? null
           : achievement;

  /// A tutorial was finished. [completed] of [total] are now done and
  /// [nextTitle] is the one that just opened. Once [completed] has reached
  /// [total] there is nothing left to open and the sub line says the
  /// mission's tutorials are done instead. A blank [nextTitle] with tutorials
  /// still to come just drops the title from the sentence. With [nextReady]
  /// false the next tutorial is still being written (one ahead), and the sub
  /// line says it is being prepared. [achievement] is the suggested
  /// achievement text, which turns on "Add to your record".
  factory Celebration.tutorial({
    required int completed,
    required int total,
    required String nextTitle,
    bool nextReady = true,
    String? achievement,
  }) {
    final next = nextTitle.trim();
    final String sub;
    if (completed >= total) {
      sub = 'Both cases accepted. This mission’s tutorials are done.';
    } else if (!nextReady) {
      sub =
          'Both cases accepted. Tutorial ${completed + 1} is being '
          'prepared.';
    } else if (next.isEmpty) {
      sub = 'Both cases accepted. Tutorial ${completed + 1} is now open.';
    } else {
      sub =
          'Both cases accepted. Tutorial ${completed + 1}, $next, is now '
          'open.';
    }
    return Celebration(
      kind: CelebrationKind.tutorial,
      title: 'Tutorial $completed complete',
      sub: sub,
      stat: completed,
      statLabel: 'of $total tutorials',
      achievement: achievement,
    );
  }

  /// Today's habits are all done. [streak] is the streak *before* today, so
  /// the celebration shows [streak] + 1 (the design's `st.streak + 1`).
  factory Celebration.day(int streak) => Celebration(
    kind: CelebrationKind.day,
    title: 'Today’s habits are done.',
    sub: 'Recorded for today. They’ll be waiting again tomorrow.',
    stat: math.max(0, streak) + 1,
    statLabel: 'day streak',
  );

  final CelebrationKind kind;
  final String title;
  final String sub;

  /// The big count-up number.
  final int stat;

  /// The caption under [stat], e.g. "day streak". Shown uppercase.
  final String statLabel;

  /// The achievement the user may add to their record; null when there is
  /// none (blank text counts as none).
  final String? achievement;

  /// Whether the overlay offers "Add to your record".
  bool get offersAchievement => achievement != null;
}

/// Shows [celebration] as a full-screen night route: it fades in over .4 s,
/// with confetti, a breathing glow and a count-up, and returns the user's
/// choice. Closing it any other way (the system back gesture) counts as
/// [CelebrationResult.continued].
///
/// Behind the content a looping video plays for the kind (a finished
/// tutorial or a finished day of habits), restarting from its first frame
/// each time; until it plays, or if it can't, the celebration looks exactly
/// as it does without one.
///
/// With reduced motion there is no video, no confetti, no breathing glow and
/// no halo, and the stat shows its final value.
Future<CelebrationResult> showCelebration(
  BuildContext context,
  Celebration celebration, {
  bool useRootNavigator = true,
}) async {
  final reduced = !MotionConfig.enabled(context);
  final result = await Navigator.of(context, rootNavigator: useRootNavigator)
      .push<CelebrationResult>(
        PageRouteBuilder<CelebrationResult>(
          opaque: true,
          // `transition: opacity .4s` (CSS `ease`); the design unmounts
          // instantly, a short fade out is kinder.
          transitionDuration: reduced
              ? Duration.zero
              : const Duration(milliseconds: 400),
          reverseTransitionDuration: reduced
              ? Duration.zero
              : const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) =>
              CelebrationOverlay(
                celebration: celebration,
                onResult: (result) => Navigator.of(context).pop(result),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: animation.drive(CurveTween(curve: Curves.ease)),
                child: child,
              ),
        ),
      );
  return result ?? CelebrationResult.continued;
}

/// The celebration page itself (what [showCelebration] pushes). Public so
/// tests and previews can host it directly.
class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.celebration,
    required this.onResult,
  });

  /// Key on the full-screen night surface.
  static const pageKey = ValueKey<String>('celebration-page');

  /// Key on the breathing radial glow.
  static const glowKey = ValueKey<String>('celebration-glow');

  /// Key on the pulsing halo ring (absent with reduced motion).
  static const haloKey = ValueKey<String>('celebration-halo');

  /// Key on the vignette laid over the video (present only while it plays).
  static const vignetteKey = ValueKey<String>('celebration-vignette');

  /// The background video for [kind].
  static String videoFor(CelebrationKind kind) => switch (kind) {
    CelebrationKind.tutorial => AppAssets.videoCelebrateTutorial,
    CelebrationKind.day => AppAssets.videoCelebrateHabits,
  };

  final Celebration celebration;

  /// Called once with the user's choice.
  final ValueChanged<CelebrationResult> onResult;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

// The design's absolute offsets: buttons sit 44 pt from the bottom, 24 pt
// from the sides, 10 pt apart; the page pads 30 pt around the content.
const double _buttonsBottom = 44;
const double _buttonsGap = 10;
const double _contentGap = 12;

const Color _white = Color(0xFFFFFFFF);

class _CelebrationOverlayState extends State<CelebrationOverlay> {
  bool _closing = false;

  void _finish(CelebrationResult result) {
    // A second tap while the page fades out must not pop the page below.
    if (_closing) return;
    _closing = true;
    widget.onResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.celebration;
    final motion = MotionConfig.enabled(context);
    final tutorial = c.kind == CelebrationKind.tutorial;
    final media = MediaQuery.of(context);
    final bottom = math.max(_buttonsBottom, media.padding.bottom + 16);
    final buttonCount = c.offersAchievement ? 2 : 1;
    final buttonsHeight =
        V3Size.lg.height * buttonCount + _buttonsGap * (buttonCount - 1);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: c.title,
        child: ColoredBox(
          key: CelebrationOverlay.pageKey,
          color: AppColors.night,
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: AppTypography.sans(16).copyWith(color: _white),
              child: IconTheme(
                data: const IconThemeData(color: _white),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    V3BreathingGlow(
                      key: CelebrationOverlay.glowKey,
                      color: tutorial ? _sageGlow : _emberGlow,
                    ),
                    Positioned.fill(child: _CelebrationVideo(kind: c.kind)),
                    if (motion) const Positioned.fill(child: V3Confetti()),
                    CustomSingleChildLayout(
                      delegate: _ContentLayout(
                        top: media.padding.top,
                        bottom: bottom + buttonsHeight + _contentGap,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          child: _Content(celebration: c),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: bottom,
                      child: V3Rise(
                        delay: const Duration(milliseconds: 850),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: c.offersAchievement
                              ? [
                                  V3Button(
                                    full: true,
                                    icon: V3Icons.trophy,
                                    onPressed: () =>
                                        _finish(CelebrationResult.addToRecord),
                                    child: const Text('Add to your record'),
                                  ),
                                  const SizedBox(height: _buttonsGap),
                                  V3Button(
                                    full: true,
                                    kind: V3ButtonKind.glass,
                                    onPressed: () =>
                                        _finish(CelebrationResult.continued),
                                    child: const Text('Continue'),
                                  ),
                                ]
                              : [
                                  V3Button(
                                    full: true,
                                    kind: V3ButtonKind.light,
                                    onPressed: () =>
                                        _finish(CelebrationResult.continued),
                                    child: const Text('Continue'),
                                  ),
                                ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centres the content in the full height, as the design's flex column does,
/// but never lets it run under the buttons or the status bar: on a short
/// screen it moves up and, past that, scrolls.
class _ContentLayout extends SingleChildLayoutDelegate {
  const _ContentLayout({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: constraints.maxWidth,
        maxHeight: math.max(0, constraints.maxHeight - top - bottom),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final centred = (size.height - childSize.height) / 2;
    final y = math.max(
      top,
      math.min(centred, size.height - bottom - childSize.height),
    );
    return Offset((size.width - childSize.width) / 2, y);
  }

  @override
  bool shouldRelayout(_ContentLayout oldDelegate) =>
      oldDelegate.top != top || oldDelegate.bottom != bottom;
}

// ─────────────────────────────────────────────────────────────────────────────
// Content
// ─────────────────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  const _Content({required this.celebration});

  final Celebration celebration;

  @override
  Widget build(BuildContext context) {
    final c = celebration;
    final tutorial = c.kind == CelebrationKind.tutorial;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // pop .7s --spring .1s both
        _DelayedPop(
          delay: const Duration(milliseconds: 100),
          size: _markSize,
          child: _Mark(tutorial: tutorial),
        ),
        const SizedBox(height: 26),
        // rise .7s --out .3s both; the count starts at .4 s over .9 s.
        V3Rise(
          delay: const Duration(milliseconds: 300),
          duration: const Duration(milliseconds: 700),
          child: V3CountUp(
            to: c.stat,
            duration: const Duration(milliseconds: 900),
            delay: const Duration(milliseconds: 400),
            style: AppTypography.display(84).copyWith(color: _white, height: 1),
          ),
        ),
        const SizedBox(height: 4),
        // fade .6s .5s both
        V3Rise(
          delay: const Duration(milliseconds: 500),
          duration: const Duration(milliseconds: 600),
          offset: 0,
          child: Text(
            c.statLabel.toUpperCase(),
            semanticsLabel: c.statLabel,
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              13,
              FontWeight.w600,
            ).copyWith(letterSpacing: 13 * 0.14, color: AppColors.nink3),
          ),
        ),
        const SizedBox(height: 24),
        V3Rise(
          delay: const Duration(milliseconds: 550),
          duration: const Duration(milliseconds: 700),
          child: Semantics(
            header: true,
            child: Text(
              c.title,
              textAlign: TextAlign.center,
              style: AppTypography.display(36).copyWith(color: _white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        V3Rise(
          delay: const Duration(milliseconds: 650),
          duration: const Duration(milliseconds: 700),
          child: Text(
            c.sub,
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              15,
            ).copyWith(color: AppColors.nink2, height: 1.5),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glow
// ─────────────────────────────────────────────────────────────────────────────

// oklch(0.5 0.12 155 / .6) and oklch(0.55 0.16 42 / .55), in sRGB.
const Color _sageGlow = Color(0x990B7643);
const Color _emberGlow = Color(0x8CBA480D);

/// The kind's looping video over the glow: `opacity .9` once it plays,
/// zooming 1.12 → 1 (`transition: opacity 1.2s var(--out), transform 4s
/// var(--out)`), with the vignette fading in over it. A new page each time,
/// so the video starts from its first frame. Until it plays (or with reduced
/// motion, or if it can't) nothing is drawn here.
class _CelebrationVideo extends StatefulWidget {
  const _CelebrationVideo({required this.kind});

  final CelebrationKind kind;

  @override
  State<_CelebrationVideo> createState() => _CelebrationVideoState();
}

class _CelebrationVideoState extends State<_CelebrationVideo> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          V3LoopVideo(
            asset: CelebrationOverlay.videoFor(widget.kind),
            // Today's celebration (the glow beneath) is the fallback.
            fallback: const SizedBox.expand(),
            opacity: 0.9,
            scale: _playing ? 1 : 1.12,
            scaleDuration: const Duration(seconds: 4),
            scaleCurve: AppMotion.out,
            onReady: (ok) {
              if (mounted && ok != _playing) setState(() => _playing = ok);
            },
          ),
          if (_playing)
            // `transition: opacity 1.2s`.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.ease,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: const CustomPaint(
                key: CelebrationOverlay.vignetteKey,
                painter: _VignettePainter(),
              ),
            ),
        ],
      ),
    );
  }
}

/// `radial-gradient(120% 80% at 50% 40%, rgba(14,12,20,.15) 0%,
/// rgba(14,12,20,.55) 60%, rgba(14,12,20,.92) 100%)`: an ellipse 1.2× the
/// width by .8× the height around (50%, 40%).
class _VignettePainter extends CustomPainter {
  const _VignettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rx = size.width * 1.2;
    final ry = size.height * 0.8;
    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.4);
    canvas.scale(1, ry / rx);
    final circle = Rect.fromCircle(center: Offset.zero, radius: rx);
    canvas.drawRect(
      // Large enough to cover the box after the vertical squash.
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 2,
        height: size.height * 2 * rx / ry,
      ),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x260E0C14), Color(0x8C0E0C14), Color(0xEB0E0C14)],
          stops: [0, 0.6, 1],
        ).createShader(circle),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VignettePainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Icon mark
// ─────────────────────────────────────────────────────────────────────────────

const double _markSize = 96;

/// Starts [child]'s `pop` after [delay] (`pop … .1s both`): until then it
/// holds the layout space and shows nothing. With reduced motion the child
/// shows at once.
class _DelayedPop extends StatefulWidget {
  const _DelayedPop({
    required this.delay,
    required this.size,
    required this.child,
  });

  final Duration delay;
  final double size;
  final Widget child;

  @override
  State<_DelayedPop> createState() => _DelayedPopState();
}

class _DelayedPopState extends State<_DelayedPop> {
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _started = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return widget.child;
    if (!_started) return SizedBox.square(dimension: widget.size);
    return V3Pop(
      duration: const Duration(milliseconds: 700),
      child: widget.child,
    );
  }
}

/// The 96 pt accent disc with its white icon and a repeating halo ring.
class _Mark extends StatelessWidget {
  const _Mark({required this.tutorial});

  final bool tutorial;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _markSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tutorial ? AppColors.sage : AppColors.ember,
            ),
            child: Center(
              child: V3Icon(
                tutorial ? V3Icons.trophy : V3Icons.flame,
                size: 42,
                color: _white,
                strokeWidth: 2,
              ),
            ),
          ),
          // `halo 1.6s --out .4s infinite`, counted from the page opening;
          // the disc has already waited .1 s when this mounts, so .3 s.
          if (MotionConfig.enabled(context))
            const Positioned.fill(
              child: V3HaloRing(
                key: CelebrationOverlay.haloKey,
                delay: Duration(milliseconds: 300),
              ),
            ),
        ],
      ),
    );
  }
}
