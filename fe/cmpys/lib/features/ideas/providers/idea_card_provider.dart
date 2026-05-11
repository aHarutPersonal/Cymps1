import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/idea_card_repository.dart';
import '../models/idea_card_models.dart';

// =============================================================================
// Ideas Feed Provider — paginated cards for the Ideas tab
// =============================================================================

/// State for the Ideas feed.
class IdeasFeedState {
  final List<IdeaCardModel> cards;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int currentPage;
  final String? activeIdolId;
  final String? activeCategory;

  const IdeasFeedState({
    this.cards = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.currentPage = 1,
    this.activeIdolId,
    this.activeCategory,
  });

  IdeasFeedState copyWith({
    List<IdeaCardModel>? cards,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? currentPage,
    String? activeIdolId,
    String? activeCategory,
  }) {
    return IdeasFeedState(
      cards: cards ?? this.cards,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      activeIdolId: activeIdolId ?? this.activeIdolId,
      activeCategory: activeCategory ?? this.activeCategory,
    );
  }
}

final ideasFeedProvider =
    StateNotifierProvider<IdeasFeedNotifier, IdeasFeedState>((ref) {
      return IdeasFeedNotifier(ref);
    });

class IdeasFeedNotifier extends StateNotifier<IdeasFeedState> {
  IdeasFeedNotifier(this._ref) : super(const IdeasFeedState());

  final Ref _ref;
  static const int _pageSize = 10;

  /// Load ideas for an idol. Resets state if idolId changes.
  Future<void> loadIdeas(String idolId, {String? category}) async {
    if (state.activeIdolId == idolId &&
        state.activeCategory == category &&
        state.cards.isNotEmpty) {
      return; // Already loaded for this idol + category
    }

    state = IdeasFeedState(
      isLoading: true,
      activeIdolId: idolId,
      activeCategory: category,
    );

    try {
      final repo = _ref.read(ideaCardRepositoryProvider);
      final response = await repo.getDailyIdeas(
        idolId: idolId,
        page: 1,
        pageSize: _pageSize,
        category: category,
      );

      if (mounted) {
        state = state.copyWith(
          cards: response.ideaCards,
          isLoading: false,
          hasMore: response.ideaCards.length >= _pageSize,
          currentPage: 1,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  /// Load next page of ideas.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.activeIdolId == null) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final repo = _ref.read(ideaCardRepositoryProvider);
      final nextPage = state.currentPage + 1;
      final response = await repo.getDailyIdeas(
        idolId: state.activeIdolId!,
        page: nextPage,
        pageSize: _pageSize,
        category: state.activeCategory,
      );

      if (mounted) {
        state = state.copyWith(
          cards: [...state.cards, ...response.ideaCards],
          isLoadingMore: false,
          hasMore: response.ideaCards.length >= _pageSize,
          currentPage: nextPage,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isLoadingMore: false);
      }
    }
  }

  /// Force refresh (new LLM generation).
  Future<void> refresh(String idolId) async {
    state = IdeasFeedState(
      isLoading: true,
      activeIdolId: idolId,
      activeCategory: state.activeCategory,
    );

    try {
      final repo = _ref.read(ideaCardRepositoryProvider);
      final response = await repo.getDailyIdeas(
        idolId: idolId,
        page: 1,
        pageSize: _pageSize,
        category: state.activeCategory,
        refresh: true,
      );

      if (mounted) {
        state = state.copyWith(
          cards: response.ideaCards,
          isLoading: false,
          hasMore: response.ideaCards.length >= _pageSize,
          currentPage: 1,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  /// Toggle stash on a card. Optimistic UI update.
  Future<void> toggleStash(String ideaCardId) async {
    // Optimistic toggle
    final idx = state.cards.indexWhere((c) => c.id == ideaCardId);
    if (idx < 0) return;

    final card = state.cards[idx];
    final updatedCards = [...state.cards];
    updatedCards[idx] = card.copyWith(isStashed: !card.isStashed);
    state = state.copyWith(cards: updatedCards);

    try {
      final repo = _ref.read(ideaCardRepositoryProvider);
      await repo.toggleStash(ideaCardId);
      // Also invalidate stash
      _ref.invalidate(stashProvider);
    } catch (_) {
      // Revert on failure
      if (mounted) {
        final revertCards = [...state.cards];
        revertCards[idx] = card;
        state = state.copyWith(cards: revertCards);
      }
    }
  }
}

// =============================================================================
// Stash Provider — user's saved IdeaCards for the Library tab
// =============================================================================

final stashProvider =
    StateNotifierProvider<StashNotifier, AsyncValue<List<IdeaCardModel>>>((
      ref,
    ) {
      return StashNotifier(ref);
    });

class StashNotifier extends StateNotifier<AsyncValue<List<IdeaCardModel>>> {
  StashNotifier(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  /// Load stashed cards.
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(ideaCardRepositoryProvider);
      final response = await repo.getStash(page: 1, pageSize: 50);
      if (mounted) {
        state = AsyncValue.data(response.ideaCards);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Toggle stash on a card and refresh.
  Future<void> toggleStash(String ideaCardId) async {
    try {
      final repo = _ref.read(ideaCardRepositoryProvider);
      await repo.toggleStash(ideaCardId);
      // Remove from local list immediately
      state.whenData((cards) {
        state = AsyncValue.data(
          cards.where((c) => c.id != ideaCardId).toList(),
        );
      });
    } catch (_) {
      // Silent — the card stays visible
    }
  }
}

// =============================================================================
// Syllabus Provider
// =============================================================================

final syllabusProvider = FutureProvider.family<SyllabusResponse, String>((
  ref,
  idolId,
) async {
  final repo = ref.watch(ideaCardRepositoryProvider);
  return repo.getSyllabus(idolId);
});
