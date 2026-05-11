import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/app_shell.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/intake/presentation/mentor_intake_screen.dart';
import '../features/chat/presentation/chat_threads_screen.dart';
import '../features/comparison/presentation/comparison_screen.dart';
import '../features/comparison/presentation/comparison_detail_screen.dart';
import '../features/comparison/models/comparison_models.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/idols/models/idol_models.dart';
import '../features/idols/presentation/enriching_screen.dart';
import '../features/idols/presentation/idol_confirm_screen.dart';
import '../features/idols/presentation/idol_search_screen.dart';
import '../features/idols/presentation/idol_suggest_screen.dart';
import '../features/intake/models/intake_models.dart';
import '../features/intake/presentation/achievement_intake_screen.dart';
import '../features/intake/presentation/intake_wizard_screen.dart';
import '../features/plans/presentation/generating_plan_screen.dart';
import '../features/plans/presentation/in_app_lesson_screen.dart';
import '../features/plans/presentation/plan_video_screen.dart';
import '../features/plans/presentation/task_detail_screen.dart';
import '../features/achievements/presentation/achievements_screen.dart';
import '../features/onboarding/presentation/profile_setup_screen.dart';
import '../features/plans/presentation/growth_screen.dart';
import '../features/notes/presentation/studio_screen.dart';
import '../features/plans/presentation/week_detail_screen.dart';
import '../features/profile/presentation/premium_paywall_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/session/presentation/agentic_intake_screen.dart';
import '../features/session/presentation/idol_pick_screen.dart';
import '../features/session/presentation/interview_screen.dart';
import '../features/session/presentation/results_screen.dart';
import '../features/session/presentation/guided_learning_screen.dart';
import '../features/session/presentation/stash_screen.dart';
import '../features/session/presentation/library_screen.dart';

/// Route paths.
abstract final class AppRoutes {
  // Auth & Onboarding
  static const String splash = '/splash';
  static const String auth = '/auth';
  static const String forgotPassword = '/forgot-password';
  static const String profileSetup = '/profile-setup';

  // Idol Selection
  static const String idolSuggest = '/idol-suggest';
  static const String idolSearch = '/idol-search';
  static const String idolConfirm = '/idol-confirm';
  static const String enriching = '/enriching';

  // Intake
  static const String achievementIntake = '/achievement-intake';
  static const String intake = '/intake';

  // Agentic Workflow
  static const String agenticIntake = '/agentic/intake';
  static const String agenticIdolPick = '/agentic/idol-pick';
  static const String agenticInterview = '/agentic/interview';
  static const String agenticResults = '/agentic/results';
  static const String agenticGuidedLearning = '/agentic/guided-learning';
  static const String stash = '/stash';
  static const String library = '/library';

  // Plan Generation
  static const String generatingPlan = '/generating-plan';

  // Task Detail
  static const String taskDetail = '/task-detail';

  // In-App Lesson
  static const String inAppLesson = '/lesson';

  // Plan Video
  static const String planVideo = '/plan-video';

  // Achievements
  static const String achievements = '/achievements';
  static const String addAchievement = '/achievements/add';

  // Comparison Detail
  static const String comparisonDetail = '/comparison-detail';

  // Main tabs (shell routes)
  static const String home = '/home';
  static const String comparison = '/comparison';
  static const String plan = '/plan';
  static const String weekDetail = '/week-detail';
  static const String chat = '/chat';
  static const String chatThreads = '/chat-threads';
  static const String chatThread = '/chat-thread';
  static const String discover = '/discover';
  static const String notes = '/notes';
  static const String profile = '/profile';
  static const String premium = '/premium';

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
  static const mainRoutes = [home, plan, discover, chat, library];
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
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
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

      // Achievement Intake (before general intake)
      GoRoute(
        path: AppRoutes.achievementIntake,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AchievementIntakeScreen(
            idolId: extra?['idolId'] as String? ?? '',
            targetAge: extra?['targetAge'] as int?,
            mentorName: extra?['mentorName'] as String?,
            mentorImageUrl: extra?['mentorImageUrl'] as String?,
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
            mentorName: extra?['mentorName'] as String?,
          );
        },
      ),

      // =======================================================================
      // Agentic Workflow Routes
      // =======================================================================
      GoRoute(
        path: AppRoutes.agenticIntake,
        builder: (context, state) => const AgenticIntakeScreen(),
      ),
      GoRoute(
        path: AppRoutes.agenticIdolPick,
        builder: (context, state) {
          final sessionId = state.extra as String? ?? '';
          return IdolPickScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoutes.agenticInterview,
        builder: (context, state) {
          final sessionId = state.extra as String? ?? '';
          return InterviewScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoutes.agenticResults,
        builder: (context, state) {
          final sessionId = state.extra as String? ?? '';
          return ResultsScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoutes.agenticGuidedLearning,
        builder: (context, state) {
          final topic = state.extra as String? ?? 'My Plan';
          return GuidedLearningScreen(topic: topic);
        },
      ),
      GoRoute(
        path: AppRoutes.stash,
        builder: (context, state) => const StashScreen(),
      ),

      // Generating Plan
      GoRoute(
        path: AppRoutes.generatingPlan,
        builder: (context, state) {
          final jobId =
              state.extra as String? ??
              state.uri.queryParameters['jobId'] ??
              '';
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
          final itemId =
              state.extra as String? ??
              state.uri.queryParameters['itemId'] ??
              '';
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
            initialIsSaved: extra?['initialIsSaved'] as bool? ?? false,
            initialProgressPercent:
                extra?['initialProgressPercent'] as int? ?? 0,
            initialIsCompleted: extra?['initialIsCompleted'] as bool? ?? false,
          );
        },
      ),

      // Plan Video
      GoRoute(
        path: AppRoutes.planVideo,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PlanVideoScreen(
            title: extra?['title'] as String? ?? 'Video',
            url: extra?['url'] as String? ?? '',
            source: extra?['source'] as String?,
            reason: extra?['reason'] as String?,
            materialId: extra?['materialId'] as String?,
            initialIsSaved: extra?['initialIsSaved'] as bool? ?? false,
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

      // Comparison Detail
      GoRoute(
        path: AppRoutes.comparisonDetail,
        builder: (context, state) {
          final comparison = state.extra as ComparisonResponse;
          return ComparisonDetailScreen(comparison: comparison);
        },
      ),

      // Chat
      GoRoute(
        path: AppRoutes.chat,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MentorIntakeScreen(),
      ),
      // Chat Threads (History)
      GoRoute(
        path: AppRoutes.chatThreads,
        builder: (context, state) => const ChatThreadsScreen(),
      ),
      GoRoute(
        path: AppRoutes.chatThread,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final threadId = extra?['threadId'] as String? ?? '';
          return MentorIntakeScreen(threadId: threadId);
        },
      ),

      // Comparison (push route from Home hero card)
      GoRoute(
        path: AppRoutes.comparison,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ComparisonScreen(),
      ),

      // Profile (push route from Home tab)
      GoRoute(
        path: AppRoutes.profile,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.premium,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PremiumPaywallScreen(),
      ),

      // Main App Shell with Bottom Navigation — 4 tabs
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Tab 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Tab 1: Growth (Plan main)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                builder: (context, state) => const GrowthScreen(),
              ),
            ],
          ),
          // Tab 2: Studio (Notes main)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.notes,
                builder: (context, state) => const StudioScreen(),
              ),
            ],
          ),
          // Tab 3: Vault (Library main)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.library,
                builder: (context, state) {
                  final tab = state.extra as int? ?? 0;
                  return LibraryScreen(initialTab: tab);
                },
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
  void goToForgotPassword() => push(AppRoutes.forgotPassword);
  void goToProfileSetup() => go(AppRoutes.profileSetup);
  void goToIdolSuggest() => go(AppRoutes.idolSuggest);
  void goToIdolSearch() => go(AppRoutes.idolSearch);
  void goToIdolConfirm(IdolCandidate idol) =>
      go(AppRoutes.idolConfirm, extra: idol);
  void goToEnriching({String? jobId, String? idolId, IdolCandidate? idol}) =>
      go(
        AppRoutes.enriching,
        extra: {'jobId': jobId, 'idolId': idolId, 'idol': idol},
      );
  void goToAchievementIntake({
    required String idolId,
    int? targetAge,
    String? mentorName,
    String? mentorImageUrl,
  }) => go(
    AppRoutes.achievementIntake,
    extra: {
      'idolId': idolId,
      'targetAge': targetAge,
      'mentorName': mentorName,
      'mentorImageUrl': mentorImageUrl,
    },
  );
  void goToIntake({
    String? sessionId,
    List<IntakeQuestion>? questions,
    String? idolId,
    int? targetAge,
    String? mentorName,
  }) => go(
    AppRoutes.intake,
    extra: {
      'sessionId': sessionId,
      'questions': questions,
      'idolId': idolId,
      'targetAge': targetAge,
      'mentorName': mentorName,
    },
  );

  // Agentic workflow
  void goToAgenticIntake() => go(AppRoutes.agenticIntake);
  void goToAgenticIdolPick(String sessionId) =>
      go(AppRoutes.agenticIdolPick, extra: sessionId);
  void goToAgenticInterview(String sessionId) =>
      go(AppRoutes.agenticInterview, extra: sessionId);
  void goToAgenticResults(String sessionId) =>
      go(AppRoutes.agenticResults, extra: sessionId);
  void goToAgenticGuidedLearning(String topic) =>
      push(AppRoutes.agenticGuidedLearning, extra: topic);
  void goToStash() => push(AppRoutes.stash);
  void goToLibrary({int tab = 0}) => push(AppRoutes.library, extra: tab);
  void goToPremium() => push(AppRoutes.premium);

  void goToGeneratingPlan(String jobId) =>
      go(AppRoutes.generatingPlan, extra: jobId);
  void goToTaskDetail(String itemId) =>
      push(AppRoutes.taskDetail, extra: itemId);
  void goToInAppLesson({
    required String title,
    required String markdown,
    String? materialId,
    int? durationMinutes,
    bool initialIsSaved = false,
    int initialProgressPercent = 0,
    bool initialIsCompleted = false,
  }) => push(
    AppRoutes.inAppLesson,
    extra: {
      'title': title,
      'markdown': markdown,
      'materialId': materialId,
      'durationMinutes': durationMinutes,
      'initialIsSaved': initialIsSaved,
      'initialProgressPercent': initialProgressPercent,
      'initialIsCompleted': initialIsCompleted,
    },
  );
  void goToPlanVideo({
    required String title,
    required String url,
    String? source,
    String? reason,
    String? materialId,
    bool initialIsSaved = false,
  }) => push(
    AppRoutes.planVideo,
    extra: {
      'title': title,
      'url': url,
      'source': source,
      'reason': reason,
      'materialId': materialId,
      'initialIsSaved': initialIsSaved,
    },
  );
  void goToHome() => go(AppRoutes.home);
  void goToComparison() => push(AppRoutes.comparison);
  void goToPlan() => go(AppRoutes.plan);
  void goToChat() => push(AppRoutes.chat);
  void goToNotes() => go(AppRoutes.notes);
  void goToProfile() => go(AppRoutes.profile);
  void goToAchievements() => push(AppRoutes.achievements);
  void goToAddAchievement() => push(AppRoutes.addAchievement);
  void goToComparisonDetail(ComparisonResponse comparison) =>
      push(AppRoutes.comparisonDetail, extra: comparison);
  void goToWeekDetail(int weekNumber) =>
      push(AppRoutes.weekDetail, extra: weekNumber);
}
