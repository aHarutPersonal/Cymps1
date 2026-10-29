import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_client.dart';
import '../models/session_models.dart';

/// Session repository provider.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(dioClient: ref.watch(dioClientProvider));
});

/// The longest [idolTimelineProvider] waits for its two requests; after it
/// the load fails (the Record falls back to the seeded ledger).
const idolTimelineTimeout = Duration(seconds: 8);

/// How long a loaded [idolTimelineProvider] result is kept after its last
/// listener goes, so reopening the Record or the Mentor screen doesn't
/// fetch again. Failures aren't kept.
const idolTimelineCacheFor = Duration(minutes: 5);

/// A catalog mentor's documented timeline ([SessionRepository.idolTimeline]),
/// keyed by the mentor's name. Shared by the mentor timeline widget and the
/// Record; `ref.invalidate` it to retry (that always fetches again).
final idolTimelineProvider = FutureProvider.autoDispose
    .family<List<IdolTimelineEntry>, String>((ref, idolName) async {
      var disposed = false;
      Timer? cache;
      ref.onDispose(() {
        disposed = true;
        cache?.cancel();
      });
      final rows = await ref
          .watch(sessionRepositoryProvider)
          .idolTimeline(idolName)
          .timeout(idolTimelineTimeout);
      if (!disposed) {
        final link = ref.keepAlive();
        cache = Timer(idolTimelineCacheFor, link.close);
      }
      return rows;
    });

/// The agentic-session flow refers to the repository by this name.
typedef AgenticSessionRepository = SessionRepository;

/// Thrown when an SSE stream ends without a terminal `done`/`error` event —
/// i.e. the socket dropped mid-generation. Callers treat this as a failure and
/// offer retry, so a truncated comparison/blueprint/interview is never shown
/// or persisted as if it were complete.
class SseIncompleteException implements Exception {
  const SseIncompleteException();

  @override
  String toString() =>
      'The response ended before it finished. Check your connection and try again.';
}

/// Robustly parse a raw SSE byte stream into `data:` JSON events.
///
/// Fixes two silent data-loss defects of a naive per-chunk parser:
/// - **Split multibyte chars:** decodes UTF-8 *statefully* with
///   `allowMalformed`, so an accented name / em-dash / emoji straddling a chunk
///   boundary is reassembled instead of throwing and dropping the chunk.
/// - **Split `data:` lines:** `LineSplitter` buffers a partial line across
///   chunks, so a `data:` line split across TCP packets is reassembled rather
///   than failing `jsonDecode` and vanishing.
///
/// Malformed `data:` payloads are skipped (logged), not fatal. Completion
/// semantics are intentionally NOT enforced here — see [SessionRepository]'s
/// completion guard — so this stays a pure, testable decoder.
Stream<Map<String, dynamic>> parseSseEvents(Stream<List<int>> stream) async* {
  // `.cast<List<int>>()` is essential: Dio hands back a Stream<Uint8List> and
  // the Utf8Decoder transformer is typed for List<int>. Without the cast,
  // `.transform` does a runtime type check of the transformer against
  // StreamTransformer<Uint8List, …> and throws "Utf8Decoder is not a subtype".
  final lines = stream
      .cast<List<int>>()
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  await for (final line in lines) {
    if (!line.startsWith('data:')) continue;
    final jsonStr = line.substring(5).trim();
    if (jsonStr.isEmpty) continue;
    try {
      yield jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ Failed to parse SSE event: $e');
    }
  }
}

/// Parse an SSE response and finish as soon as its terminal event arrives.
///
/// A valid `done` must not depend on a later clean TCP close: mobile networks
/// and proxies may reset an already-complete socket. Waiting for EOF would
/// turn a complete mentor reply into a false "cut off" error.
Stream<Map<String, dynamic>> parseCompletedSseEvents(
  Stream<List<int>> stream,
) async* {
  await for (final event in parseSseEvents(stream)) {
    final type = event['type'];
    yield event;
    if (type == 'done' || type == 'error') return;
  }
  throw const SseIncompleteException();
}

/// Repository for the 5-phase agentic session workflow.
///
/// Handles all API communication for:
/// - Session creation and management
/// - Idol suggestion and selection
/// - Interview SSE streaming
/// - Comparison + Blueprint result generation
class SessionRepository {
  Future<List<Map<String, dynamic>>> discoverMentors(String query) async {
    final response = await _dioClient.get('/idols/discover', queryParameters: {'q': query, 'limit': 10});
    return (response.data['candidates'] as List)
        .map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }

  /// "Prepare profile": queue a research job for a person who is not in the
  /// library yet. `POST /idols/import` returns at once with the queued job; the
  /// worker drafts the profile, and it is checked before it is published.
  Future<IdolImportResult> importIdol(String name) async {
    var clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length > _maxImportNameLength) {
      clean = clean.substring(0, _maxImportNameLength).trimRight();
    }
    final response = await _dioClient.post(
      '/idols/import',
      data: {
        'provider': 'llm',
        'externalId': 'llm:${_slug(clean)}',
        'name': clean,
      },
    );
    return IdolImportResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// The documented timeline for a catalog mentor, found by name.
  ///
  /// Suggestions carry no catalog id, so the published idol is looked up with
  /// `GET /idols/search` (exact name or alias) and its events are read from
  /// `GET /idols/{id}/timeline`. An idol that is not in the catalog, or has no
  /// event with a known age, gives an empty list.
  ///
  /// Only an unambiguous match counts: when two catalog idols share the name
  /// (homonyms), or the search page could not hold every match, the result
  /// is empty rather than another person's timeline.
  Future<List<IdolTimelineEntry>> idolTimeline(String idolName) async {
    final wanted = _fold(idolName);
    if (wanted.isEmpty) return const [];
    // The search is a substring match with no ordering, so ask for the
    // server's largest page: a short page could cut the exact match off.
    final search = await _dioClient.get(
      '/idols/search',
      queryParameters: {'q': idolName.trim(), 'limit': _idolSearchLimit},
    );
    final rows = search.data['idols'] as List? ?? const [];
    final total = (search.data['total'] as num?)?.toInt() ?? rows.length;
    if (total > rows.length) return const [];
    final matches = <String>{};
    for (final raw in rows) {
      final idol = Map<String, dynamic>.from(raw as Map);
      final names = [
        idol['name']?.toString() ?? '',
        for (final alias in (idol['aliases'] as List? ?? const []))
          (alias as Map)['alias_text']?.toString() ?? '',
      ];
      final id = idol['id']?.toString() ?? '';
      if (id.isNotEmpty && names.any((n) => _fold(n) == wanted)) {
        matches.add(id);
      }
    }
    if (matches.length != 1) return const [];
    final idolId = matches.single;

    final response = await _dioClient.get(
      '/idols/$idolId/timeline',
      queryParameters: {'limit': 50},
    );
    final entries = <IdolTimelineEntry>[];
    for (final raw in (response.data['events'] as List? ?? const [])) {
      final event = Map<String, dynamic>.from(raw as Map);
      final age = event['ageAtEvent'];
      if (age is! num) continue;
      final title = (event['canonicalTitle']?.toString() ?? '').trim();
      final text = title.isNotEmpty
          ? title
          : (event['canonicalDescription']?.toString() ?? '').trim();
      if (text.isEmpty) continue;
      final id = event['id']?.toString().trim() ?? '';
      final category = event['category']?.toString().trim() ?? '';
      entries.add(
        IdolTimelineEntry(
          age: age.toInt(),
          text: text,
          id: id.isEmpty ? null : id,
          category: category.isEmpty ? null : category,
        ),
      );
    }
    return entries;
  }

  /// Idol names are stored in a 255-character column; stay well inside it.
  static const _maxImportNameLength = 120;

  /// `GET /idols/search`'s largest page.
  static const _idolSearchLimit = 100;

  static String _fold(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// `llm:` external ids are the name in snake case, as the catalog's other
  /// model-sourced rows are (`llm:elon_musk`). Letters of any script are kept,
  /// so two different names never share an id.
  static String _slug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isNotEmpty) return slug;
    // Nothing but symbols: hex of the text still keeps distinct names apart.
    return name.codeUnits.map((c) => c.toRadixString(16)).join('_');
  }

  Future<List<Map<String, dynamic>>> learningMessages(String sessionId) async {
    final response = await _dioClient.get('/sessions/$sessionId/guided-learning/messages');
    return (response.data['messages'] as List)
        .map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }

  SessionRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// POST a request that streams its response (SSE), routed through the shared
  /// authenticated Dio so it gets the Bearer token AND the refresh-on-401
  /// interceptor — a fresh Dio would 401 the moment the access token expired
  /// mid-session (e.g. between select-idol and the interview) with no way to
  /// recover.
  Future<Response<dynamic>> _streamPost(String path, Object data) {
    return _dioClient.post<dynamic>(
      path,
      data: data,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        // The server/provider deadline is 60 seconds. Keep enough margin to
        // receive its terminal SSE error instead of racing it with Dio's
        // shared 60-second timeout.
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
  }

  /// Wrap [parseSseEvents] with a completion guard: if the stream ends without
  /// a terminal `done`/`error` event (socket dropped mid-generation), throw
  /// [SseIncompleteException] so the caller retries and never treats a
  /// truncated comparison/blueprint/interview as final.
  Stream<Map<String, dynamic>> _sseWithCompletion(
    Stream<List<int>> stream,
  ) async* {
    yield* parseCompletedSseEvents(stream);
  }

  // ===========================================================================
  // Session Lifecycle
  // ===========================================================================

  /// Create a new agentic session.
  ///
  /// Returns the newly created [Session] in 'idol_selection' phase.
  Future<Session> createSession(SessionCreateRequest request) async {
    debugPrint('🚀 Creating agentic session');

    final response = await _dioClient.post('/sessions', data: request.toJson());

    debugPrint('🚀 Session created: ${response.data}');
    return Session.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get session state by ID.
  Future<Session> getSession(String sessionId) async {
    debugPrint('📖 Getting session: $sessionId');

    final response = await _dioClient.get('/sessions/$sessionId');

    return Session.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get the user's current active (non-completed) session.
  ///
  /// Returns null ONLY when the server authoritatively says there is no active
  /// session (200 with a null body, or 404). A transient failure (5xx, network)
  /// is re-thrown rather than masked as "no session" — otherwise a hiccup is
  /// indistinguishable from a real absence, and a caller that reconciles local
  /// state could wrongly treat a blip as "the user has nothing" and drop their
  /// mentor/results. Callers that just want best-effort hydration already wrap
  /// this in try/catch and keep their existing state on throw.
  Future<Session?> getCurrentSession() async {
    debugPrint('🔍 Checking for active session');

    try {
      final response = await _dioClient.get('/sessions/current');
      if (response.data == null) {
        debugPrint('🔍 No active session');
        return null;
      }
      debugPrint('🔍 Active session found');
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.statusCode == 404) {
        debugPrint('🔍 No active session (404)');
        return null;
      }
      // Ambiguous failure — do not pretend the user has no session.
      debugPrint('🔍 /sessions/current failed transiently: ${e.message}');
      rethrow;
    }
  }

  /// Get the user's newest session, including completed onboarding.
  ///
  /// This is distinct from [getCurrentSession], which is only for resuming an
  /// unfinished onboarding flow. Post-onboarding hydration and plan recovery
  /// need the completed session's blueprint, scores, and selected mentor.
  Future<Session?> getLatestSession() async {
    debugPrint('🔍 Loading latest session');
    final response = await _dioClient.get('/sessions/latest');
    if (response.data == null) return null;
    return Session.fromJson(response.data as Map<String, dynamic>);
  }

  /// Reset and enqueue a bounded retry after comparison scoring reaches a
  /// terminal failure. Ordinary polling never creates duplicate attempts.
  Future<Session> retryComparisonScores(String sessionId) async {
    final response = await _dioClient.post(
      '/sessions/$sessionId/comparison-scores/retry',
    );
    return Session.fromJson(response.data as Map<String, dynamic>);
  }

  /// Abandon the user's current in-progress session so a fresh one can start.
  /// Best-effort: the backend rejects a second active session, so we clear the
  /// current one server-side when the endpoint is available and ignore the
  /// absence of one (older backends supersede on next create).
  Future<void> abandonCurrentSession() async {
    final session = await getCurrentSession();
    if (session == null) return;
    try {
      await _dioClient.post('/sessions/${session.id}/abandon');
    } catch (e) {
      debugPrint('🗑️ abandonCurrentSession best-effort: $e');
    }
  }

  // ===========================================================================
  // Idol Suggestion & Selection
  // ===========================================================================

  /// Get 3 idol suggestions based on session intake data.
  Future<List<IdolSuggestion>> suggestIdols(String sessionId) async {
    debugPrint('🎯 Requesting idol suggestions for session $sessionId');

    final response = await _dioClient.post(
      '/sessions/$sessionId/suggest-idols',
    );

    final data = response.data as Map<String, dynamic>;
    final suggestionsRaw = data['suggestions'] as List? ?? [];

    return suggestionsRaw
        .whereType<Map<String, dynamic>>()
        .map((e) => IdolSuggestion.fromJson(e))
        .toList();
  }

  /// Choose the mentor for the session.
  ///
  /// Transitions session to 'interview' phase.
  Future<Session> selectIdol(
    String sessionId,
    SelectIdolRequest request,
  ) async {
    debugPrint('✨ Selecting idol "${request.idolName}" for session $sessionId');

    final response = await _dioClient.post(
      '/sessions/$sessionId/select-idol',
      data: request.toJson(),
    );

    return Session.fromJson(response.data as Map<String, dynamic>);
  }

  // ===========================================================================
  // Interview (SSE)
  // ===========================================================================

  /// Send a message during the interview phase.
  ///
  /// Returns a stream of SSE events. Each event is a Map with:
  /// - `type`: 'chunk' | 'done' | 'error'
  /// - `content`: text chunk (for type='chunk')
  /// - `turn`: current turn number (for type='done')
  /// - `phase_transition`: bool (for type='done')
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
    String? questionId,
    bool missingEvidence = false,
  }) async* {
    debugPrint('💬 Sending interview message to session $sessionId');

    final response = await _streamPost('/sessions/$sessionId/interview', {
      'content': content,
      'is_kickoff': isKickoff,
      if (questionId != null) 'question_id': questionId,
      // The learner picked the question's "I don't have one yet" option:
      // planning records missing evidence rather than a self-report.
      if (missingEvidence) 'missing_evidence': true,
    });

    final stream = response.data.stream as Stream<List<int>>;

    yield* _sseWithCompletion(stream);
  }

  // ===========================================================================
  // Results Generation (SSE) — Phase 4–5
  // ===========================================================================

  /// Start generating comparison + blueprint via SSE.
  ///
  /// Returns a stream of SSE events. Each event is a Map with:
  /// - `type`: 'section' | 'chunk' | 'done' | 'error'
  /// - `section`: 'comparison' | 'blueprint' (for type='section')
  /// - `content`: text chunk (for type='chunk')
  Stream<Map<String, dynamic>> generateResults(String sessionId) async* {
    debugPrint('🔥 Starting results generation for session $sessionId');

    final response = await _streamPost(
      '/sessions/$sessionId/generate-results',
      const <String, dynamic>{},
    );

    final stream = response.data.stream as Stream<List<int>>;

    yield* _sseWithCompletion(stream);
  }

  // ===========================================================================
  // Guided Learning (Phase 6)
  // ===========================================================================

  /// Fetch curated learning materials for a specific blueprint topic.
  Future<List<LearningMaterial>> fetchLearningMaterials(
    String sessionId,
    String topic,
  ) async {
    debugPrint('📚 Fetching learning materials for topic: $topic');

    final response = await _dioClient.post(
      '/sessions/$sessionId/learning-materials',
      data: {'topic': topic},
    );

    final data = response.data as Map<String, dynamic>;
    final materialsRaw = data['materials'] as List? ?? [];

    return materialsRaw
        .whereType<Map<String, dynamic>>()
        .map((e) => LearningMaterial.fromJson(e))
        .toList();
  }

  /// Fetch the personalized Daily Insights feed.
  Future<DailyFeedResponse> fetchDailyFeed(String sessionId) async {
    debugPrint('📰 Fetching daily feed for session: $sessionId');

    final response = await _dioClient.get('/sessions/$sessionId/feed');

    return DailyFeedResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Send a message during the guided learning phase.
  /// Streams back the tutor's response using LearnLM.
  Stream<Map<String, dynamic>> sendGuidedLearningMessage(
    String sessionId,
    String content,
  ) async* {
    debugPrint('🎓 Sending guided learning message to session $sessionId');

    final response = await _streamPost('/sessions/$sessionId/guided-learning', {
      'content': content,
    });

    final stream = response.data.stream as Stream<List<int>>;

    yield* _sseWithCompletion(stream);
  }
}
