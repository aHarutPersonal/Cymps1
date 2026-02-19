import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/progress_bar.dart';
import '../../../core/ui/thinking_stream.dart';
import '../../idols/models/job_models.dart';
import '../controllers/plans_controller.dart';
import '../models/plan_models.dart';
import 'widgets/ascent_map.dart';

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(plansControllerProvider.notifier).load();
    });
  }

  Future<void> _onRefresh() async {
    await ref.read(plansControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final plansState = ref.watch(plansControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: _buildBody(plansState),
      ),
      floatingActionButton: plansState is PlansLoaded
          ? FloatingActionButton.extended(
              onPressed: () => _showRegenerateDialog(),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('New Plan'),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.bg,
            )
          : null,
    );
  }

  Widget _buildBody(PlansState state) {
    return switch (state) {
      PlansInitial() || PlansLoading() => const LoadingState(
          message: 'Loading your path...',
        ),
      PlansGenerating(:final jobStatus) => _buildGeneratingState(jobStatus),
      PlansNoPlan() => _buildNoPlanState(),
      PlansError(:final message) => _buildErrorState(message),
      PlansLoaded(:final plan) => _buildAscentMap(plan),
    };
  }

  Widget _buildAscentMap(Plan plan) {
    // Transform Plan data into AscentMap model
    final currentWeek = plan.currentWeek;
    final totalWeeks = plan.durationWeeks.clamp(1, 52); // Cap at 52 for sanity
    
    final weeks = List.generate(totalWeeks, (index) {
      final weekNum = index + 1;
      final isCompleted = weekNum < currentWeek;
      final isCurrent = weekNum == currentWeek;
      final isLocked = weekNum > currentWeek; 
      
      // Try to find a title from the first "Focus" item of that week?
      // Or just generic.
      String title = 'Week $weekNum';
      final weekItems = plan.itemsForWeek(weekNum);
      if (weekItems.isNotEmpty) {
        // Find a distinct title?
        // Maybe "Foundation", "Growth", etc. based on index?
        // For now, keep it simple.
      }

      return {
        'number': weekNum,
        'title': title,
        'isCompleted': isCompleted,
        'isCurrent': isCurrent,
        'isLocked': isLocked,
      };
    });

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Architecture', style: AppTypography.h1),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Text(
                      'PHASE ${((currentWeek - 1) / 4).floor() + 1}',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              Icon(Icons.flag, color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),

        // Map
        Expanded(
          child: AscentMap(
            weeks: weeks,
            onWeekSelected: (weekNum) {
               context.goToWeekDetail(weekNum);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratingState(JobStatus? jobStatus) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.s32),
        Padding(
          padding: AppSpacing.screenH,
          child: Column(
            children: [
              Text(
                'Charting the Course',
                style: AppTypography.h2.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Analyzing the stars for your perfect path...',
                style: AppTypography.body.copyWith(
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        if (jobStatus != null)
          Padding(
            padding: AppSpacing.screenH,
            child: ProgressBar(
              progress: jobStatus.progressPercent / 100,
              height: 6,
              animated: true,
            ),
          ),
        const SizedBox(height: AppSpacing.s24),
        if (jobStatus?.thinkingStream != null)
          Expanded(
            child: SingleChildScrollView(
              padding: AppSpacing.screenH,
              child: ThinkingStreamWidget(
                stream: jobStatus!.thinkingStream!,
              ),
            ),
          )
        else
          const Expanded(
            child: Center(
              child: LoadingState(message: 'Initializing AI thinking...'),
            ),
          ),
      ],
    );
  }

  Widget _buildNoPlanState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadii.br16,
                boxShadow: AppShadows.glowLime,
              ),
              child: Center(
                child: SvgPicture.asset(
                  AppAssets.iconSparkles,
                  width: 40,
                  height: 40,
                  colorFilter: const ColorFilter.mode(
                    Colors.black,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            Text('No Path Charted', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Generate a personalized plan based on\nyour idol\'s journey and your goals',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s32),
            CmpysButton(
              label: 'Generate Plan',
              icon: AppAssets.iconSparkles,
              onPressed: () => _showGenerateDialog(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.s16),
            Text('Navigation Error', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Retry',
              onPressed: () => ref.read(plansControllerProvider.notifier).load(),
            ),
          ],
        ),
      ),
    );
  }

  void _showGenerateDialog() {
    ref.read(plansControllerProvider.notifier).generatePlan();
  }

  void _showRegenerateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Regenerate Plan?', style: AppTypography.h3),
        content: Text(
          'This will replace your current path with a new one. History will be preserved in your profile.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTypography.buttonSmall.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(plansControllerProvider.notifier).generatePlan();
            },
            child: Text('Regenerate', style: AppTypography.buttonSmall.copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
