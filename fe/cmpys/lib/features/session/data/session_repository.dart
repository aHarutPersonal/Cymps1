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
  }) async* {
    debugPrint('💬 Sending interview message to session $sessionId');

    final response = await _streamPost('/sessions/$sessionId/interview', {
      'content': content,
      'is_kickoff': isKickoff,
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
