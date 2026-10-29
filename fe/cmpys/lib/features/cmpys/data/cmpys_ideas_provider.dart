// Database-first idea cards.
//
// Fetches source-backed catalog quotes first; the backend uses an LLM only to
// fill any remaining capacity. Provenance is mapped through to the UI.
// There is no static fallback: failures surface as errors with retry.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/controllers/session_controller.dart';
import 'cmpys_seed.dart';

const _tonePalette = <Color>[
  AppColors.green,
  AppColors.lilac,
  AppColors.blue,
  AppColors.clay,
  AppColors.pink,
  AppColors.mint,
  AppColors.ochre,
  AppColors.blkInk,
];

Color _toneFor(String key) {
  if (key.isEmpty) return AppColors.green;
  final idx = key.codeUnits.fold<int>(0, (a, b) => a + b) % _tonePalette.length;
  return _tonePalette[idx];
}

String _cleanQuote(String s) {
  var t = s.trim();
  // Normalise smart quotes and strip a single wrapping pair.
  t = t.replaceAll('“', '"').replaceAll('”', '"').replaceAll('’', '\'');
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    t = t.substring(1, t.length - 1).trim();
  }
  return t;
}

/// Maps a raw `/feed` quote item to a [CmpysIdea].
CmpysIdea? _ideaFromFeedItem(Map<String, dynamic> m) {
  if ((m['type'] ?? 'quote') != 'quote') return null;
  final text = _cleanQuote((m['content'] ?? m['title'] ?? '').toString());
  if (text.isEmpty) return null;
  final id = (m['id'] ?? text.hashCode).toString();
  final category = (m['category'] ?? 'Idea').toString();
  return CmpysIdea(
    id: id,
    text: text,
    author: (m['speaker'] ?? m['source'] ?? 'Unknown').toString(),
    tag: category,
    tone: _toneFor(category),
    likes: (m['like_count'] as num?)?.toInt() ?? 0,
    comments: const [],
    isSourced: m['is_sourced'] == true,
    isVerified: m['is_verified'] == true,
    sourceUrl: m['source_url']?.toString(),
    sourceTitle: m['source_title']?.toString(),
    sourceReference: m['source_reference']?.toString(),
    quoteType: m['quote_type']?.toString(),
    verificationLevel: m['verification_level']?.toString(),
  );
}

/// One page of `/feed` idea cards and whether the feed has more pages.
///
/// The backend shuffles its pool with a per-day seed, so pages are stable
/// within a day. `refresh` asks it to generate new content (paid LLM calls),
/// so callers page through the existing feed first. Never throws for an
/// empty page.
Future<({List<CmpysIdea> ideas, bool hasMore})> fetchCmpysIdeasPage(
  DioClient dio, {
  int page = 1,
  bool refresh = false,
}) async {
  final res = await dio.get(
    '/feed',
    queryParameters: {
      'page_size': 14,
      if (page > 1) 'page': page,
      if (refresh) 'refresh': true,
    },
  );
  final data = res.data;
  final items = (data is Map ? data['items'] : null) as List? ?? const [];
  final ideas = items
      .whereType<Map>()
      .map((m) => _ideaFromFeedItem(m.cast<String, dynamic>()))
      .whereType<CmpysIdea>()
      .toList();
  return (ideas: ideas, hasMore: data is Map && data['has_more'] == true);
}

/// Loads database-first idea cards via [dio]. Throws when the backend is
/// unreachable or returns nothing — callers show error + retry, never canned
/// quotes. `refresh` asks the backend for additional content.
Future<List<CmpysIdea>> fetchCmpysIdeasFromDio(DioClient dio,
    {bool refresh = false}) async {
  final page = await fetchCmpysIdeasPage(dio, refresh: refresh);
  if (page.ideas.isEmpty) {
    throw StateError('feed returned no quote items');
  }
  return page.ideas;
}

/// Wall clock for the idea feed: the day boundary below and the reels'
/// double-tap timing. Tests override it with the fake test clock.
final cmpysIdeasClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

String _localDay(DateTime t) => '${t.year}-${t.month}-${t.day}';

/// The AI idea feed for Reels / Today.
///
/// When the app resumes on a different local day than the feed was loaded,
/// the provider reloads itself: the plain `/feed` read (never
/// `refresh=true`) brings the new day's order and newly published quotes.
/// A load that failed (offline after midnight, say) retries on the next
/// resume, so yesterday's list never sticks for the whole day.
///
/// The feed belongs to the signed-in account: it reloads when the account
/// changes (a sign-out, or another account signing in), so a new account
/// never sees the previous one's ideas.
final cmpysIdeasProvider = FutureProvider<List<CmpysIdea>>((ref) async {
  ref.watch(currentUserProvider.select((user) => user?.id));
  final now = ref.read(cmpysIdeasClockProvider);
  String? loadedOn; // set only once the fetch succeeds
  var failed = false;
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final stale = loadedOn != null && _localDay(now()) != loadedOn;
      if (failed || stale) ref.invalidateSelf();
    },
  );
  ref.onDispose(lifecycle.dispose);
  try {
    final ideas = await fetchCmpysIdeasFromDio(ref.read(dioClientProvider));
    loadedOn = _localDay(now());
    return ideas;
  } catch (_) {
    failed = true;
    rethrow;
  }
});
