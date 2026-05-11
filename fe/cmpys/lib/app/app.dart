import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/controllers/session_controller.dart';
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.go(AppRoutes.auth);
        });
      }
    });

    // Set system UI overlay style for the dark glass theme.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp.router(
      title: 'CMPYS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
