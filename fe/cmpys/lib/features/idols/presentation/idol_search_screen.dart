import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_text_field.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/list_tile_card.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../models/idol_models.dart';
import 'idol_visuals.dart';

class IdolSearchScreen extends ConsumerStatefulWidget {
  const IdolSearchScreen({super.key});

  @override
  ConsumerState<IdolSearchScreen> createState() => _IdolSearchScreenState();
}

class _IdolSearchScreenState extends ConsumerState<IdolSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    // Switch to search mode in controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(onboardingControllerProvider.notifier).goToSearch();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    // 600ms debounce for API calls (GET /idols/discover?q=)
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (query.trim().isNotEmpty) {
        setState(() => _hasSearched = true);
        ref.read(onboardingControllerProvider.notifier).searchIdols(query);
      } else {
        setState(() => _hasSearched = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);

    // Listen for errors
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
      body: PrototypeGridBackground(
        gridSize: 20,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CmpysSearchField(
                        controller: _searchController,
                        hint: 'Search titan, domain, or era...',
                        onChanged: _onSearch,
                        autofocus: true,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildResults(onboardingState)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(OnboardingState state) {
    // Show loading
    if (state is OnboardingIdolSearchStep && state.isLoading) {
      return const _SearchThinking();
    }

    // Get results from state
    final results = state is OnboardingIdolSearchStep
        ? state.results
        : <IdolCandidate>[];

    // Not searched yet - show suggestions
    if (!_hasSearched) {
      return _buildSuggestions();
    }

    // No results
    if (results.isEmpty) {
      return NoResultsState(
        query: _searchController.text,
        onClear: () {
          _searchController.clear();
          setState(() => _hasSearched = false);
        },
      );
    }

    // Show results
    return ListView.separated(
      padding: EdgeInsets.only(
        left: AppSpacing.s24,
        right: AppSpacing.s24,
        bottom: AppSpacing.s24,
      ),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s12),
      itemBuilder: (context, index) {
        final idol = results[index];
        return _SearchResultCard(idol: idol, onTap: () => _onSelectIdol(idol));
      },
    );
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: AppSpacing.screenH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Try searching for',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children:
                [
                      'Entrepreneurs',
                      'Scientists',
                      'Athletes',
                      'Artists',
                      'Leaders',
                    ]
                    .map(
                      (term) => GestureDetector(
                        onTap: () {
                          _searchController.text = term;
                          _onSearch(term);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s16,
                            vertical: AppSpacing.s8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.brFull,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(term, style: AppTypography.caption),
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: AppSpacing.s32),
          Text(
            'Popular searches',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          ...['Elon Musk', 'Steve Jobs', 'Albert Einstein'].map(
            (term) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: ListTileCard(
                title: term,
                leading: const ListTileAvatar(
                  icon: 'assets/icons/clock.svg',
                  size: 36,
                ),
                onTap: () {
                  _searchController.text = term;
                  _onSearch(term);
                },
              ),
            ),
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

class _SearchThinking extends StatelessWidget {
  const _SearchThinking();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.p24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.mint.withValues(alpha: 0.3),
                ),
              ),
              padding: AppSpacing.p12,
              child: ClipOval(
                child: Image.network(
                  kPrototypeThinkingAsset,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              'QUERYING_MENTOR_MATCHES',
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.mint,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Searching reliable sources...',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.idol, required this.onTap});

  final IdolCandidate idol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppSpacing.p12,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: AppRadii.br16,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadii.br12,
              child: ColorFiltered(
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
                  imageUrlForIdolCandidate(idol),
                  width: 64,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Image.network(
                    kPrototypeDefaultPortrait,
                    width: 64,
                    height: 76,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(idol.name, style: AppTypography.h4),
                  const SizedBox(height: 4),
                  Text(
                    idolDomainLabel(idol),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'MATCH ${(idol.confidence ?? idol.relevanceScore ?? 0.84) * 100 ~/ 1}%',
                    style: AppTypography.captionUpper.copyWith(
                      color: AppColors.mint,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
