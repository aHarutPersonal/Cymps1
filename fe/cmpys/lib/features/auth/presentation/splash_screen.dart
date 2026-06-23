import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/ambient_background.dart';
import '../controllers/session_controller.dart';

/// Splash screen — paper bg, coral pulsing logo, "COMPARE YOUR SUCCESS".
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;

  late Animation<double> _logoScale;
  late Animation<double> _titleOpacity;
  late Animation<double> _spinnerOpacity;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    _spinnerOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    _fadeController.forward();

    // Auto-navigate after a moment
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _onStart();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _onStart() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await ref.read(sessionControllerProvider.notifier).initialize();
      if (!mounted) return;

      final sessionState = ref.read(sessionControllerProvider);

      if (sessionState is SessionUnauthenticated) {
        context.go(AppRoutes.auth);
      } else if (sessionState is SessionNeedsOnboarding) {
        context.go(AppRoutes.profileSetup);
      } else if (sessionState is SessionReady) {
        context.go(AppRoutes.home);
      } else if (sessionState is SessionError) {
        context.go(AppRoutes.auth);
      } else {
        context.go(AppRoutes.auth);
      }
    } catch (e) {
      debugPrint('🚀 Error during init: $e');
      if (mounted) context.go(AppRoutes.auth);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Match the paper-first visual system.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        useSafeArea: false,
        child: Stack(
          children: [
            // Center content
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _fadeController,
                  _pulseController,
                ]),
                builder: (context, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Coral pulsing logo
                      Transform.scale(
                        scale:
                            _logoScale.value *
                            (1.0 + _pulseController.value * 0.05),
                        child: Opacity(
                          opacity: _logoScale.value.clamp(0.0, 1.0),
                          child: Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: AppShadows.md,
                            ),
                            child: const Center(
                              child: Text(
                                'CMPYS',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Opacity(
                        opacity: _titleOpacity.value,
                        child: Text(
                          'COMPARE YOUR SUCCESS',
                          style: AppTypography.captionUpper.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 96),

                      // Loading spinner
                      Opacity(
                        opacity: _spinnerOpacity.value,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Bottom tagline
            Positioned(
              bottom: 64,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _fadeController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _spinnerOpacity.value,
                    child: Text(
                      'MASTER YOUR TRAJECTORY',
                      textAlign: TextAlign.center,
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
