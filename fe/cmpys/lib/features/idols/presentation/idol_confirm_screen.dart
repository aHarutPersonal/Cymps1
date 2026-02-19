import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_app_bar.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/list_tile_card.dart';
import '../../auth/controllers/session_controller.dart';
import '../../intake/data/intake_repository.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../data/idols_repository.dart';
import '../models/idol_models.dart';

class IdolConfirmScreen extends ConsumerStatefulWidget {
  const IdolConfirmScreen({super.key, this.idol});

  final IdolCandidate? idol;

  @override
  ConsumerState<IdolConfirmScreen> createState() => _IdolConfirmScreenState();
}

class _IdolConfirmScreenState extends ConsumerState<IdolConfirmScreen> {
  bool _isImporting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);
    
    // Get idol from widget or state
    final selectedIdol = widget.idol ?? _getIdolFromState(onboardingState);
    
    if (selectedIdol == null) {
      return Scaffold(
        appBar: const CmpysAppBar(title: 'Confirm Selection'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No idol selected',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.s16),
              CmpysButton(
                label: 'Go Back',
                onPressed: () => context.go(AppRoutes.idolSuggest),
              ),
            ],
          ),
        ),
      );
    }

    // Get user age from session
    final userAge = ref.read(sessionControllerProvider.notifier).userAge ?? 25;

    return Scaffold(
      appBar: const CmpysAppBar(title: 'Confirm Selection'),
      body: Column(
        children: [
          // Error banner
          if (_errorMessage != null)
            _ErrorBanner(
              message: _errorMessage!,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: AppSpacing.s24,
                right: AppSpacing.s24,
                bottom: AppSpacing.s24,
              ),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.s24),
                  // Avatar with CachedNetworkImage
                  GradientAvatar(
                    initials: _getInitials(selectedIdol.name),
                    imageUrl: selectedIdol.avatarThumbUrl,
                    size: 96,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    selectedIdol.name, 
                    style: AppTypography.h1,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    selectedIdol.occupations.join(', '),
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  // Info cards
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          icon: AppAssets.iconCalendar,
                          label: 'Born',
                          value: selectedIdol.birthDate?.year.toString() ?? 'N/A',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: _InfoCard(
                          icon: AppAssets.iconTarget,
                          label: selectedIdol.isLocal ? 'Relevance' : 'Confidence',
                          value: selectedIdol.isLocal
                              ? (selectedIdol.relevanceScore != null
                                  ? '${(selectedIdol.relevanceScore! * 100).round()}%'
                                  : 'N/A')
                              : (selectedIdol.confidence != null
                                  ? '${(selectedIdol.confidence! * 100).round()}%'
                                  : 'N/A'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  // Description
                  if (selectedIdol.description != null) ...[
                    CmpysCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SvgPicture.asset(
                                AppAssets.iconInfo,
                                width: 18,
                                height: 18,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.accent,
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Text('About', style: AppTypography.bodyMedium),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          Text(
                            selectedIdol.description!,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                  // Wikipedia link
                  if (selectedIdol.wikipediaUrl != null) ...[
                    CmpysCard(
                      child: Row(
                        children: [
                          SvgPicture.asset(
                            AppAssets.iconExternalLink,
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              AppColors.textSecondary,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: Text(
                              'View on Wikipedia',
                              style: AppTypography.body.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          SvgPicture.asset(
                            AppAssets.iconChevronRight,
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              AppColors.textTertiary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                  // Comparison info
                  CmpysGradientCard(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.2),
                            borderRadius: AppRadii.br12,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              AppAssets.iconTrendingUp,
                              width: 20,
                              height: 20,
                              colorFilter: const ColorFilter.mode(
                                AppColors.accent,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comparing at age $userAge',
                                style: AppTypography.bodyMedium,
                              ),
                              Text(
                                'See what ${selectedIdol.name.split(' ').first} achieved by your age',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            ),
          ),
          // Bottom buttons
          _BottomButtons(
            onConfirm: () => _handleConfirm(selectedIdol),
            onCancel: () => context.pop(),
            isLoading: _isImporting,
          ),
        ],
      ),
    );
  }

  IdolCandidate? _getIdolFromState(OnboardingState state) {
    if (state is OnboardingIdolConfirmStep) {
      return state.selectedIdol;
    }
    return null;
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first.substring(0, 2).toUpperCase();
  }

  /// Handle confirm button - calls POST /idols/import
  Future<void> _handleConfirm(IdolCandidate idol) async {
    debugPrint('🎯 _handleConfirm called: ${idol.name}, isLocal=${idol.isLocal}, id=${idol.id}');
    
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final userAge = ref.read(sessionControllerProvider.notifier).userAge;
      debugPrint('🎯 User age: $userAge');
      
      // For local suggestions, the idol already exists - just select it and start intake
      if (idol.isLocal && idol.id != null) {
        debugPrint('🎯 Local idol - starting intake directly');
        
        // Store idol ID in session
        await ref.read(sessionControllerProvider.notifier).setCurrentIdolId(idol.id!);
        
        if (!mounted) return;
        
        // Start intake for existing idol
        final intakeRepository = ref.read(intakeRepositoryProvider);
        debugPrint('📋 Starting intake for local idol: ${idol.id}');
        
        final intakeResponse = await intakeRepository.startIntake(
          idolId: idol.id,
          targetAge: userAge,
        );

        debugPrint('📋 Intake started: sessionId=${intakeResponse.sessionId}, questions=${intakeResponse.questions.length}');

        if (!mounted) return;

        // Navigate to intake wizard
        debugPrint('🚀 Navigating to IntakeWizardScreen');
        context.goToIntake(
          sessionId: intakeResponse.sessionId,
          questions: intakeResponse.questions,
          idolId: idol.id,
          targetAge: userAge,
        );
        return;
      }
      
      debugPrint('🎯 Web idol - going through enrichment first');

      // For web suggestions, import from provider with all metadata
      final idolsRepository = ref.read(idolsRepositoryProvider);
      final importResponse = await idolsRepository.importIdol(
        provider: idol.provider,
        externalId: idol.externalId,
        name: idol.name,
        description: idol.description,
        birthDate: idol.birthDate?.toIso8601String().split('T')[0], // YYYY-MM-DD format
        wikipediaUrl: idol.wikipediaUrl,
        occupations: idol.occupations.isNotEmpty ? idol.occupations : null,
      );

      if (!mounted) return;

      // Navigate to enriching screen (which will start intake after enrichment completes)
      context.goToEnriching(
        jobId: importResponse.jobId,
        idolId: importResponse.idolId,
        idol: idol,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _errorMessage = e.toString();
      });
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      padding: AppSpacing.p16,
      child: Column(
        children: [
          SvgPicture.asset(
            icon,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(value, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

class _BottomButtons extends StatelessWidget {
  const _BottomButtons({
    required this.onConfirm,
    required this.onCancel,
    this.isLoading = false,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.s24,
        right: AppSpacing.s24,
        bottom: AppSpacing.s24,
        top: AppSpacing.s16,
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CmpysButton(
              label: 'Confirm & Continue',
              onPressed: isLoading ? null : onConfirm,
              isLoading: isLoading,
            ),
            const SizedBox(height: AppSpacing.s12),
            CmpysButton(
              label: 'Choose Different Idol',
              variant: CmpysButtonVariant.ghost,
              onPressed: isLoading ? null : onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Error banner widget
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: AppColors.error.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            AppAssets.iconAlertCircle,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              AppColors.error,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: SvgPicture.asset(
              AppAssets.iconX,
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(
                AppColors.error.withOpacity(0.7),
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
