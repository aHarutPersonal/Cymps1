import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/app_shell.dart';
import '../core/ui/motion/page_transition.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/cmpys/presentation/chat_screen.dart';
import '../features/cmpys/presentation/compare_screen.dart';
import '../features/cmpys/presentation/onboarding/onboarding_flow.dart';
import '../features/cmpys/presentation/plan_screen.dart';
import '../features/cmpys/presentation/reels_screen.dart';
import '../features/cmpys/presentation/today_screen.dart';
import '../features/cmpys/presentation/you_screen.dart';
import '../features/plan/presentation/book_narration_checkpoint.dart';
import '../features/plan/presentation/book_reader_screen.dart';

/// Route paths for the CMPYS app.
///
/// The whole experience is: splash → auth → AI onboarding → the five-tab
/// shell. Most detail screens are pushed within their tabs. Book readers also
/// have nested declarative routes so a durable narration session can reopen in
/// its original shell branch on cold start.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String auth = '/auth';
  static const String forgotPassword = '/forgot-password';

  /// AI-driven onboarding: personalize → discover mentor → interview →
  /// analysis → blueprint.
  static const String cmpysOnboarding = '/onboarding';

  /// Full-screen idea reels (pushed from Today and You).
  static const String ideas = '/ideas';

  // Main shell tabs — Today · Plan · Chat · Compare · You.
  static const String home = '/home';
  static const String plan = '/plan';
  static const String chat = '/chat';
  static const String vault = '/vault'; // Compare tab
  static const String profile = '/profile'; // You tab

  static const String bookRouteSegment = 'book/:resourceId';
  static const String planBook = '/plan/book/:resourceId';
  static const String profileBook = '/profile/book/:resourceId';

  /// Builds a declarative reader location inside its owning shell branch.
  static String bookReaderLocation({
    required int branchIndex,
    required String resourceId,
    required String fallbackTitle,
    required bool autoplayOnRestore,
  }) {
    final normalizedResourceId = resourceId.trim();
    final normalizedTitle = fallbackTitle.trim();
    if (normalizedResourceId.isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId', 'must not be empty');
    }
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(
        fallbackTitle,
        'fallbackTitle',
        'must not be empty',
      );
    }

    final branchSegment = switch (branchIndex) {
      ActiveBookNarrationResume.planBranchIndex => 'plan',
      ActiveBookNarrationResume.profileBranchIndex => 'profile',
      _ => throw ArgumentError.value(
        branchIndex,
        'branchIndex',
        'must identify the Plan or Profile shell branch',
      ),
    };
    return Uri(
      pathSegments: ['', branchSegment, 'book', normalizedResourceId],
      queryParameters: {
        'title': normalizedTitle,
        if (autoplayOnRestore) 'autoplay': '1',
      },
    ).toString();
  }
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRoute _bookReaderRoute({required int branchIndex}) {
  return GoRoute(
    path: AppRoutes.bookRouteSegment,
    pageBuilder: (context, state) {
      final fallbackTitle = state.uri.queryParameters['title']?.trim();
      return CmpysPageTransition.page(
        key: state.pageKey,
        child: BookReaderScreen(
          resourceId: state.pathParameters['resourceId']!,
          fallbackTitle: fallbackTitle == null || fallbackTitle.isEmpty
              ? 'Book'
              : fallbackTitle,
          shellBranchIndex: branchIndex,
          autoplayOnRestore: state.uri.queryParameters['autoplay'] == '1',
        ),
      );
    },
  );
}

/// Router provider. Navigation is driven explicitly by screens (no global
/// redirects); the splash decides the first destination from session state.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => CmpysPageTransition.page(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.auth,
        pageBuilder: (context, state) => CmpysPageTransition.page(
          key: state.pageKey,
          child: const AuthScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) => CmpysPageTransition.page(
          key: state.pageKey,
          child: const ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.cmpysOnboarding,
        pageBuilder: (context, state) => CmpysPageTransition.page(
          key: state.pageKey,
          child: const CmpysOnboardingFlow(),
        ),
      ),
      GoRoute(
        path: AppRoutes.ideas,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CmpysPageTransition.page(
          key: state.pageKey,
          child: const CmpysReelsScreen(),
        ),
      ),

      // Main app shell with the floating five-tab nav.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) => CmpysPageTransition.page(
                  key: state.pageKey,
                  child: const CmpysTodayScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                pageBuilder: (context, state) => CmpysPageTransition.page(
                  key: state.pageKey,
                  child: const CmpysPlanScreen(),
                ),
                routes: [
                  _bookReaderRoute(
                    branchIndex: ActiveBookNarrationResume.planBranchIndex,
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chat,
                pageBuilder: (context, state) => CmpysPageTransition.page(
                  key: state.pageKey,
                  child: const CmpysChatScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.vault,
                pageBuilder: (context, state) => CmpysPageTransition.page(
                  key: state.pageKey,
                  child: const CmpysCompareScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                pageBuilder: (context, state) => CmpysPageTransition.page(
                  key: state.pageKey,
                  child: const CmpysYouScreen(),
                ),
                routes: [
                  _bookReaderRoute(
                    branchIndex: ActiveBookNarrationResume.profileBranchIndex,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Navigation helpers used across the app.
extension GoRouterExtension on BuildContext {
  void goToIdeas() => push(AppRoutes.ideas);
}
