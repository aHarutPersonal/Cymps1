import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/loading_state.dart';
import '../../auth/controllers/session_controller.dart';
import '../../comparison/controllers/comparison_controller.dart';
import '../../idols/models/idol_models.dart';
import '../../idols/models/timeline_models.dart';
import '../controllers/home_controller.dart';
import 'widgets/daily_directive_card.dart';
import 'widgets/progress_ring.dart';
import 'widgets/stat_tile.dart';

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
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: _buildBody(homeState, currentUser),
      ),
    );
  }

  Widget _buildBody(HomeState homeState, dynamic currentUser) {
    return switch (homeState) {
      HomeInitial() || HomeLoading() => const LoadingState(
          message: 'Initializing System...',
        ),
      HomeError(:final message) => _buildErrorState(message),
      HomeLoaded(:final idol, :final timeline, :final userAge) =>
        _buildContent(idol, timeline, userAge),
    };
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: AppSpacing.s16),
            Text('System Malfunction', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.s8),
            Text(message, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.s24),
            ElevatedButton(
              onPressed: () => ref.read(homeControllerProvider.notifier).load(),
              child: const Text('RETRY'),
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
  ) {
    final comparisonState = ref.watch(comparisonControllerProvider);
    double overallProgress = 0;
    if (comparisonState is ComparisonLoaded) {
      overallProgress = comparisonState.comparison.overallScore / 100;
    }
    final scorePercent = overallProgress > 0 ? overallProgress : 0.82;
    final scoreLabel = '${(scorePercent * 100).toInt()}';

    // Date label
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMM d').format(now).toUpperCase();

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.s100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.s12),

            // -- HEADER --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateStr,
                        style: AppTypography.captionUpper,
                      ),
                      const SizedBox(height: 4),
                      Text('Hub', style: AppTypography.h1),
                    ],
                  ),
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: NetworkImage(
                      idol.avatarThumbUrl ?? 'https://api.dicebear.com/7.x/avataaars/svg?seed=User',
                    ),
                    backgroundColor: AppColors.surfaceHighlight,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.s16),

            // -- TRAJECTORY ALIGNMENT CARD --
            GestureDetector(
              onTap: () => context.goToComparison(),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.br16,
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.merge_type, size: 14, color: AppColors.blue),
                            const SizedBox(width: 6),
                            Text(
                              'TRAJECTORY ALIGNMENT',
                              style: AppTypography.captionUpper.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              scoreLabel,
                              style: AppTypography.h1.copyWith(
                                fontSize: 40,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            Text(
                              '%',
                              style: AppTypography.h3.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'vs. ${idol.name} (Age $userAge)',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    ProgressRing(
                      percent: scorePercent,
                      label: scoreLabel,
                      subLabel: '',
                      color: AppColors.emerald,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.s16),

            // -- ACTIVE PROTOCOL --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'ACTIVE PROTOCOL',
                style: AppTypography.captionUpper,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ActiveProtocolCard(
                title: 'Current Week Focus',
                description: 'Complete your active plan tasks and track progress.',
                progress: 0.33,
                progressLabel: '1/3',
                onTap: () => context.goToPlan(),
              ),
            ),

            const SizedBox(height: AppSpacing.s24),

            // -- SYSTEM VITALS --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'SYSTEM VITALS',
                style: AppTypography.captionUpper,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Capital Base',
                      value: '\$12.4k',
                      subLabel: 'Target: \$50k (Lagging)',
                      trailingIcon: Icons.trending_up,
                      trailingIconColor: AppColors.emerald,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      label: 'Biometrics',
                      value: 'Optimal',
                      subLabel: 'HRV Ready for deep work',
                      trailingIcon: Icons.show_chart,
                      trailingIconColor: AppColors.blue,
                    ),
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
