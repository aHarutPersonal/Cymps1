import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../app/env.dart';

part 'chat_models.freezed.dart';

/// Helper to resolve relative backend image URLs to absolute URLs based on environment
String? _resolveImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http')) return url;

  // Format: /api/v1/media/... -> replace with Env.apiBaseUrl + /media/... or whatever
  // The Env.apiBaseUrl already has /api/v1 so we need to be careful
  if (url.startsWith('/api/v1')) {
    final path = url.replaceFirst('/api/v1', '');
    return '${Env.apiBaseUrl}$path';
  }

  // If we just got /media/... but the base URL has /api/v1
  // For safety, let's construct it cleanly based on what Env provides
  if (url.startsWith('/')) {
    // Determine if Env.apiBaseUrl already has /api/v1. If it does, we typically strip it
    // to map directly to the root for media files which FastAPI usually mounts at /media or /api/v1/media.
    // In our backend, media is mounted at /api/v1/media.

    // Simplest logic: just ensure we don't duplicate host/port
    final baseUrl = Env.apiBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), '');
    return '$baseUrl$url';
  }
  return url;
}

/// A chat message.
@freezed
class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  const factory ChatMessage({
    required String id,
    required String role,
    required String content,
    required DateTime createdAt,
    String? threadId,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt:
          _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      threadId: (json['threadId'] ?? json['thread_id'])?.toString(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Check if message is from user.
  bool get isUser => role == 'user';

  /// Check if message is from assistant.
  bool get isAssistant => role == 'assistant';
}

/// A chat thread.
@freezed
class ChatThread with _$ChatThread {
  const ChatThread._();

  const factory ChatThread({
    required String id,
    required String idolId,
    required DateTime createdAt,
    DateTime? updatedAt,
    ChatMessage? lastMessage,
    @Default(0) int messageCount,
    String? title,
    String? idolName,
    String? idolImageUrl,
    List<ChatMessage>? messages,
  }) = _ChatThread;

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: (json['id'] ?? '').toString(),
      idolId: (json['idolId'] ?? json['idol_id'] ?? '').toString(),
      createdAt:
          _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      lastMessage: json['lastMessage'] != null || json['last_message'] != null
          ? ChatMessage.fromJson(
              (json['lastMessage'] ?? json['last_message'])
                  as Map<String, dynamic>,
            )
          : null,
      messageCount:
          (json['messageCount'] ?? json['message_count'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      idolName: (json['idolName'] ?? json['idol_name'])?.toString(),
      idolImageUrl: _resolveImageUrl(
        (json['idolImageUrl'] ??
                json['idol_image_url'] ??
                json['idolImage'] ??
                json['idol_image'])
            ?.toString(),
      ),
      messages: _parseMessagesList(json['messages']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<ChatMessage>? _parseMessagesList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Suggested action from chat response.
@freezed
class SuggestedAction with _$SuggestedAction {
  const factory SuggestedAction({
    required String type,
    required String label,
    Map<String, dynamic>? payload,
  }) = _SuggestedAction;

  factory SuggestedAction.fromJson(Map<String, dynamic> json) {
    return SuggestedAction(
      type: (json['type'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}

/// Response from sending a message.
@freezed
class SendMessageResponse with _$SendMessageResponse {
  const factory SendMessageResponse({
    required String reply,
    double? confidence,
    @Default(false) bool disclaimerIncluded,
    List<String>? followUpQuestions,
    List<SuggestedAction>? suggestedActions,
    String? messageId,
    String? threadId,
    ChatMessage? userMessage,
    ChatMessage? assistantMessage,
    String? disclaimer,
  }) = _SendMessageResponse;

  factory SendMessageResponse.fromJson(Map<String, dynamic> json) {
    // Parse assistant message first to extract reply if needed
    ChatMessage? assistantMsg;
    final assistantData = json['assistantMessage'] ?? json['assistant_message'];
    if (assistantData != null && assistantData is Map<String, dynamic>) {
      assistantMsg = ChatMessage.fromJson(assistantData);
    }

    // Parse user message
    ChatMessage? userMsg;
    final userData = json['userMessage'] ?? json['user_message'];
    if (userData != null && userData is Map<String, dynamic>) {
      userMsg = ChatMessage.fromJson(userData);
    }

    // Get reply - try 'reply' field first, then fall back to assistantMessage.content
    String reply = '';
    if (json['reply'] != null && json['reply'].toString().isNotEmpty) {
      reply = json['reply'].toString();
    } else if (assistantMsg != null && assistantMsg.content.isNotEmpty) {
      reply = assistantMsg.content;
    }

    return SendMessageResponse(
      reply: reply,
      confidence: (json['confidence'] as num?)?.toDouble(),
      disclaimerIncluded:
          json['disclaimerIncluded'] == true ||
          json['disclaimer_included'] == true,
      followUpQuestions: parseStringList(
        json['followUpQuestions'] ?? json['follow_up_questions'],
      ),
      suggestedActions: parseSuggestedActions(
        json['suggestedActions'] ?? json['suggested_actions'],
      ),
      messageId: (json['messageId'] ?? json['message_id'] ?? assistantMsg?.id)
          ?.toString(),
      threadId:
          (json['threadId'] ?? json['thread_id'] ?? assistantMsg?.threadId)
              ?.toString(),
      userMessage: userMsg,
      assistantMessage: assistantMsg,
      disclaimer: json['disclaimer']?.toString(),
    );
  }

  static List<String>? parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value.map((e) => e.toString()).toList();
  }

  static List<SuggestedAction>? parseSuggestedActions(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => SuggestedAction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Request to send a message.
/// API: POST /chat/threads/{thread_id}/messages
/// Only `content` should be in the body, thread_id is in the URL path.
@freezed
class SendMessageRequest with _$SendMessageRequest {
  const SendMessageRequest._();

  const factory SendMessageRequest({required String content}) =
      _SendMessageRequest;

  factory SendMessageRequest.fromJson(Map<String, dynamic> json) {
    return SendMessageRequest(content: (json['content'] ?? '').toString());
  }

  Map<String, dynamic> toJson() => {'content': content};
}

/// Response for listing messages.
@freezed
class MessagesListResponse with _$MessagesListResponse {
  const factory MessagesListResponse({
    @Default([]) List<ChatMessage> messages,
    int? totalCount,
    @Default(false) bool hasMore,
  }) = _MessagesListResponse;

  factory MessagesListResponse.fromJson(Map<String, dynamic> json) {
    return MessagesListResponse(
      messages: _parseMessagesList(json['messages']) ?? [],
      totalCount: (json['totalCount'] ?? json['total_count'] as num?)?.toInt(),
      hasMore: json['hasMore'] == true || json['has_more'] == true,
    );
  }

  static List<ChatMessage>? _parseMessagesList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Response for listing threads.
@freezed
class ThreadsListResponse with _$ThreadsListResponse {
  const factory ThreadsListResponse({
    @Default([]) List<ChatThread> threads,
    int? totalCount,
    @Default(false) bool hasMore,
    int? total,
  }) = _ThreadsListResponse;

  factory ThreadsListResponse.fromJson(Map<String, dynamic> json) {
    return ThreadsListResponse(
      threads: _parseThreadsList(json['threads']) ?? [],
      totalCount: (json['totalCount'] ?? json['total_count'] as num?)?.toInt(),
      hasMore: json['hasMore'] == true || json['has_more'] == true,
      total: (json['total'] as num?)?.toInt(),
    );
  }

  static List<ChatThread>? _parseThreadsList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => ChatThread.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Event from streaming chat response.
sealed class StreamChatEvent {
  const StreamChatEvent();

  /// A chunk of text content.
  factory StreamChatEvent.chunk(String content) = StreamChatChunk;

  /// Streaming completed successfully.
  factory StreamChatEvent.done({
    String? messageId,
    String? userMessageId,
    List<SuggestedAction>? suggestedActions,
    List<String>? followUpQuestions,
  }) = StreamChatDone;

  /// An error occurred.
  factory StreamChatEvent.error(String error) = StreamChatError;
}

class StreamChatChunk extends StreamChatEvent {
  final String content;
  const StreamChatChunk(this.content);
}

class StreamChatDone extends StreamChatEvent {
  final String? messageId;
  final String? userMessageId;
  final List<SuggestedAction>? suggestedActions;
  final List<String>? followUpQuestions;

  const StreamChatDone({
    this.messageId,
    this.userMessageId,
    this.suggestedActions,
    this.followUpQuestions,
  });
}

class StreamChatError extends StreamChatEvent {
  final String error;
  const StreamChatError(this.error);
}
