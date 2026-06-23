import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/chat_models.dart';

/// Chat repository provider.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for chat operations.
class ChatRepository {
  ChatRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Create a new chat thread with an idol.
  ///
  /// [idolId] - The idol's unique identifier.
  /// Returns the created [ChatThread].
  Future<ChatThread> createThread(String idolId) async {
    final response = await _dioClient.post(
      '/chat/threads',
      data: {'idolId': idolId}, // Backend expects camelCase
    );
    return ChatThread.fromJson(response.data);
  }

  /// Get all chat threads for the user.
  ///
  /// [limit] - Maximum number of threads to return.
  /// [offset] - Pagination offset.
  /// Returns a [ThreadsListResponse] with threads.
  Future<ThreadsListResponse> getThreads({int? limit, int? offset}) async {
    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _dioClient.get(
      '/chat/threads',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    // Handle both list and object responses
    if (response.data is List) {
      return ThreadsListResponse(
        threads: (response.data as List)
            .map((json) => ChatThread.fromJson(json as Map<String, dynamic>))
            .toList(),
      );
    }

    return ThreadsListResponse.fromJson(response.data);
  }

  /// Get a specific chat thread with messages.
  ///
  /// [threadId] - The thread's unique identifier.
  /// Returns the [ChatThread].
  Future<ChatThread> getThread(String threadId) async {
    final response = await _dioClient.get('/chat/threads/$threadId');
    return ChatThread.fromJson(response.data);
  }

  /// Get messages for a thread.
  ///
  /// [threadId] - The thread's unique identifier.
  /// [limit] - Maximum number of messages to return.
  /// [before] - Get messages before this message ID (for pagination).
  /// Returns a [MessagesListResponse] with messages.
  Future<MessagesListResponse> getMessages(
    String threadId, {
    int? limit,
    String? before,
  }) async {
    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (before != null) queryParams['before'] = before;

    final response = await _dioClient.get(
      '/chat/threads/$threadId/messages',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    // Handle both list and object responses
    if (response.data is List) {
      return MessagesListResponse(
        messages: (response.data as List)
            .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
            .toList(),
      );
    }

    return MessagesListResponse.fromJson(response.data);
  }

  /// Send a message in a thread.
  ///
  /// [threadId] - The thread's unique identifier.
  /// [message] - The message content.
  /// Returns a [SendMessageResponse] with the reply.
  ///
  /// API: POST /chat/threads/{thread_id}/messages
  Future<SendMessageResponse> sendMessage(
    String threadId,
    String message,
  ) async {
    final request = SendMessageRequest(content: message);

    debugPrint('💬 Sending message: ${request.toJson()}');

    final response = await _dioClient.post(
      '/chat/threads/$threadId/messages',
      data: request.toJson(),
    );

    debugPrint('💬 Chat response: ${response.data}');

    final parsed = SendMessageResponse.fromJson(response.data);
    debugPrint('💬 Parsed reply: "${parsed.reply}"');
    debugPrint('💬 Assistant message: ${parsed.assistantMessage?.content}');

    return parsed;
  }

  /// Send a message with real-time streaming response.
  ///
  /// Returns a stream of content chunks as they arrive.
  /// The stream yields individual text chunks, with a final empty chunk
  /// and messageId when complete.
  ///
  /// API: POST /chat/threads/{thread_id}/messages/stream (SSE)
  Stream<StreamChatEvent> sendMessageStream(
    String threadId,
    String message,
  ) async* {
    debugPrint('💬 Streaming message to thread: $threadId');

    // Helper to make the stream request
    Future<HttpClientResponse> makeRequest(String? authToken) async {
      final uri = Uri.parse(
        '${_dioClient.baseUrl}/chat/threads/$threadId/messages/stream',
      );
      debugPrint('💬 Making request to: $uri');
      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'text/event-stream');
      if (authToken != null) {
        request.headers.set('Authorization', 'Bearer $authToken');
        debugPrint('💬 Auth header set');
      } else {
        debugPrint('💬 WARNING: No auth token!');
      }
      final jsonBody = jsonEncode({'content': message});
      // Use add() with utf8 encoding instead of write() to handle all characters properly
      request.add(utf8.encode(jsonBody));
      debugPrint('💬 Request body written, calling close()...');
      return request.close();
    }

    try {
      // First attempt
      var token = await _dioClient.getAuthToken();
      debugPrint(
        '💬 Got token: ${token != null ? "${token.substring(0, 20)}..." : "NULL"}',
      );

      HttpClientResponse response;
      try {
        response = await makeRequest(token);
        debugPrint('💬 First request response: ${response.statusCode}');
      } catch (e) {
        debugPrint('💬 First request FAILED: $e');
        yield StreamChatEvent.error('Connection failed: $e');
        return;
      }

      // If 401, trigger a token refresh via a dummy Dio call and retry
      if (response.statusCode == 401) {
        debugPrint('💬 Got 401, refreshing token...');
        try {
          // This Dio call will trigger the refresh interceptor
          await _dioClient.get('/me');
          debugPrint('💬 Refresh trigger call succeeded');
        } catch (e) {
          // Ignore - we just want to trigger refresh
          debugPrint('💬 Refresh trigger call error (expected): $e');
        }

        // Get the fresh token (may have been refreshed by the interceptor)
        token = await _dioClient.getAuthToken();
        debugPrint('💬 Retrying stream with refreshed token...');
        try {
          response = await makeRequest(token);
          debugPrint('💬 Retry response: ${response.statusCode}');
        } catch (e) {
          debugPrint('💬 Retry request FAILED: $e');
          yield StreamChatEvent.error('Retry failed: $e');
          return;
        }
      }

      if (response.statusCode != 200) {
        debugPrint('💬 Non-200 status: ${response.statusCode}');
        yield StreamChatEvent.error('HTTP ${response.statusCode}');
        return;
      }

      debugPrint('💬 Starting to read SSE stream...');
      await for (final chunk in response.transform(utf8.decoder)) {
        // Parse SSE format: "data: {...}\n\n"
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              final jsonStr = line.substring(6);
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;

              final type = data['type'] as String?;
              if (type == 'chunk') {
                yield StreamChatEvent.chunk(data['content'] as String? ?? '');
              } else if (type == 'done') {
                debugPrint('💬 Stream done!');
                yield StreamChatEvent.done(
                  messageId: data['messageId'] as String?,
                  userMessageId: data['userMessageId'] as String?,
                  suggestedActions: SendMessageResponse.parseSuggestedActions(
                    data['suggestedActions'] ?? data['suggested_actions'],
                  ),
                  followUpQuestions: SendMessageResponse.parseStringList(
                    data['followUpQuestions'] ?? data['follow_up_questions'],
                  ),
                );
              } else if (type == 'error') {
                debugPrint('💬 Server sent error: ${data['error']}');
                yield StreamChatEvent.error(
                  data['error'] as String? ?? 'Unknown error',
                );
              }
            } catch (e) {
              debugPrint('💬 Failed to parse SSE: $e');
            }
          }
        }
      }
      debugPrint('💬 SSE stream finished');
    } catch (e, stack) {
      debugPrint('💬 FATAL ERROR in sendMessageStream: $e');
      debugPrint('💬 Stack: $stack');
      yield StreamChatEvent.error('Fatal: $e');
    }
  }

  /// Send a message and create a thread if needed.
  ///
  /// [idolId] - The idol's unique identifier.
  /// [message] - The message content.
  /// [threadId] - Optional existing thread ID.
  /// Returns a [SendMessageResponse] with the reply.
  Future<SendMessageResponse> sendMessageToIdol(
    String idolId,
    String message, {
    String? threadId,
  }) async {
    if (threadId != null) {
      return sendMessage(threadId, message);
    }

    // Create new thread and send message
    final thread = await createThread(idolId);
    return sendMessage(thread.id, message);
  }

  /// Delete a chat thread.
  Future<void> deleteThread(String threadId) async {
    await _dioClient.delete('/chat/threads/$threadId');
  }

  /// Get or create a thread for an idol.
  Future<ChatThread> getOrCreateThread(String idolId) async {
    // First try to find existing thread
    final threads = await getThreads();
    final existing = threads.threads.where((t) => t.idolId == idolId).toList();

    if (existing.isNotEmpty) {
      return existing.first;
    }

    // Create new thread
    return createThread(idolId);
  }
}
