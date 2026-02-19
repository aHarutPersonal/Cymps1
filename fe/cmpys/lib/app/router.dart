import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/app_shell.dart';
import '../features/auth/controllers/session_controller.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/comparison/presentation/comparison_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/idols/models/idol_models.dart';
import '../features/idols/presentation/enriching_screen.dart';
import '../features/idols/presentation/idol_confirm_screen.dart';
import '../features/idols/presentation/idol_search_screen.dart';
import '../features/idols/presentation/idol_suggest_screen.dart';
import '../features/intake/models/intake_models.dart';
import '../features/intake/presentation/intake_wizard_screen.dart';
import '../features/plans/presentation/generating_plan_screen.dart';
import '../features/plans/presentation/in_app_lesson_screen.dart';
import '../features/plans/presentation/task_detail_screen.dart';
import '../features/notes/presentation/notes_screen.dart';
import '../features/achievements/presentation/achievements_screen.dart';
import '../features/onboarding/presentation/profile_setup_screen.dart';
import '../features/plans/presentation/plans_screen.dart';
import '../features/plans/presentation/week_detail_screen.dart';
import '../features/profile/presentation/profile_screen.dart';

/// Route paths.
abstract final class AppRoutes {
  // Auth & Onboarding
  static const String splash = '/splash';
  static const String auth = '/auth';
  static const String profileSetup = '/profile-setup';

  // Idol Selection
  static const String idolSuggest = '/idol-suggest';
  static const String idolSearch = '/idol-search';
  static const String idolConfirm = '/idol-confirm';
  static const String enriching = '/enriching';

  // Intake
  static const String intake = '/intake';

  // Plan Generation
  static const String generatingPlan = '/generating-plan';

  // Task Detail
  static const String taskDetail = '/task-detail';

  // In-App Lesson
  static const String inAppLesson = '/lesson';

  // Achievements
  static const String achievements = '/achievements';
  static const String addAchievement = '/achievements/add';

  // Main tabs (shell routes)
  static const String home = '/home';
  static const String comparison = '/comparison';
  static const String plan = '/plan';
  static const String weekDetail = '/week-detail';
  static const String chat = '/chat';
  static const String notes = '/notes';
  static const String profile = '/profile';

  // Routes that don't require authentication
  static const publicRoutes = [splash, auth];

  // Routes that are part of onboarding
  static const onboardingRoutes = [
    profileSetup,
    idolSuggest,
    idolSearch,
    idolConfirm,
    enriching,
    intake,
  ];

  // Main app routes (require full auth + onboarding)
  static const mainRoutes = [home, comparison, plan, chat, notes, profile];
}

/// Navigation keys for shell routes.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Router provider.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    // NO automatic redirects based on session state
    // Navigation is handled explicitly by screens
    routes: [
      // Splash
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (context, state) => const ProfileSetupScreen(),
      ),

      // Idol Selection Flow
      GoRoute(
        path: AppRoutes.idolSuggest,
        builder: (context, state) => const IdolSuggestScreen(),
      ),
      GoRoute(
        path: AppRoutes.idolSearch,
        builder: (context, state) => const IdolSearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.idolConfirm,
        builder: (context, state) {
          final idol = state.extra as IdolCandidate?;
          return IdolConfirmScreen(idol: idol);
        },
      ),
      GoRoute(
        path: AppRoutes.enriching,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return EnrichingScreen(
            jobId: extra?['jobId'] as String?,
            idolId: extra?['idolId'] as String?,
            idol: extra?['idol'] as IdolCandidate?,
          );
        },
      ),

      // Intake Wizard
      GoRoute(
        path: AppRoutes.intake,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return IntakeWizardScreen(
            sessionId: extra?['sessionId'] as String?,
            questions: extra?['questions'] as List<IntakeQuestion>?,
            idolId: extra?['idolId'] as String?,
            targetAge: extra?['targetAge'] as int?,
          );
        },
      ),

      // Generating Plan
      GoRoute(
        path: AppRoutes.generatingPlan,
        builder: (context, state) {
          final jobId = state.extra as String? ?? state.uri.queryParameters['jobId'] ?? '';
          return GeneratingPlanScreen(jobId: jobId);
        },
      ),

      // Week Detail
      GoRoute(
        path: AppRoutes.weekDetail,
        parentNavigatorKey: _rootNavigatorKey, // Push over bottom nav
        builder: (context, state) {
          final weekNumber = state.extra as int? ?? 1;
          return WeekDetailScreen(weekNumber: weekNumber);
        },
      ),

      // Task Detail
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) {
          final itemId = state.extra as String? ?? state.uri.queryParameters['itemId'] ?? '';
          return TaskDetailScreen(itemId: itemId);
        },
      ),

      // In-App Lesson
      GoRoute(
        path: AppRoutes.inAppLesson,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return InAppLessonScreen(
            title: extra?['title'] as String? ?? 'Lesson',
            markdown: extra?['markdown'] as String? ?? '',
            materialId: extra?['materialId'] as String?,
            durationMinutes: extra?['durationMinutes'] as int?,
          );
        },
      ),

      // Achievements
      GoRoute(
        path: AppRoutes.achievements,
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.addAchievement,
        builder: (context, state) => const AddAchievementScreen(),
      ),

      // Main App Shell with Bottom Navigation
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Home Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Comparison Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.comparison,
                builder: (context, state) => const ComparisonScreen(),
              ),
            ],
          ),
          // Plan Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                builder: (context, state) => const PlansScreen(),
              ),
            ],
          ),
          // Chat Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chat,
                builder: (context, state) => const ChatScreen(),
              ),
            ],
          ),
          // Notes Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.notes,
                builder: (context, state) => const NotesScreen(),
              ),
            ],
          ),
          // Profile Tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Extension for easy navigation.
extension GoRouterExtension on BuildContext {
  void goToAuth() => go(AppRoutes.auth);
  void goToProfileSetup() => go(AppRoutes.profileSetup);
  void goToIdolSuggest() => go(AppRoutes.idolSuggest);
  void goToIdolSearch() => go(AppRoutes.idolSearch);
  void goToIdolConfirm(IdolCandidate idol) =>
      go(AppRoutes.idolConfirm, extra: idol);
  void goToEnriching({String? jobId, String? idolId, IdolCandidate? idol}) =>
      go(AppRoutes.enriching, extra: {
        'jobId': jobId,
        'idolId': idolId,
        'idol': idol,
      });
  void goToIntake({
    String? sessionId,
    List<IntakeQuestion>? questions,
    String? idolId,
    int? targetAge,
  }) =>
      go(AppRoutes.intake, extra: {
        'sessionId': sessionId,
        'questions': questions,
        'idolId': idolId,
        'targetAge': targetAge,
      });
  void goToGeneratingPlan(String jobId) =>
      go(AppRoutes.generatingPlan, extra: jobId);
  void goToTaskDetail(String itemId) =>
      push(AppRoutes.taskDetail, extra: itemId);
  void goToInAppLesson({
    required String title,
    required String markdown,
    String? materialId,
    int? durationMinutes,
  }) =>
      push(AppRoutes.inAppLesson, extra: {
        'title': title,
        'markdown': markdown,
        'materialId': materialId,
        'durationMinutes': durationMinutes,
      });
  void goToHome() => go(AppRoutes.home);
  void goToComparison() => go(AppRoutes.comparison);
  void goToPlan() => go(AppRoutes.plan);
  void goToChat() => go(AppRoutes.chat);
  void goToNotes() => go(AppRoutes.notes);
  void goToProfile() => go(AppRoutes.profile);
  void goToAchievements() => push(AppRoutes.achievements);
  void goToAddAchievement() => push(AppRoutes.addAchievement);
  void goToWeekDetail(int weekNumber) => push(AppRoutes.weekDetail, extra: weekNumber);
}
