import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../models/idol_models.dart';
import '../models/job_models.dart';
import 'idol_visuals.dart';
import 'widgets/idol_grid_card.dart';

class IdolSuggestScreen extends ConsumerStatefulWidget {
  const IdolSuggestScreen({super.key});

  @override
  ConsumerState<IdolSuggestScreen> createState() => _IdolSuggestScreenState();
}

class _IdolSuggestScreenState extends ConsumerState<IdolSuggestScreen> {
  IdolCandidate? _selectedIdol;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(onboardingControllerProvider);
      if (state is! OnboardingIdolSuggestStep) {
        ref.read(onboardingControllerProvider.notifier).loadIdolSuggestions();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);

    ref.listen(onboardingControllerProvider, (prev, next) {
      if (next is OnboardingError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _buildBody(onboardingState),
    );
  }

  Widget _buildBody(OnboardingState state) {
    if (state is OnboardingIdolSuggestStep && state.isLoading) {
      return _PrototypeThinkingScreen(status: state.jobStatus);
    }

    final suggestions = state is OnboardingIdolSuggestStep
        ? state.suggestions
        : <IdolCandidate>[];

    return PrototypeGridBackground(
      gridSize: 20,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s32,
              MediaQuery.paddingOf(context).top + AppSpacing.s24,
              AppSpacing.s32,
              AppSpacing.s24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Target_Selection',
                            style: AppTypography.captionUpper.copyWith(
                              color: AppColors.mint,
                              fontSize: 9,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose your North Star',
                            style: AppTypography.h2.copyWith(fontSize: 24),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: AppRadii.br12,
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s24),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.idolSearch),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: AppRadii.br12,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.charcoal.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          AppAssets.iconSearch,
                          width: 18,
                          height: 18,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Text(
                          'Search titan, domain, or era...',
                          style: AppTypography.captionUpper.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Grid Content
          Expanded(
            child: suggestions.isEmpty
                ? _buildEmptyState()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.s16,
                          mainAxisSpacing: AppSpacing.s16,
                          childAspectRatio: 0.66,
                        ),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final idol = suggestions[index];
                      return IdolGridCard(
                        idol: idol,
                        isSelected:
                            _selectedIdol?.externalId == idol.externalId,
                        onTap: () => setState(() => _selectedIdol = idol),
                      );
                    },
                  ),
          ),

          Container(
            padding: EdgeInsets.only(
              left: AppSpacing.s32,
              right: AppSpacing.s32,
              bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.s24,
              top: AppSpacing.s20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.surface.withValues(alpha: 0),
                  AppColors.surface,
                  AppColors.surface,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (suggestions.isNotEmpty && _selectedIdol == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: GestureDetector(
                      onTap: () => context.push(AppRoutes.idolSearch),
                      child: Text(
                        "Don't see your idol? Search here",
                        style: AppTypography.caption.copyWith(
                          color: AppColors.brandAccent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),

                GestureDetector(
                  onTap: _selectedIdol != null
                      ? () => _onSelectIdol(_selectedIdol!)
                      : null,
                  child: Opacity(
                    opacity: _selectedIdol != null ? 1 : 0.35,
                    child: Container(
                      height: 64,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.charcoal,
                        borderRadius: AppRadii.br12,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Analyze Trajectory',
                        style: AppTypography.button.copyWith(fontSize: 17),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.s16),
          Text('No stars found', style: AppTypography.bodyMedium),
          const SizedBox(height: AppSpacing.s24),
          CmpysButton(
            label: 'Search Manually',
            onPressed: () => context.push(AppRoutes.idolSearch),
          ),
        ],
      ),
    );
  }

  void _onSelectIdol(IdolCandidate idol) {
    ref.read(onboardingControllerProvider.notifier).selectIdol(idol);
    context.goToIdolConfirm(idol);
  }
}

class _PrototypeThinkingScreen extends StatelessWidget {
  const _PrototypeThinkingScreen({this.status});

  final JobStatus? status;

  @override
  Widget build(BuildContext context) {
    final progress = status?.progressPercent ?? 0;
    final activeStep = status?.step ?? 'analyzing_interests';
    return PrototypeGridBackground(
      color: AppColors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 3),
                builder: (context, value, child) => Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 2,
                    margin: EdgeInsets.only(
                      top: MediaQuery.sizeOf(context).height * value,
                    ),
                    color: AppColors.mint.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: AppSpacing.p24,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _Ring(inset: 0, opacity: 0.10),
                        _Ring(inset: 40, opacity: 0.20),
                        _Ring(inset: 80, opacity: 0.40),
                        Container(
                          width: 192,
                          height: 192,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.mint, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.mint.withValues(alpha: 0.20),
                                blurRadius: 40,
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            kPrototypeThinkingAsset,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.mint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Engine.Reasoning_Active',
                        style: AppTypography.captionUpper.copyWith(
                          color: AppColors.mint,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    'Synthesizing your\nStrategic Identity...',
                    style: AppTypography.h2.copyWith(height: 1.2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  Container(
                    width: double.infinity,
                    padding: AppSpacing.p20,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      border: Border.all(color: AppColors.borderLight),
                      borderRadius: AppRadii.br12,
                    ),
                    child: Column(
                      children: [
                        _LogRow(
                          label: 'COMPRESSING_GOALS',
                          complete: progress >= 30,
                        ),
                        _LogRow(
                          label: 'MAPPING_INTEREST_CLUSTERS',
                          active: activeStep == 'analyzing_interests',
                          complete: progress >= 45,
                        ),
                        _LogRow(
                          label: 'QUERYING_MENTOR_MATCHES',
                          active: activeStep == 'querying_knowledge_base',
                          complete: progress >= 80,
                        ),
                        _LogRow(
                          label: 'ALIGNING_TITAN_PROTOCOLS',
                          active: activeStep == 'filtering_matches',
                          complete: progress >= 100,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s48),
                  Text(
                    'Session ID: CX-2920-ALPHA',
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.textTertiary.withValues(alpha: 0.45),
                      fontSize: 8,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.inset, required this.opacity});

  final double inset;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      left: inset,
      right: inset,
      top: inset,
      bottom: inset,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.mint.withValues(alpha: opacity)),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.label,
    this.active = false,
    this.complete = false,
  });

  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: active || complete ? 1 : 0.30,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.captionUpper.copyWith(
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontSize: 9,
                ),
              ),
            ),
            if (complete)
              const Icon(Icons.check_rounded, color: AppColors.mint, size: 14)
            else if (active)
              Container(width: 12, height: 2, color: AppColors.mint),
          ],
        ),
      ),
    );
  }
}
