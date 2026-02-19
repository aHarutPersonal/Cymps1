import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../../../core/ui/typewriter_text.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_app_bar.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/thinking_stream.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../models/idol_models.dart';
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
      appBar: CmpysAppBar(
        title: 'Choose Your North Star',
        actions: [
          CmpysAppBarAction(
            icon: AppAssets.iconSearch,
            onPressed: () => context.push(AppRoutes.idolSearch),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(onboardingState),
      ),
    );
  }

  Widget _buildBody(OnboardingState state) {
    if (state is OnboardingIdolSuggestStep && state.isLoading) {
      if (state.jobStatus?.thinkingStream != null) {
        return Padding(
          padding: AppSpacing.p24,
          child: ThinkingStreamWidget(stream: state.jobStatus!.thinkingStream!),
        );
      }
      return const Center(child: LoadingState(message: 'Analyzing the cosmos...'));
    }

    final suggestions = state is OnboardingIdolSuggestStep
        ? state.suggestions
        : <IdolCandidate>[];

    return Column(
      children: [
        // Grid Content
        Expanded(
          child: suggestions.isEmpty 
          ? _buildEmptyState()
          : GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.s20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.s16,
                mainAxisSpacing: AppSpacing.s16,
                childAspectRatio: 0.8, // Taller cards
              ),
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final idol = suggestions[index];
                return IdolGridCard(
                  idol: idol,
                  isSelected: _selectedIdol?.externalId == idol.externalId,
                  onTap: () => setState(() => _selectedIdol = idol),
                );
              },
            ),
        ),

        // Search Prompt if list is not empty (as a footer equivalent in grid? No, stick to bottom or separate)
        // Actually, let's keep the Search for others accessible via AppBar or a sticky bottom area if selection not made?
        // Let's stick "Continue" button at bottom.
        
        Container(
          padding: EdgeInsets.only(
            left: AppSpacing.s24,
            right: AppSpacing.s24,
            bottom: AppSpacing.s24,
            top: AppSpacing.s16,
          ),
          decoration: const BoxDecoration(
            color: AppColors.bg, // Transparent-ish?
            border: Border(top: BorderSide(color: AppColors.border)),
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
                          style: AppTypography.caption.copyWith(color: AppColors.primary, decoration: TextDecoration.underline),
                        ),
                     ),
                   ),

                CmpysButton(
                  label: 'Confirm Selection',
                  onPressed: _selectedIdol != null
                      ? () => _onSelectIdol(_selectedIdol!)
                      : null,
                ),
             ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
     return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'No stars found',
            style: AppTypography.bodyMedium,
          ),
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
