// Database-first idea cards.
//
// Fetches source-backed catalog quotes first; the backend uses an LLM only to
// fill any remaining capacity. Provenance is mapped through to the UI.
// There is no static fallback: failures surface as errors with retry.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/dio_client.dart';
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
  );
}

/// Loads database-first idea cards via [dio]. Throws when the backend is
/// unreachable or returns nothing — callers show error + retry, never canned
/// quotes. `refresh` asks the backend for additional content.
Future<List<CmpysIdea>> fetchCmpysIdeasFromDio(DioClient dio,
    {bool refresh = false}) async {
  final res = await dio.get(
    '/feed',
    queryParameters: {
      'page_size': 14,
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
  if (ideas.isEmpty) {
    throw StateError('feed returned no quote items');
  }
  return ideas;
}

/// The AI idea feed for Reels / Today.
final cmpysIdeasProvider = FutureProvider<List<CmpysIdea>>((ref) async {
  return fetchCmpysIdeasFromDio(ref.read(dioClientProvider));
});
