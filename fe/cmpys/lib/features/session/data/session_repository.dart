import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/session_models.dart';

/// Session repository provider.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(dioClient: ref.watch(dioClientProvider));
});

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
  /// Returns null if no active session exists.
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
    } catch (e) {
      debugPrint('🔍 No active session (error: $e)');
      return null;
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

  /// Select an idol for the session.
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
    String content,
  ) async* {
    debugPrint('💬 Sending interview message to session $sessionId');

    final dio = Dio(
      BaseOptions(
        baseUrl: _dioClient.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    // Inject auth token
    final token = await _dioClient.getAuthToken();
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }

    final response = await dio.post(
      '/sessions/$sessionId/interview',
      data: {'content': content},
    );

    final stream = response.data.stream as Stream<List<int>>;

    await for (final chunk in stream) {
      final text = utf8.decode(chunk);
      for (final line in text.split('\n')) {
        if (line.startsWith('data: ')) {
          try {
            final jsonStr = line.substring(6);
            final event = jsonDecode(jsonStr) as Map<String, dynamic>;
            yield event;
          } catch (e) {
            debugPrint('⚠️ Failed to parse SSE event: $e');
          }
        }
      }
    }
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

    final dio = Dio(
      BaseOptions(
        baseUrl: _dioClient.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    final token = await _dioClient.getAuthToken();
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }

    final response = await dio.post('/sessions/$sessionId/generate-results');

    final stream = response.data.stream as Stream<List<int>>;

    await for (final chunk in stream) {
      final text = utf8.decode(chunk);
      for (final line in text.split('\n')) {
        if (line.startsWith('data: ')) {
          try {
            final jsonStr = line.substring(6);
            final event = jsonDecode(jsonStr) as Map<String, dynamic>;
            yield event;
          } catch (e) {
            debugPrint('⚠️ Failed to parse SSE event: $e');
          }
        }
      }
    }
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

    final dio = Dio(
      BaseOptions(
        baseUrl: _dioClient.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    final token = await _dioClient.getAuthToken();
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }

    final response = await dio.post(
      '/sessions/$sessionId/guided-learning',
      data: {'content': content},
    );

    final stream = response.data.stream as Stream<List<int>>;

    await for (final chunk in stream) {
      final text = utf8.decode(chunk);
      for (final line in text.split('\n')) {
        if (line.startsWith('data: ')) {
          try {
            final jsonStr = line.substring(6);
            final event = jsonDecode(jsonStr) as Map<String, dynamic>;
            yield event;
          } catch (e) {
            debugPrint('⚠️ Failed to parse SSE event: $e');
          }
        }
      }
    }
  }
}
