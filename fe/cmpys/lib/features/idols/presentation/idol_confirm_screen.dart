import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_app_bar.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../auth/controllers/session_controller.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../data/idols_repository.dart';
import '../models/idol_models.dart';
import 'idol_visuals.dart';

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
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
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

    final domain = idolDomainLabel(selectedIdol);
    final score =
        selectedIdol.confidence ?? selectedIdol.relevanceScore ?? 0.984;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 138),
              child: Column(
                children: [
                  SizedBox(
                    height: 480,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(
                          colorFilter: const ColorFilter.matrix(<double>[
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ]),
                          child: Image.network(
                            imageUrlForIdolCandidate(selectedIdol, hero: true),
                            fit: BoxFit.cover,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.charcoal.withValues(alpha: 0.16),
                                Colors.transparent,
                                AppColors.charcoal.withValues(alpha: 0.88),
                              ],
                              stops: const [0, 0.45, 1],
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _HeroButton(
                                      icon: Icons.chevron_left_rounded,
                                      onPressed: () => context.pop(),
                                    ),
                                    _HeroButton(
                                      icon: Icons.ios_share_rounded,
                                      onPressed: () {},
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Selected_Titan',
                                        style: AppTypography.captionUpper
                                            .copyWith(
                                              color: AppColors.mint,
                                              fontSize: 10,
                                              letterSpacing: 1.6,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        selectedIdol.name,
                                        style: AppTypography.readingBold
                                            .copyWith(
                                              color: Colors.white,
                                              fontSize: 38,
                                              height: 1.05,
                                              fontStyle: FontStyle.italic,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Domain: $domain',
                                        style: AppTypography.captionUpper
                                            .copyWith(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                      ),
                                      const SizedBox(height: 28),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PrototypeGridBackground(
                    gridSize: 20,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null)
                            _InlineError(
                              message: _errorMessage!,
                              onDismiss: () =>
                                  setState(() => _errorMessage = null),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricCell(
                                  label: 'Alignment',
                                  value: '${(score * 100).toStringAsFixed(1)}%',
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: _MetricCell(
                                  label: 'Path_Duration',
                                  value: '12 Weeks',
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: _MetricCell(
                                  label: 'Complexity',
                                  value: 'High',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          Text(
                            'Strategic_Fit',
                            style: AppTypography.captionUpper.copyWith(
                              color: AppColors.mint,
                              fontSize: 10,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            selectedIdol.description ??
                                '${selectedIdol.name} gives this path a concrete benchmark: compare the operating principles, proof points, and learning cadence against your current trajectory.',
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.65,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _ProtocolCard(
                            title: '12-Week Allocation Protocol',
                            body:
                                'A sequenced path calibrated against what ${selectedIdol.name.split(' ').first} built by age $userAge.',
                            icon: Icons.trending_up_rounded,
                          ),
                          const SizedBox(height: 12),
                          const _ProtocolCard(
                            title: 'Unlimited Logic Consultation',
                            body:
                                'Ask follow-up questions inside Studio while the path evolves.',
                            icon: Icons.chat_bubble_outline_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomButtons(
              onConfirm: () => _handleConfirm(selectedIdol),
              onCancel: () => context.pop(),
              isLoading: _isImporting,
            ),
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

  /// Handle confirm button - calls POST /idols/import
  Future<void> _handleConfirm(IdolCandidate idol) async {
    debugPrint(
      '🎯 _handleConfirm called: ${idol.name}, isLocal=${idol.isLocal}, id=${idol.id}',
    );

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
        await ref
            .read(sessionControllerProvider.notifier)
            .setCurrentIdolId(idol.id!);

        if (!mounted) return;

        context.goToAchievementIntake(
          idolId: idol.id!,
          targetAge: userAge,
          mentorName: idol.name,
          mentorImageUrl: imageUrlForIdolCandidate(idol),
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
        birthDate: idol.birthDate?.toIso8601String().split(
          'T',
        )[0], // YYYY-MM-DD format
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

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.charcoal.withValues(alpha: 0.50),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          borderRadius: AppRadii.br12,
        ),
        child: Icon(icon, color: Colors.white70, size: 22),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.borderLight),
          bottom: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.h4.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.p16,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.br16,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.08),
              borderRadius: AppRadii.br12,
            ),
            child: Icon(icon, color: AppColors.mint, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.h4.copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s16),
      padding: AppSpacing.p12,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
        borderRadius: AppRadii.br12,
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.error,
          ),
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
        color: AppColors.surface.withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.sm,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CmpysButton(
              label: 'Confirm Strategic Idol',
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
