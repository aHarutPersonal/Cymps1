import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/feed_repository.dart';
import '../models/feed_models.dart';

/// Cached feed state.
class FeedCache {
  final List<FeedItem> items;
  final bool hasMore;
  final int seed;
  final DateTime fetchedAt;

  const FeedCache({
    required this.items,
    required this.hasMore,
    required this.seed,
    required this.fetchedAt,
  });

  /// Cache is stale after 5 minutes.
  bool get isStale => DateTime.now().difference(fetchedAt).inMinutes >= 5;
}

/// Global feed cache — preloaded when app starts, reused by DiscoverFeedScreen.
final feedCacheProvider =
    StateNotifierProvider<FeedCacheNotifier, AsyncValue<FeedCache>>((ref) {
      return FeedCacheNotifier(ref);
    });

class FeedCacheNotifier extends StateNotifier<AsyncValue<FeedCache>> {
  FeedCacheNotifier(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;
  static const int _pageSize = 10;

  /// Preload feed in background. Safe to call multiple times —
  /// only fetches if no cache or cache is stale.
  Future<void> preload() async {
    final current = state.valueOrNull;
    if (current != null && !current.isStale) return; // already fresh

    try {
      final repo = _ref.read(feedRepositoryProvider);
      final seed = Random().nextInt(999999);
      final response = await repo.getFeed(
        page: 1,
        pageSize: _pageSize,
        seed: seed,
      );
      if (mounted) {
        state = AsyncValue.data(
          FeedCache(
            items: response.items,
            hasMore: response.hasMore,
            seed: seed,
            fetchedAt: DateTime.now(),
          ),
        );
      }
    } catch (e, st) {
      // Don't overwrite existing data on error
      if (state.valueOrNull == null) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Force refresh (pull-to-refresh, etc.)
  Future<void> refresh() async {
    try {
      final repo = _ref.read(feedRepositoryProvider);
      final seed = Random().nextInt(999999);
      final response = await repo.getFeed(
        page: 1,
        pageSize: _pageSize,
        seed: seed,
      );
      if (mounted) {
        state = AsyncValue.data(
          FeedCache(
            items: response.items,
            hasMore: response.hasMore,
            seed: seed,
            fetchedAt: DateTime.now(),
          ),
        );
      }
    } catch (e, st) {
      if (state.valueOrNull == null) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Invalidate cache (e.g. after seed change).
  void invalidate() {
    state = const AsyncValue.loading();
  }
}
