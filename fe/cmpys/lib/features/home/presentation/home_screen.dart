import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../auth/controllers/session_controller.dart';
import '../../auth/models/me_models.dart';
import '../../comparison/controllers/comparison_controller.dart';
import '../../idols/models/idol_models.dart';
import '../../idols/models/timeline_models.dart';
import '../../plans/controllers/plans_controller.dart';
import '../../plans/models/plan_models.dart';
import '../../notes/data/notes_repository.dart';
import '../../feed/providers/feed_preloader.dart';
import '../../session/providers/content_resources_provider.dart';
import '../../session/models/content_resource.dart';
import '../controllers/home_controller.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../plans/providers/daily_tasks_provider.dart';
import '../../plans/presentation/widgets/today_checklist.dart';

abstract final class _HomePalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const coral = AppColors.brandAccent;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).load();
      ref.read(comparisonControllerProvider.notifier).load();
      ref.read(plansControllerProvider.notifier).load();
      // Preload discover feed in background
      ref.read(feedCacheProvider.notifier).preload();
    });
  }

  Future<void> _onRefresh() async {
    await ref.read(homeControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(plansControllerProvider, (prev, next) {
      if (next is PlansLoaded) {
        ref.read(dailyTasksProvider.notifier).load(next.plan.id);
      }
    });

    final homeState = ref.watch(homeControllerProvider);
    final currentUser = ref.watch(currentUserProvider);
    final plansState = ref.watch(plansControllerProvider);

    return Scaffold(
      backgroundColor: _HomePalette.canvas,
      body: PrototypeGridBackground(
        child: SafeArea(
          bottom: false,
          child: _buildBody(homeState, currentUser, plansState),
        ),
      ),
    );
  }

  Widget _buildBody(
    HomeState homeState,
    Me? currentUser,
    PlansState plansState,
  ) {
    return switch (homeState) {
      HomeInitial() ||
      HomeLoading() => const LoadingState(message: 'Initializing System...'),
      HomeError(:final message) => _buildErrorState(message),
      HomeLoaded(:final idol, :final timeline, :final userAge) => _buildContent(
        idol,
        timeline,
        userAge,
        currentUser,
        plansState,
      ),
    };
  }

  Widget _buildErrorState(String message) {
    final needsIdol =
        message.toLowerCase().contains('idol') ||
        message.toLowerCase().contains('choose an idol');

    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              needsIdol
                  ? PhosphorIcons.compass(PhosphorIconsStyle.bold)
                  : Icons.error_outline,
              color: needsIdol ? AppColors.accent : AppColors.error,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              needsIdol ? 'Choose Your North Star' : 'Mirror Unavailable',
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              needsIdol
                  ? 'Your selected idol is no longer available. Pick a new benchmark to continue.'
                  : 'We could not load your Mirror right now. Please try again.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            ElevatedButton(
              onPressed: needsIdol
                  ? () => context.goToIdolSuggest()
                  : () => ref.read(homeControllerProvider.notifier).load(),
              child: Text(needsIdol ? 'CHOOSE IDOL' : 'TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    IdolProfile idol,
    TimelineResponse timeline,
    int userAge,
    Me? currentUser,
    PlansState plansState,
  ) {
    if (plansState is PlansNoPlan || plansState is PlansGenerating) {
      return _buildEmptyState();
    }

    final knowledgeGap = _timelineGap(timeline, userAge);
    final userName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!.split(' ').first
        : idol.name.split(' ').first; // Use first name from idol as fallback

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: _HomePalette.coral,
      backgroundColor: _HomePalette.paper,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.floatingNavBarBottom,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Home',
                          style: AppTypography.captionUpper.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 9,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hello, $userName.',
                          style: AppTypography.h2.copyWith(
                            color: _HomePalette.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _StreakBadge(),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Notifications',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.br12,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        PhosphorIconsRegular.bell,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _MentorSummaryCard(
                idol: idol,
                onTap: () => StatefulNavigationShell.of(context).goBranch(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const TodayChecklist(),
            ),
            const SizedBox(height: 16),
            if (plansState is PlansLoaded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _WeeklySummaryCard(plan: plansState.plan),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const _ContinueReadingCard(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ReflectionCard(idolName: idol.name),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _MetricCard(
                label: 'Knowledge Gap',
                value: '$knowledgeGap%',
                unit: '-3%',
              ),
            ),
            const SizedBox(height: 28),
            _StrategicPathSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsRegular.compass,
              color: AppColors.accent,
              size: 56,
            ),
            const SizedBox(height: AppSpacing.s24),
            Text(
              'Welcome to CMPYS',
              style: AppTypography.h2.copyWith(
                color: _HomePalette.ink,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Compare your progress with your idol and get a personalized growth plan.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s32),
            ElevatedButton(
              onPressed: () => context.goToAgenticIntake(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
              ),
              child: Text(
                'Set Up Your 12-Week Plan',
                style: AppTypography.buttonSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _timelineGap(TimelineResponse timeline, int userAge) {
  final total = timeline.items.length;
  if (total == 0) return 0;
  final achieved = timeline.items
      .where((item) => (item.ageAtEvent ?? userAge + 1) <= userAge)
      .length
      .clamp(0, total);
  return (100 - (achieved / total * 100)).round().clamp(0, 99);
}

class _MentorSummaryCard extends StatelessWidget {
  const _MentorSummaryCard({required this.idol, required this.onTap});

  final IdolProfile idol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.br16,
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.mint),
              ),
              clipBehavior: Clip.antiAlias,
              child: idol.avatarThumbUrl != null || idol.avatarUrl != null
                  ? Image.network(
                      idol.avatarThumbUrl ?? idol.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        PhosphorIconsRegular.userCircle,
                        color: AppColors.textTertiary,
                      ),
                    )
                  : const Icon(
                      PhosphorIconsRegular.userCircle,
                      color: AppColors.textTertiary,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Mentor',
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.mint,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    idol.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h4.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReflectionCard extends ConsumerWidget {
  const _ReflectionCard({required this.idolName});

  final String idolName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusAsync = ref.watch(dailyFocusProvider);
    final focus = focusAsync.valueOrNull;
    final prompt = focusAsync.when(
      data: (focus) =>
          focus.reflectionPrompt ??
          'What would $idolName refuse to optimize today?',
      loading: () => 'What would $idolName refuse to optimize today?',
      error: (_, _) => 'What would $idolName refuse to optimize today?',
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: AppRadii.br16,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -2,
            right: -2,
            child: Icon(
              PhosphorIconsRegular.sparkle,
              color: Colors.white.withValues(alpha: 0.10),
              size: 42,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Reflection",
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.mint,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '"$prompt"',
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.white,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: () => _showReflectionSheet(
                  context,
                  ref,
                  prompt: prompt,
                  planItemId: focus?.focusItem?.id,
                ),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.br8),
                ),
                child: Text(
                  'Submit Insight',
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _showReflectionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String prompt,
  String? planItemId,
}) {
  final controller = TextEditingController();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final inset = MediaQuery.of(context).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br20,
            border: Border.all(color: AppColors.border),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Capture reflection', style: AppTypography.h3),
                const SizedBox(height: 8),
                Text(
                  prompt,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 6,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Write what you learned or what you will change.',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.br12,
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final content = controller.text.trim();
                      if (content.isEmpty) return;
                      final date = DateTime.now().toIso8601String().substring(
                        0,
                        10,
                      );
                      final repo = ref.read(notesRepositoryProvider);
                      if (planItemId != null) {
                        await repo.createPlanItemNote(
                          planItemId: planItemId,
                          title: 'Reflection - $date',
                          content: content,
                        );
                      } else {
                        await repo.createNote(
                          title: 'Reflection - $date',
                          content: content,
                        );
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reflection saved')),
                        );
                      }
                    },
                    child: const Text('Save reflection'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

class _WeeklySummaryCard extends StatelessWidget {
  const _WeeklySummaryCard({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final week = plan.currentWeek.clamp(1, plan.durationWeeks).toInt();
    final weekItems = plan.itemsForWeek(week);
    final completed = weekItems.where((item) => item.isCompleted).length;
    final total = weekItems.length;
    final percent = total == 0 ? 0 : ((completed / total) * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.18),
              borderRadius: AppRadii.br12,
            ),
            child: const Icon(Icons.trending_up_rounded, color: AppColors.mint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Week $week summary',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$completed of $total tasks complete. $percent% of this week is closed.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.goToWeekDetail(week),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: AppTypography.h2.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: AppTypography.captionUpper.copyWith(
                    color: unit.startsWith('-')
                        ? AppColors.brandAccent
                        : AppColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StrategicPathSection extends ConsumerWidget {
  const _StrategicPathSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansState = ref.watch(plansControllerProvider);
    final title = switch (plansState) {
      PlansLoaded(:final plan) =>
        'Week ${plan.currentWeek.toString().padLeft(2, '0')}: ${_pathTitle(plan)}',
      PlansGenerating() => 'Building your roadmap',
      PlansNoPlan() => 'Generate your roadmap',
      PlansError() => 'Plan unavailable',
      _ => 'Loading roadmap',
    };
    final subtitle = switch (plansState) {
      PlansLoaded(:final plan) => _pathSubtitle(plan),
      PlansGenerating() => 'The system is translating your intake into weeks.',
      PlansNoPlan() => 'Create a 12-week strategic path from your current gap.',
      PlansError() => 'Tap to retry the roadmap connection.',
      _ => 'Checking the next strategic move.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Strategic Plan',
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.goToPlan(),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Full Roadmap',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => context.goToPlan(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.br16,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: AppRadii.br12,
                    ),
                    child: const Icon(
                      PhosphorIconsRegular.path,
                      color: AppColors.mint,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.h4.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _pathTitle(Plan plan) {
    final items = plan.itemsForWeek(plan.currentWeek);
    if (items.isEmpty) return 'Resource Logic';
    return items.first.category?.trim().isNotEmpty == true
        ? items.first.category!.trim()
        : items.first.title;
  }

  String _pathSubtitle(Plan plan) {
    final items = plan.itemsForWeek(plan.currentWeek);
    if (items.isEmpty) return 'Next Step: Capital Allocation Lesson';
    return 'Next Step: ${items.first.title}';
  }
}

class _StreakBadge extends ConsumerWidget {
  const _StreakBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(streakProvider);
    return streakAsync.when(
      data: (streak) {
        if (streak.currentStreak == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.mint.withValues(alpha: 0.12),
            borderRadius: AppRadii.br8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.mint,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '${streak.currentStreak}-day streak',
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.mint,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _ContinueReadingCard extends ConsumerWidget {
  const _ContinueReadingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resourceAsync = ref.watch(continueReadingProvider);
    return resourceAsync.when(
      data: (resource) {
        if (resource == null) return const SizedBox.shrink();
        return _ContinueReadingCardData(resource: resource);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _ContinueReadingCardData extends StatelessWidget {
  const _ContinueReadingCardData({required this.resource});

  final ContentResource resource;

  @override
  Widget build(BuildContext context) {
    final duration = resource.durationMinutes != null
        ? '${resource.durationMinutes} min'
        : resource.kindLabel;

    return GestureDetector(
      onTap: () {
        if (resource.canReadInApp) {
          context.goToInAppLesson(
            title: resource.title,
            markdown: resource.contentMarkdown ?? '',
            materialId: resource.id,
            durationMinutes: resource.durationMinutes,
            initialIsSaved: resource.isSaved,
            initialProgressPercent: resource.progressPercent,
            initialIsCompleted: resource.isCompleted,
          );
        } else if (resource.isVideo && resource.sourceUrl != null) {
          context.goToPlanVideo(
            title: resource.title,
            url: resource.sourceUrl!,
          );
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.br16,
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.10),
                    borderRadius: AppRadii.br12,
                  ),
                  child: Icon(
                    resource.isVideo
                        ? PhosphorIconsRegular.playCircle
                        : PhosphorIconsRegular.bookOpen,
                    color: AppColors.brandAccent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue Reading',
                        style: AppTypography.captionUpper.copyWith(
                          color: AppColors.brandAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        resource.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.h4.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      duration,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${resource.progressPercent}%',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: AppRadii.br8,
              child: LinearProgressIndicator(
                value: resource.progressPercent / 100,
                backgroundColor: AppColors.borderLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.mint),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
