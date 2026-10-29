import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../../plan/presentation/book_narration_checkpoint.dart';
import '../controllers/session_controller.dart';

const _splashSeenKey = 'cmpys_has_seen_splash';

@visibleForTesting
const splashFirstVisitMinimum = Duration(milliseconds: 3400);

@visibleForTesting
const splashReturningVisitMinimum = Duration(milliseconds: 600);

@visibleForTesting
Duration splashMinimumForVisit({required bool hasSeenSplash}) =>
    hasSeenSplash ? splashReturningVisitMinimum : splashFirstVisitMinimum;

@visibleForTesting
Duration splashRemainingDelay({
  required bool hasSeenSplash,
  required Duration elapsed,
}) {
  final remaining =
      splashMinimumForVisit(hasSeenSplash: hasSeenSplash) - elapsed;
  return remaining.isNegative ? Duration.zero : remaining;
}

/// Waits for both the minimum brand beat and session bootstrap. The futures are
/// deliberately joined instead of awaited serially, so network/storage work is
/// hidden behind the animation rather than added after it.
@visibleForTesting
Future<void> waitForSplashGate({
  required Future<void> initialization,
  required Duration minimumDelay,
  Future<void> Function(Duration) delay = Future<void>.delayed,
}) async {
  await Future.wait<void>([initialization, delay(minimumDelay)]);
}

/// Reads the current account's active book and consumes the prior-playing bit
/// before the caller navigates. If the one-shot write fails, the book can still
/// be restored, but autoplay is conservatively disabled.
@visibleForTesting
Future<ActiveBookNarrationResume?> consumeActiveBookNarrationResume({
  required ActiveBookNarrationResumeStore store,
  required String ownerId,
}) async {
  final resume = await store.read(ownerId);
  if (resume == null || !resume.wasPlaying) return resume;

  try {
    await store.write(resume.copyWith(wasPlaying: false));
    return resume;
  } catch (error) {
    debugPrint('🚀 narration autoplay consumption error: $error');
    return resume.copyWith(wasPlaying: false);
  }
}

/// Chooses the ready-session destination without coupling route policy to the
/// splash animation. Browser restores are always manual because cold-start
/// autoplay is commonly blocked and should never surprise the listener.
@visibleForTesting
String splashRouteForReadySession({
  required ActiveBookNarrationResume? resume,
  required bool isWeb,
}) {
  if (resume == null) return AppRoutes.home;
  return AppRoutes.bookReaderLocation(
    branchIndex: resume.branchIndex,
    resourceId: resume.resourceId,
    fallbackTitle: resume.fallbackTitle,
    autoplayOnRestore: resume.wasPlaying && !isWeb,
  );
}

/// CMPYS splash (`v3/onboard.jsx` Splash): the library video behind the
/// wordmark, the tagline and the entry buttons revealing at 1.7 s.
///
/// While the video plays (`SPLASH_VIDEO`: faded in from a blur over 1.6 s,
/// Ken Burns 1.08 → 1 over 14 s) the wordmark sits at the top, a shade and
/// grain cover the video and a row of mentor avatars introduces the copy.
/// Until it plays, if it can't (6 s), or with reduced motion, the splash is
/// the night scene with five grey mentor portraits orbiting the wordmark.
///
/// The session still resolves in the background while this plays. A restored
/// session routes on as before (home, onboarding or a narration restore) once
/// the minimum brand beat has passed; a visitor who is signed out stays here
/// and chooses "Get started" or "I already have an account", which open the
/// auth screen in that mode. A tap on the scene still skips ahead for a
/// session that is already restorable.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Reveal wrappers, so tests can read their opacity.
  @visibleForTesting
  static const taglineKey = ValueKey<String>('splash-tagline');
  @visibleForTesting
  static const introKey = ValueKey<String>('splash-intro');
  @visibleForTesting
  static const buttonsKey = ValueKey<String>('splash-buttons');

  /// The rotating mentor group.
  @visibleForTesting
  static const orbitKey = ValueKey<String>('splash-orbit');

  /// The "cmpys" wordmark (one letter per glyph, labelled "cmpys").
  @visibleForTesting
  static const wordmarkKey = ValueKey<String>('splash-wordmark');

  /// The background video.
  @visibleForTesting
  static const videoKey = ValueKey<String>('splash-video');

  /// The "Learn with history’s builders" avatar row (only while the video
  /// plays).
  @visibleForTesting
  static const avatarRowKey = ValueKey<String>('splash-avatar-row');

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

/// The five mentors of the design's `MENTORS`, with the bundled portraits.
const _mentors = <({String slug, String initials, Color tint})>[
  (slug: 'wb', initials: 'WB', tint: Color(0xFFDCD6C8)),
  (slug: 'mc', initials: 'MC', tint: Color(0xFFE2D5CB)),
  (slug: 'sj', initials: 'SJ', tint: Color(0xFFD9D9D9)),
  (slug: 'jdr', initials: 'JR', tint: Color(0xFFD4CDC2)),
  (slug: 'em', initials: 'EM', tint: Color(0xFFD1D3D8)),
];

// The design's literal oklch values, converted to sRGB once: the glow's
// `oklch(0.45 0.14 285 / .55)` and `oklch(0.4 0.12 42 / .18)`, the tagline
// accent `oklch(0.82 0.1 42)` and the wordmark sheen `oklch(0.88 0.1 60)`.
const _glowIris = Color(0x8C50459E);
const _glowEmber = Color(0x2E7A2A01);
const _taglineAccent = Color(0xFFFCAF91);
const _sheenGold = Color(0xFFFFC894);

/// Over the playing video: `linear-gradient(180deg, rgba(14,12,20,.55) 0%,
/// rgba(14,12,20,.05) 22%, rgba(14,12,20,0) 42%, rgba(14,12,20,.55) 62%,
/// rgba(14,12,20,.96) 84%, var(--night) 100%)`.
const _videoShade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x8C0E0C14),
    Color(0x0D0E0C14),
    Color(0x000E0C14),
    Color(0x8C0E0C14),
    Color(0xF50E0C14),
    AppColors.night,
  ],
  stops: [0, 0.22, 0.42, 0.62, 0.84, 1],
);

/// Where the wordmark sits while the video plays (the design's `top: 112`).
const double _wordmarkTopWithVideo = 112;

/// About how tall the wordmark block is (the 62 pt word, the gap and the
/// 11 pt line under it), so a short phone can lift it clear of the copy.
const double _wordmarkBlockHeight = 100;

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  /// When the tagline and the buttons reveal (the design's `ready`).
  static const _revealAfter = Duration(milliseconds: 1700);

  /// When the wordmark's sheen starts sweeping (letter 0; each next letter
  /// 60 ms later).
  static const _sheenAfter = Duration(milliseconds: 1200);

  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  late final Animation<double> _counterTurns = ReverseAnimation(_orbit);
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  );

  /// `logoSheen 4.5s ease-in-out infinite`, one cycle for every letter
  /// (each offset by 60 ms).
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );
  Timer? _sheenTimer;
  bool _sheenDue = false;

  /// The background video is playing: the orbit scene gives way to it.
  bool _videoPlaying = false;
  Timer? _orbitStopTimer;

  late Future<void> _initFuture;
  bool _startupFailed = false;
  late final Stopwatch _visitClock;
  bool _navigated = false;
  bool _revealed = false;
  bool _openingAuth = false;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    _visitClock = Stopwatch()..start();
    _revealTimer = Timer(_revealAfter, () {
      if (mounted) setState(() => _revealed = true);
    });
    _sheenTimer = Timer(_sheenAfter, () {
      _sheenDue = true;
      if (mounted) _syncLoops();
    });

    // Resolve the session in the background while the splash plays.
    _initFuture = ref.read(sessionControllerProvider.notifier).initialize();
    unawaited(_autoAdvanceWhenReady());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoops();
  }

  /// Reduced motion holds the scene still: the orbit stays at its start, the
  /// glow at rest and the wordmark plain white. Once the video has taken
  /// over, the hidden orbit and glow stop too.
  void _syncLoops() {
    final motion = MotionConfig.enabled(context);
    if (motion && !_videoPlaying) {
      _orbitStopTimer?.cancel();
      _orbitStopTimer = null;
      if (!_orbit.isAnimating) _orbit.repeat();
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
    } else if (!motion) {
      _orbit.value = 0;
      _breathe.value = 0;
    }
    if (motion && _sheenDue) {
      if (!_sheen.isAnimating) _sheen.repeat();
    } else {
      _sheen.value = 0;
    }
  }

  void _onVideoReady(bool playing) {
    if (!mounted || playing == _videoPlaying) return;
    setState(() => _videoPlaying = playing);
    if (playing) {
      // The orbit fades out over 1.2 s; stop its loops once it is gone.
      _orbitStopTimer?.cancel();
      _orbitStopTimer = Timer(const Duration(milliseconds: 1300), () {
        if (!mounted || !_videoPlaying) return;
        _orbit.stop();
        _breathe.stop();
      });
    } else {
      _syncLoops();
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _sheenTimer?.cancel();
    _orbitStopTimer?.cancel();
    _visitClock.stop();
    _orbit.dispose();
    _breathe.dispose();
    _sheen.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_navigated) return;
    _navigated = true;

    try {
      await _initFuture;
    } catch (e) {
      debugPrint('🚀 splash bootstrap error: $e');
    }
    if (!mounted) return;

    final session = ref.read(sessionControllerProvider);
    if (session is SessionError || session is SessionInitializing) {
      setState(() => _startupFailed = true);
      _navigated = false;
      return;
    }
    if (session is! SessionReady && session is! SessionNeedsOnboarding) {
      // Signed out: the splash stays and offers the sign-in choices.
      _navigated = false;
      return;
    }
    var route = session is SessionReady
        ? AppRoutes.home
        : AppRoutes.cmpysOnboarding;
    if (session case SessionReady(:final user)) {
      try {
        final resume = await consumeActiveBookNarrationResume(
          store: const SharedPreferencesActiveBookNarrationResumeStore(),
          ownerId: user.id,
        );
        route = splashRouteForReadySession(resume: resume, isWeb: kIsWeb);
      } catch (error) {
        // A damaged/unavailable preference must not block a valid session.
        debugPrint('🚀 narration resume preference error: $error');
      }
    }
    if (!mounted) return;
    context.go(route);
  }

  Future<void> _autoAdvanceWhenReady() async {
    // Treat a failed preference read conservatively as a first visit. Session
    // bootstrap was already started above and continues in parallel.
    var hasSeenSplash = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      hasSeenSplash = prefs.getBool(_splashSeenKey) ?? false;
      if (!hasSeenSplash) {
        unawaited(prefs.setBool(_splashSeenKey, true));
      }
    } catch (e) {
      debugPrint('🚀 splash preference error: $e');
    }

    final remaining = splashRemainingDelay(
      hasSeenSplash: hasSeenSplash,
      elapsed: _visitClock.elapsed,
    );
    try {
      await waitForSplashGate(
        initialization: _initFuture,
        minimumDelay: remaining,
      );
    } catch (e) {
      // [_advance] retains the existing fallback behavior when session
      // initialization fails; this catch prevents an unhandled background error.
      debugPrint('🚀 splash bootstrap error: $e');
    }
    if (mounted) await _advance();
  }

  /// Opens the auth screen in [location]'s mode, once per tap.
  Future<void> _openAuth(String location) async {
    if (_openingAuth) return;
    _openingAuth = true;
    try {
      await context.push<void>(location);
    } finally {
      _openingAuth = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_startupFailed) return _buildStartupFailure(context);

    final signedOut =
        ref.watch(sessionControllerProvider) is SessionUnauthenticated;
    final safe = MediaQuery.viewPaddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _advance,
          child: DefaultTextStyle(
            style: AppTypography.sans(16).copyWith(color: Colors.white),
            child: LayoutBuilder(
              builder: (context, screen) => ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildVideo()),
                    Positioned.fill(
                      child: _buildContent(screen, safe, signedOut),
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

  /// The library video (`SPLASH_VIDEO`, `vidIn 1.6s` + `kb 14s`) with its
  /// shade and grain, which show only while it plays. Before that, and if it
  /// can't play, this is just the night ground.
  Widget _buildVideo() {
    final playing = _videoPlaying;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          V3LoopVideo(
            key: SplashScreen.videoKey,
            asset: AppAssets.videoSplash,
            fallback: const SizedBox.expand(),
            // vidIn: from opacity 0, blur(8px) brightness(.6) to clear.
            opacityDuration: const Duration(milliseconds: 1600),
            opacityCurve: AppMotion.out,
            blur: playing ? 0 : 8,
            brightness: playing ? 1 : 0.6,
            filterDuration: const Duration(milliseconds: 1600),
            filterCurve: AppMotion.out,
            // kb: scale 1.08 → 1 over 14 s, ease-out.
            initialScale: 1.08,
            scale: 1,
            scaleDuration: const Duration(seconds: 14),
            scaleCurve: Curves.easeOut,
            onReady: _onVideoReady,
          ),
          AnimatedOpacity(
            opacity: playing ? 1 : 0,
            duration: const Duration(milliseconds: 1200),
            child: const Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(decoration: BoxDecoration(gradient: _videoShade)),
                V3Grain(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BoxConstraints screen, EdgeInsets safe, bool signedOut) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, zone) => _buildScene(zone, safe.top),
          ),
        ),
        // The copy takes its natural height, but never more than
        // 70% of the screen: at large text sizes or on a very short
        // phone it scrolls instead of pushing the scene away.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screen.maxHeight * 0.7),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              math.max(46, safe.bottom + 12),
            ),
            child: _buildCopyAndButtons(buttonsReady: signedOut),
          ),
        ),
      ],
    );
  }

  /// Glow, rings, orbit and wordmark, centred at the design's 330/506 of the
  /// space above the copy (so it matches the 844 pt frame and shrinks on
  /// shorter phones). While the video plays the glow, rings and orbit fade
  /// away and the wordmark moves up to the top (`top 1.2s var(--io)`).
  Widget _buildScene(BoxConstraints zone, double topInset) {
    final cx = zone.maxWidth / 2;
    final cy = zone.maxHeight * 0.652;
    // Design radius 132; keep the portraits clear of the status bar and the
    // copy below on a short screen.
    final fit = math.min(cy - topInset - 32, zone.maxHeight - cy - 24);
    final radius = math.min(132.0, math.max(56.0, fit));
    final k = radius / 132;
    final glow = 520.0 * math.max(k, 0.7);
    final outer = (radius + 60.0 * k) * 2;
    final motion = MotionConfig.enabled(context);
    // The design's top 112 over the video; on a short phone, as high as it
    // takes to stay clear of the copy below (but under the status bar).
    final videoTop = math.min(
      _wordmarkTopWithVideo,
      math.max(topInset + 8, zone.maxHeight - _wordmarkBlockHeight),
    );

    // Not clipped here: the glow and rings run on under the copy, as on the
    // design's full-screen canvas (the screen clips them).
    final orbitScene = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: cx - glow / 2,
          top: cy - glow / 2,
          width: glow,
          height: glow,
          child: ExcludeSemantics(child: _Glow(animation: _breathe)),
        ),
        Positioned(
          left: cx - radius,
          top: cy - radius,
          width: radius * 2,
          height: radius * 2,
          child: const ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: cx - outer / 2,
          top: cy - outer / 2,
          width: outer,
          height: outer,
          child: const ExcludeSemantics(
            child: CustomPaint(
              painter: _DashedCirclePainter(color: Color(0x0FFFFFFF)),
            ),
          ),
        ),
        Positioned(
          left: cx - (radius + 40),
          top: cy - (radius + 40),
          child: ExcludeSemantics(
            child: _Orbit(
              key: SplashScreen.orbitKey,
              turns: _orbit,
              counterTurns: _counterTurns,
              radius: radius,
            ),
          ),
        ),
      ],
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _videoPlaying,
            child: AnimatedOpacity(
              opacity: _videoPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 1200),
              child: orbitScene,
            ),
          ),
        ),
        AnimatedPositioned(
          left: 0,
          right: 0,
          top: _videoPlaying ? videoTop : cy - 34,
          duration: motion ? const Duration(milliseconds: 1200) : Duration.zero,
          curve: AppMotion.io,
          child: Column(
            children: [
              _Wordmark(key: SplashScreen.wordmarkKey, sheen: _sheen),
              const SizedBox(height: 4),
              V3Rise(
                delay: const Duration(milliseconds: 600),
                duration: const Duration(seconds: 1),
                offset: 0,
                child: Text(
                  'COMPARE YOUR SUCCESS',
                  textAlign: TextAlign.center,
                  style: AppTypography.sans(11).copyWith(
                    color: const Color(0xBFFFFFFF),
                    letterSpacing: 11 * 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCopyAndButtons({required bool buttonsReady}) {
    final tagline = AppTypography.display(34).copyWith(
      color: Colors.white,
      height: 1.08,
      shadows: const [
        Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 20),
      ],
    );
    final glass = V3Button(
      full: true,
      kind: V3ButtonKind.glass,
      onPressed: () => _openAuth(AppRoutes.authSignIn),
      child: const Text('I already have an account'),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_videoPlaying)
          _Reveal(
            key: SplashScreen.avatarRowKey,
            show: _revealed,
            offset: 10,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: _BuildersRow(),
            ),
          ),
        // `BlurWords`: each word resolves from a blur once the copy is
        // ready; the second line in italic ember 380 ms behind.
        KeyedSubtree(
          key: SplashScreen.taglineKey,
          child: ExcludeSemantics(
            excluding: !_revealed,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  V3BlurWords(
                    text: 'Learn from someone you admire.',
                    show: _revealed,
                    style: tagline,
                    textAlign: TextAlign.center,
                  ),
                  V3BlurWords(
                    text: 'Measure yourself honestly.',
                    show: _revealed,
                    delay: const Duration(milliseconds: 380),
                    style: AppTypography.displayItalic(34).copyWith(
                      color: _taglineAccent,
                      height: 1.08,
                      shadows: tagline.shadows,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        _Reveal(
          key: SplashScreen.introKey,
          show: _revealed,
          delay: const Duration(milliseconds: 200),
          offset: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 26),
            child: Text(
              'A personal plan of short tutorials and real practice, shaped by '
              'a mentor’s documented methods.',
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                14,
              ).copyWith(color: AppColors.nink2, height: 1.5),
            ),
          ),
        ),
        _Reveal(
          key: SplashScreen.buttonsKey,
          show: _revealed && buttonsReady,
          delay: const Duration(milliseconds: 300),
          offset: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              V3Button(
                full: true,
                iconRight: V3Icons.arrowR,
                onPressed: () => _openAuth(AppRoutes.authSignUp),
                child: const Text('Get started'),
              ),
              const SizedBox(height: 10),
              // Over the video the glass button frosts what is behind it
              // (`backdrop-filter: blur(12px)`).
              if (_videoPlaying)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: glass,
                  ),
                )
              else
                glass,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStartupFailure(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DefaultTextStyle(
              style: AppTypography.sans(15).copyWith(color: AppColors.nink2),
              textAlign: TextAlign.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const V3Icon(V3Icons.alert, size: 36, color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    'Could not restore your session',
                    textAlign: TextAlign.center,
                    style: AppTypography.display(
                      30,
                    ).copyWith(color: Colors.white, height: 1.1),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your saved work is safe. Check your connection and try again.',
                  ),
                  const SizedBox(height: 24),
                  V3Button(
                    kind: V3ButtonKind.light,
                    onPressed: () {
                      setState(() => _startupFailed = false);
                      _initFuture = ref
                          .read(sessionControllerProvider.notifier)
                          .initialize();
                      unawaited(_advance());
                    },
                    child: const Text('Try again'),
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

/// `transition: all .8s var(--out)` reveal: hidden (and inert) until [show],
/// then fades in while rising by [offset] after [delay].
class _Reveal extends StatelessWidget {
  const _Reveal({
    super.key,
    required this.show,
    this.delay = Duration.zero,
    this.offset = 14,
    required this.child,
  });

  final bool show;
  final Duration delay;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (show) {
      return V3Rise(
        delay: delay,
        duration: const Duration(milliseconds: 800),
        offset: offset,
        child: child,
      );
    }
    return Opacity(
      opacity: 0,
      // Not tappable, not announced and not reachable with a keyboard.
      child: IgnorePointer(
        child: ExcludeSemantics(child: ExcludeFocus(child: child)),
      ),
    );
  }
}

/// The breathing glow: `breathe 7s ease-in-out infinite` (scale 1 → 1.08,
/// opacity .55 → .9 and back) on the design's radial gradient. CSS sizes that
/// `circle` to the farthest corner: 367.7 px on the 520 px box (260·√2).
/// Flutter's `RadialGradient.radius` is a fraction of the box's *shortest side*
/// (520), so the same circle is 367.7 / 520 = √2 / 2 = 0.7071.
class _Glow extends StatelessWidget {
  const _Glow({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(animation.value);
          return Opacity(
            opacity: 0.55 + 0.35 * t,
            child: Transform.scale(scale: 1 + 0.08 * t, child: child),
          );
        },
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              radius: 0.7071,
              colors: [_glowIris, _glowEmber, Color(0x00000000)],
              stops: [0, 0.45, 0.7],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1 px dashed circle (`border: 1px dashed`), which Flutter lacks.
class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 - 0.5;
    final circumference = 2 * math.pi * radius;
    const dash = 3.0;
    final count = (circumference / (dash * 2)).floor();
    final step = 2 * math.pi / count;
    final sweep = step / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The rotating mentor group: [turns] spins the whole ring once per 60 s and
/// each portrait spins the opposite way ([counterTurns]) so faces stay
/// upright. The first portrait is 74 pt and starts at twelve o'clock; the
/// others are 54 pt. Each pops in 140 ms after the one before it.
class _Orbit extends StatelessWidget {
  const _Orbit({
    super.key,
    required this.turns,
    required this.counterTurns,
    required this.radius,
  });

  final Animation<double> turns;
  final Animation<double> counterTurns;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final box = 2 * (radius + 40);
    return SizedBox.square(
      dimension: box,
      child: RotationTransition(
        turns: turns,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < _mentors.length; i++) _portrait(i, box / 2),
          ],
        ),
      ),
    );
  }

  Widget _portrait(int i, double center) {
    final mentor = _mentors[i];
    final angle = (i / _mentors.length) * 2 * math.pi - math.pi / 2;
    final size = i == 0 ? 74.0 : 54.0;
    return Positioned(
      left: center + math.cos(angle) * radius - size / 2,
      top: center + math.sin(angle) * radius - size / 2,
      width: size,
      height: size,
      child: RotationTransition(
        turns: counterTurns,
        child: _PopIn(
          delay: Duration(milliseconds: 300 + i * 140),
          // Rasterised once, so the 60 s spin only moves a cached layer.
          child: RepaintBoundary(
            child: Opacity(
              opacity: i == 0 ? 1 : 0.8,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: V3Avatar(
                  image: AssetImage('assets/images/mentors/${mentor.slug}.png'),
                  initials: mentor.initials,
                  tint: mentor.tint,
                  size: size,
                  gray: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plays `pop .8s` after [delay] (`animation-delay`, hidden until then).
class _PopIn extends StatefulWidget {
  const _PopIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
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
    if (!_shown) return const SizedBox.shrink();
    return V3Pop(
      duration: const Duration(milliseconds: 800),
      child: widget.child,
    );
  }
}

/// "cmpys" in display 62, one glyph per letter so each can rise and catch
/// the sheen on its own. Screen readers hear the word once.
///
/// Each letter rises (`rise .9s var(--spring)`, from 150 ms, 70 ms apart),
/// then a warm sheen sweeps across it on [sheen] (`logoSheen 4.5s
/// ease-in-out infinite`, 60 ms apart). With reduced motion the word is
/// plain white and still.
class _Wordmark extends StatelessWidget {
  const _Wordmark({super.key, required this.sheen});

  static const _word = 'cmpys';

  final Animation<double> sheen;

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final style = AppTypography.display(
      62,
    ).copyWith(color: Colors.white, letterSpacing: 62 * 0.02);
    return Semantics(
      label: _word,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (var i = 0; i < _word.length; i++)
            _LetterRise(
              delay: Duration(milliseconds: 150 + i * 70),
              child: _SheenLetter(
                letter: _word[i],
                style: style,
                // 60 ms per letter, as a share of the 4.5 s cycle.
                lag: i * 60 / 4500,
                sheen: motion ? sheen : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// One wordmark letter with its soft shadow (`0 4px 30px rgba(0,0,0,.45)`)
/// and, when [sheen] runs, the sweep: CSS paints the letter with
/// `linear-gradient(100deg, #fff 40%, oklch(0.88 0.1 60) 50%, #fff 60%)`
/// sized 300% of the letter and slides it from `background-position 150%`
/// to `-50%`, so the warm band crosses the letter once per cycle.
class _SheenLetter extends StatelessWidget {
  const _SheenLetter({
    required this.letter,
    required this.style,
    required this.lag,
    required this.sheen,
  });

  final String letter;
  final TextStyle style;
  final double lag;
  final Animation<double>? sheen;

  static const _shadow = Shadow(
    color: Color(0x73000000),
    offset: Offset(0, 4),
    blurRadius: 30,
  );

  // CSS 100deg: towards the right and slightly down.
  static final double _dirX = math.sin(100 * math.pi / 180);
  static final double _dirY = -math.cos(100 * math.pi / 180);

  /// The sweep's shader for a letter of [bounds] at cycle [phase] (0–1).
  static Shader _shader(Rect bounds, double phase) {
    final w = bounds.width;
    final h = bounds.height;
    final eased = Curves.easeInOut.transform(phase);
    final position = 1.5 - 2 * eased; // background-position 150% → -50%
    // The 300%-wide gradient box sits at (letter − box) × position.
    final box = Rect.fromLTWH(
      bounds.left - 2 * w * position,
      bounds.top,
      3 * w,
      h,
    );
    final length = (box.width * _dirX).abs() + (box.height * _dirY).abs();
    final ax = _dirX * length / box.width;
    final ay = h == 0 ? 0.0 : _dirY * length / box.height;
    return LinearGradient(
      begin: Alignment(-ax, -ay),
      end: Alignment(ax, ay),
      colors: const [
        Colors.white,
        Colors.white,
        _sheenGold,
        Colors.white,
        Colors.white,
      ],
      stops: const [0, 0.4, 0.5, 0.6, 1],
    ).createShader(box);
  }

  @override
  Widget build(BuildContext context) {
    final glyph = Text(letter, style: style);
    final sheen = this.sheen;
    return Stack(
      children: [
        // The shadow alone, under the (shaded) letter.
        Text(
          letter,
          style: style.copyWith(
            color: const Color(0x00FFFFFF),
            shadows: const [_shadow],
          ),
        ),
        if (sheen == null)
          glyph
        else
          AnimatedBuilder(
            animation: sheen,
            child: glyph,
            builder: (context, child) {
              final phase = (sheen.value - lag) % 1.0;
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => _shader(bounds, phase),
                child: child,
              );
            },
          ),
      ],
    );
  }
}

/// `rise .9s var(--spring)` after [delay] (fill `both`: hidden until then).
/// The spring overshoots, so the letter lifts a touch past its place and
/// settles. With reduced motion the letter is simply there.
class _LetterRise extends StatefulWidget {
  const _LetterRise({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_LetterRise> createState() => _LetterRiseState();
}

class _LetterRiseState extends State<_LetterRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, _controller.forward);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = AppMotion.spring.transform(_controller.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// "Learn with history’s builders" beside the five mentors' grey 34 pt
/// avatars, overlapping by 10 pt with a night ring, each popping in 80 ms
/// after the one before (`pop .6s var(--spring)`). Shown only over the
/// video.
class _BuildersRow extends StatelessWidget {
  const _BuildersRow();

  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _mentors.length; i++)
                // Each avatar after the first overlaps the one before by
                // 10 pt (`margin-left: -10px`) and sits on top of it.
                Align(
                  widthFactor: i == _mentors.length - 1
                      ? 1
                      : (_size - 10) / _size,
                  alignment: Alignment.centerLeft,
                  child: V3Pop(
                    duration: const Duration(milliseconds: 600),
                    delay: Duration(milliseconds: i * 80),
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.night, width: 2),
                      ),
                      child: V3Avatar(
                        image: AssetImage(
                          'assets/images/mentors/${_mentors[i].slug}.png',
                        ),
                        initials: _mentors[i].initials,
                        tint: _mentors[i].tint,
                        size: _size,
                        gray: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Learn with history’s builders',
            style: AppTypography.sans(
              12.5,
              FontWeight.w500,
            ).copyWith(color: AppColors.nink2),
          ),
        ),
      ],
    );
  }
}
