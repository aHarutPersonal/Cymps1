import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/router.dart';
import '../controllers/session_controller.dart';

/// CMPYS splash — the green "Who were they, at your age?" intro from the
/// design: gradient field, soft glow, wordmark, overlapping mentor portraits
/// that pop in, a serif headline, subtitle, and a tap-to-begin cue. Resolves
/// the session in the background and auto-advances after ~3.4s (tap to skip).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Design palette (CMPYS 2026).
  static const Color _green = Color(0xFF10B36B);
  static const Color _green2 = Color(0xFF0B9156);

  // Mentor portraits, in the design's order.
  static const _mentors = ['wb', 'mc', 'sj', 'jdr', 'roth', 'em'];

  // Master entrance timeline (ms). The last cue ("tap") starts at 2000ms and
  // animates for 650ms.
  static const int _timeline = 2700;

  late final AnimationController _entrance;
  late final AnimationController _loop; // glow bob + typing-dot pulse
  Timer? _autoAdvance;
  Future<void>? _initFuture;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _timeline),
    )..forward();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Resolve the session in the background while the splash plays.
    _initFuture = ref.read(sessionControllerProvider.notifier).initialize();
    _autoAdvance = Timer(const Duration(milliseconds: 3400), _advance);
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    _entrance.dispose();
    _loop.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_navigated) return;
    _navigated = true;
    _autoAdvance?.cancel();

    try {
      await _initFuture;
    } catch (e) {
      debugPrint('🚀 splash bootstrap error: $e');
    }
    if (!mounted) return;

    final route = switch (ref.read(sessionControllerProvider)) {
      SessionReady() => AppRoutes.home,
      SessionNeedsOnboarding() => AppRoutes.cmpysOnboarding,
      _ => AppRoutes.auth,
    };
    context.go(route);
  }

  // A fade + 10px rise, mapped to a [delayMs, delayMs+durMs] slice of the
  // master timeline (cmpysFadeUp).
  Widget _fadeUp({required int delayMs, int durMs = 650, required Widget child}) {
    final curved = CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        delayMs / _timeline,
        (delayMs + durMs) / _timeline,
        curve: const Cubic(0.22, 0.8, 0.3, 1),
      ),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (_, c) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - curved.value) * 10),
          child: c,
        ),
      ),
      child: child,
    );
  }

  // Scale pop with spring overshoot (cmpysPop).
  Widget _pop({required int delayMs, int durMs = 550, required Widget child}) {
    final curved = CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        delayMs / _timeline,
        ((delayMs + durMs) / _timeline).clamp(0.0, 1.0),
        curve: const Cubic(0.34, 1.5, 0.5, 1),
      ),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (_, c) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.5 + 0.5 * curved.value, // spring curve overshoots past 1
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
      ),
    );

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_green2, _green, _green2],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Soft top-right glow with a gentle bob.
              AnimatedBuilder(
                animation: _loop,
                builder: (_, _) => Positioned(
                  top: -110 + (-3 * _loop.value),
                  right: -130,
                  child: Container(
                    width: 330,
                    height: 330,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x29FFFFFF), Color(0x00FFFFFF)],
                        stops: [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 70),
                      _fadeUp(
                        delayMs: 100,
                        child: Text(
                          'CMPYS',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 3.6, // 0.18em
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Overlapping mentor portraits.
                      SizedBox(
                        height: 56,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < _mentors.length; i++)
                              Positioned(
                                left: i * 40.0, // 56 - 16 overlap
                                child: _pop(
                                  delayMs: 400 + i * 120,
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _green2,
                                      border: Border.all(
                                          color: _green, width: 2.5),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x2E000000),
                                          blurRadius: 12,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                      image: DecorationImage(
                                        fit: BoxFit.cover,
                                        image: AssetImage(
                                            'assets/images/mentors/${_mentors[i]}.png'),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Serif headline.
                      _fadeUp(
                        delayMs: 1150,
                        child: Text(
                          'Who were they,',
                          style: GoogleFonts.bricolageGrotesque(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1.02,
                            letterSpacing: -0.88, // -0.02em
                          ),
                        ),
                      ),
                      _fadeUp(
                        delayMs: 1320,
                        child: Text(
                          'at your age?',
                          style: GoogleFonts.bricolageGrotesque(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1.02,
                            letterSpacing: -0.88,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      _fadeUp(
                        delayMs: 1550,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'Pick a mentor. Measure the gap. Close it — one patient day at a time.',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Tap-to-begin cue with pulsing dots.
                      _fadeUp(
                        delayMs: 2000,
                        child: Opacity(
                          opacity: 0.7,
                          child: Row(
                            children: [
                              _TypingDots(animation: _loop),
                              const SizedBox(width: 10),
                              Text(
                                'Tap to begin',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 64),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three small pulsing dots (the design's typing indicator).
class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => Row(
        children: List.generate(3, (i) {
          // Stagger each dot's pulse phase.
          final phase = (animation.value + i * 0.3) % 1.0;
          final opacity = 0.35 + 0.65 * (1 - (phase - 0.5).abs() * 2);
          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
              ),
            ),
          );
        }),
      ),
    );
  }
}
