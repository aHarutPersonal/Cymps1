import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../controllers/session_controller.dart';

/// Splash/landing screen matching Figma design.
/// Shows app branding with "Let's start" button.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  late AnimationController _gradientController;
  
  late Animation<double> _logoScale;
  late Animation<double> _logoRotation;
  late Animation<double> _titleOpacity;
  late Animation<double> _titleSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _buttonOpacity;
  late Animation<double> _buttonSlide;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    // Logo entrance animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Pulsing glow animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    // Floating particles animation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    
    // Gradient animation
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);
    
    // Logo animations
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    
    _logoRotation = Tween<double>(begin: -0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );
    
    // Title animations
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );
    
    _titleSlide = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );
    
    // Subtitle animation
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.5, 0.85, curve: Curves.easeOut),
      ),
    );
    
    // Button animations
    _buttonOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );
    
    _buttonSlide = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );
    
    _logoController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  /// Called when user taps "Let's start"
  Future<void> _onStart() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Initialize session and check auth state
      await ref.read(sessionControllerProvider.notifier).initialize();
      
      if (!mounted) return;
      
      final sessionState = ref.read(sessionControllerProvider);
      
      debugPrint('🚀 Session state after init: ${sessionState.runtimeType}');
      
      // Navigate based on session state
      if (sessionState is SessionUnauthenticated) {
        debugPrint('🚀 Navigating to Auth');
        context.go(AppRoutes.auth);
      } else if (sessionState is SessionNeedsOnboarding) {
        debugPrint('🚀 Navigating to Profile Setup');
        context.go(AppRoutes.profileSetup);
      } else if (sessionState is SessionReady) {
        debugPrint('🚀 Navigating to Home');
        context.go(AppRoutes.home);
      } else if (sessionState is SessionError) {
        debugPrint('🚀 Session error, navigating to Auth');
        context.go(AppRoutes.auth);
      } else {
        // Still initializing somehow - go to auth
        debugPrint('🚀 Unknown state, navigating to Auth');
        context.go(AppRoutes.auth);
      }
    } catch (e) {
      debugPrint('🚀 Error during init: $e');
      if (mounted) {
        context.go(AppRoutes.auth);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _gradientController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      -0.3 + (_gradientController.value * 0.6),
                      -0.5 + (_gradientController.value * 0.3),
                    ),
                    radius: 1.8,
                    colors: [
                      AppColors.accent.withOpacity(0.12 + (_gradientController.value * 0.08)),
                      AppColors.accentLight.withOpacity(0.05),
                      AppColors.bg,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              );
            },
          ),
          
          // Floating particles
          ...List.generate(6, (index) => _FloatingParticle(
            controller: _particleController,
            index: index,
          )),
          
          // Content
          SafeArea(
            child: Padding(
              padding: AppSpacing.screenH,
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  
                  // Logo with pulsing glow
                  AnimatedBuilder(
                    animation: Listenable.merge([_logoController, _pulseController]),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoScale.value,
                        child: Transform.rotate(
                          angle: _logoRotation.value * math.pi,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulsing glow
                              Transform.scale(
                                scale: 1.0 + (_pulseController.value * 0.2),
                                child: Opacity(
                                  opacity: 0.5 * (1 - _pulseController.value),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [AppColors.accent, AppColors.accentLight],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: AppRadii.br24,
                                    ),
                                  ),
                                ),
                              ),
                              // Main logo
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppColors.accent, AppColors.accentLight],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: AppRadii.br24,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accent.withOpacity(0.4),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: SvgPicture.asset(
                                    AppAssets.iconSparkles,
                                    width: 40,
                                    height: 40,
                                    colorFilter: const ColorFilter.mode(
                                      AppColors.textPrimary,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: AppSpacing.s32),
                  
                  // App title
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _titleSlide.value),
                        child: Opacity(
                          opacity: _titleOpacity.value,
                          child: Text(
                            'CMPYS',
                            style: AppTypography.h1.copyWith(
                              fontSize: 36,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: AppSpacing.s12),
                  
                  // Tagline
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _subtitleOpacity.value,
                        child: Text(
                          'Compare Your Success',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const Spacer(flex: 2),
                  
                  // "Let's start" button
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _buttonSlide.value),
                        child: Opacity(
                          opacity: _buttonOpacity.value,
                          child: CmpysButton(
                            label: "Let's start",
                            onPressed: _onStart,
                            isLoading: _isLoading,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating particle for background effect.
class _FloatingParticle extends StatelessWidget {
  const _FloatingParticle({
    required this.controller,
    required this.index,
  });

  final AnimationController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final random = math.Random(index);
    final startX = 0.2 + (random.nextDouble() * 0.6);
    final startY = 0.3 + (random.nextDouble() * 0.5);
    final size = 6.0 + (random.nextDouble() * 6);
    final duration = 3.0 + (random.nextDouble() * 2);
    final delay = random.nextDouble();
    
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = ((controller.value + delay) % 1.0);
        final adjustedProgress = progress / duration * 3;
        final y = startY - (adjustedProgress * 0.3);
        final opacity = (1 - (adjustedProgress.abs())).clamp(0.0, 1.0) * 0.4;
        
        if (y < 0 || opacity <= 0) return const SizedBox.shrink();
        
        return Positioned(
          left: MediaQuery.of(context).size.width * startX,
          top: MediaQuery.of(context).size.height * y,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
