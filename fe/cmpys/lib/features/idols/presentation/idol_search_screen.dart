import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_app_bar.dart';
import '../../../core/ui/cmpys_text_field.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/list_tile_card.dart';
import '../../../core/ui/loading_state.dart';
import '../../onboarding/controllers/onboarding_controller.dart';
import '../models/idol_models.dart';

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
    // 300ms debounce for API calls (GET /idols/discover?q=)
    _debounce = Timer(const Duration(milliseconds: 300), () {
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
      appBar: const CmpysAppBar(title: 'Search Idols'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.screenH,
              child: CmpysSearchField(
                controller: _searchController,
                hint: 'Search by name or profession...',
                onChanged: _onSearch,
                autofocus: true,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Expanded(
              child: _buildResults(onboardingState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(OnboardingState state) {
    // Show loading
    if (state is OnboardingIdolSearchStep && state.isLoading) {
      return const LoadingState(message: 'Searching...');
    }

    // Get results from state
    final results = state is OnboardingIdolSearchStep ? state.results : <IdolCandidate>[];

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
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
      itemBuilder: (context, index) {
        final idol = results[index];
        return IdolCard(
          name: idol.name,
          initials: _getInitials(idol.name),
          subtitle: idol.occupations.isNotEmpty ? idol.occupations.first : null,
          imageUrl: idol.avatarThumbUrl,
          onTap: () => _onSelectIdol(idol),
        );
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
            children: [
              'Entrepreneurs',
              'Scientists',
              'Athletes',
              'Artists',
              'Leaders',
            ]
                .map((term) => GestureDetector(
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
                        child: Text(
                          term,
                          style: AppTypography.caption,
                        ),
                      ),
                    ))
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
          ...['Elon Musk', 'Steve Jobs', 'Albert Einstein'].map((term) => Padding(
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
              )),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first.substring(0, 2).toUpperCase();
  }

  void _onSelectIdol(IdolCandidate idol) {
    ref.read(onboardingControllerProvider.notifier).selectIdol(idol);
    context.goToIdolConfirm(idol);
  }
}
