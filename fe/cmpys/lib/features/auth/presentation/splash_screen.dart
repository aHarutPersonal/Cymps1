import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../controllers/session_controller.dart';

/// Minimal CMPYS splash — green brand, wordmark, auto-advances into the
/// session-resolved route. Replaces the old coral "COMPARE YOUR SUCCESS"
/// screen and never blocks the user behind a tap.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0B9156);

  late final AnimationController _fade;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_navigated) return;
    _navigated = true;

    try {
      await ref.read(sessionControllerProvider.notifier).initialize();
    } catch (e) {
      debugPrint('🚀 splash bootstrap error: $e');
    }
    if (!mounted) return;

    final route = switch (ref.read(sessionControllerProvider)) {
      SessionReady() => AppRoutes.home,
      SessionNeedsOnboarding() => AppRoutes.profileSetup,
      _ => AppRoutes.auth,
    };
    context.go(route);
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
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fade,
        child: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CMPYS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Pick a mentor. Close the gap.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
