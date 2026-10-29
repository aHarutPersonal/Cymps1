import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/controllers/session_controller.dart';
import '../features/plan/presentation/book_narration_checkpoint.dart';
import 'router.dart';
import 'design_tokens.dart';
import 'theme.dart';

/// Root application widget.
/// Configures MaterialApp.router with light theme.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    ref.listen(sessionControllerProvider, (previous, next) {
      if (next is SessionUnauthenticated) {
        if (previous case SessionReady(
          :final user,
        ) when user.id.trim().isNotEmpty) {
          unawaited(
            const SharedPreferencesActiveBookNarrationResumeStore()
                .clear(user.id)
                .catchError((_) {}),
          );
        }
        // A cold start that resolves signed out stays on the splash, which
        // offers "Get started" and "I already have an account". Every other
        // way of becoming signed out (signing out, an expired session, a link
        // opened straight onto a signed-in page) goes to auth.
        if (previous is SessionInitializing &&
            router.routerDelegate.currentConfiguration.uri.path ==
                AppRoutes.splash) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.go(AppRoutes.auth);
        });
      }
    });

    // Keep system icons readable against the light paper background.
    const overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: MaterialApp.router(
        title: 'CMPYS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.light,
        themeMode: ThemeMode.dark,
        routerConfig: router,
      ),
    );
  }
}
