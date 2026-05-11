import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../feed/providers/feed_preloader.dart';
import '../controllers/home_controller.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
    final homeState = ref.watch(homeControllerProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: _HomePalette.canvas,
      body: PrototypeGridBackground(
        child: SafeArea(
          bottom: false,
          child: _buildBody(homeState, currentUser),
        ),
      ),
    );
  }

  Widget _buildBody(HomeState homeState, Me? currentUser) {
    return switch (homeState) {
      HomeInitial() ||
      HomeLoading() => const LoadingState(message: 'Initializing System...'),
      HomeError(:final message) => _buildErrorState(message),
      HomeLoaded(:final idol, :final timeline, :final userAge) => _buildContent(
        idol,
        timeline,
        userAge,
        currentUser,
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
  ) {
    final userName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!.split(' ').first
        : idol.name.split(' ').first; // Use first name from idol as fallback

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: _HomePalette.coral,
      backgroundColor: _HomePalette.paper,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.s100),
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
                          'Console.Mirror',
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
                onTap: () => context.goToChat(),
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ReflectionCard(
                idolName: idol.name,
                onTap: () => context.goToChat(),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Consistency',
                      value: '12',
                      unit: 'Days',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _MetricCard(
                      label: 'Knowledge Gap',
                      value: '${_timelineGap(timeline, userAge)}%',
                      unit: '-3%',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _StrategicPathSection(),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CURRENT_TITAN',
                          style: AppTypography.captionUpper.copyWith(
                            color: AppColors.mint,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'ALIGN: 98%',
                        style: AppTypography.captionUpper.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ],
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

class _ReflectionCard extends StatelessWidget {
  const _ReflectionCard({required this.idolName, required this.onTap});

  final String idolName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                '"What would $idolName refuse to optimize today?"',
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.white,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: onTap,
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
      PlansError() => 'Path unavailable',
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
                'Strategic_Path',
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
