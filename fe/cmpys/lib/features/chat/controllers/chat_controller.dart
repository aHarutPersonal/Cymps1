import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_error.dart';
import '../../auth/controllers/session_controller.dart';
import '../../home/controllers/home_controller.dart';
import '../../idols/data/idols_repository.dart';
import '../data/chat_repository.dart';
import '../models/chat_models.dart';

/// Chat state.
sealed class ChatState {
  const ChatState();
}

class ChatInitial extends ChatState {
  const ChatInitial();
}

class ChatLoading extends ChatState {
  const ChatLoading();
}

class ChatLoaded extends ChatState {
  const ChatLoaded({
    required this.thread,
    required this.messages,
    this.isSending = false,
    this.llmUnavailable = false,
    this.streamingContent,
    this.suggestedActions,
    this.followUpQuestions,
  });

  final ChatThread thread;
  final List<ChatMessage> messages;
  final bool isSending;
  final bool llmUnavailable;

  /// Content being streamed in real-time (null if not streaming).
  final String? streamingContent;

  final List<SuggestedAction>? suggestedActions;
  final List<String>? followUpQuestions;

  ChatLoaded copyWith({
    ChatThread? thread,
    List<ChatMessage>? messages,
    bool? isSending,
    bool? llmUnavailable,
    String? streamingContent,
    bool clearStreaming = false,
    List<SuggestedAction>? suggestedActions,
    List<String>? followUpQuestions,
  }) {
    return ChatLoaded(
      thread: thread ?? this.thread,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      llmUnavailable: llmUnavailable ?? this.llmUnavailable,
      streamingContent: clearStreaming
          ? null
          : (streamingContent ?? this.streamingContent),
      suggestedActions: suggestedActions ?? this.suggestedActions,
      followUpQuestions: followUpQuestions ?? this.followUpQuestions,
    );
  }
}

class ChatError extends ChatState {
  const ChatError({required this.message, this.isLlmUnavailable = false});
  final String message;
  final bool isLlmUnavailable;
}

/// Chat controller provider.
final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) {
    return ChatController(
      ref: ref,
      chatRepository: ref.watch(chatRepositoryProvider),
      idolsRepository: ref.watch(idolsRepositoryProvider),
      currentIdolId: ref.watch(currentIdolIdProvider),
    );
  },
);

/// Controller for chat screen.
class ChatController extends StateNotifier<ChatState> {
  ChatController({
    required Ref ref,
    required ChatRepository chatRepository,
    required IdolsRepository idolsRepository,
    required String? currentIdolId,
  }) : _ref = ref,
       _chatRepository = chatRepository,
       _idolsRepository = idolsRepository,
       _currentIdolId = currentIdolId,
       super(const ChatInitial());

  final Ref _ref;
  final ChatRepository _chatRepository;
  final IdolsRepository _idolsRepository;
  final String? _currentIdolId;

  /// Local message storage (since backend may not persist all messages)
  final List<ChatMessage> _localMessages = [];

  bool _isStaleIdolError(ApiError error) {
    return error.isNotFoundError &&
        error.message.toLowerCase().contains('idol');
  }

  /// Initialize chat - create or get thread.
  /// POST /chat/threads {idolId}
  Future<void> initialize() async {
    if (state is ChatLoading) return;

    state = const ChatLoading();

    try {
      String? idolId = _currentIdolId;

      // --- Fallback: if idol ID missing (web hot-restart / direct navigation),
      // use the most recent thread's idol instead of showing an error. ---
      if (idolId == null) {
        try {
          final threads = await _chatRepository.getThreads(limit: 1);
          if (threads.threads.isNotEmpty) {
            idolId = threads.threads.first.idolId;
          }
        } catch (_) {}
      }

      if (idolId == null) {
        state = const ChatError(message: 'No idol selected');
        return;
      }

      // Get or create thread for current idol
      final thread = await _chatRepository.getOrCreateThread(idolId);

      // Try to load existing messages
      List<ChatMessage> messages = [];
      try {
        final messagesResponse = await _chatRepository.getMessages(thread.id);
        messages = messagesResponse.messages;
      } catch (e) {
        // If backend doesn't support message listing, use local storage
        messages = _localMessages;
      }

      state = ChatLoaded(thread: thread, messages: messages);

      debugPrint(
        '🎨 [ChatController] Checking thread.idolImageUrl: ${thread.idolImageUrl}',
      );
      // Auto-generate avatar if missing
      if (thread.idolImageUrl == null) {
        debugPrint(
          '🎨 [ChatController] idolImageUrl is null. Calling generateAvatar()...',
        );
        generateAvatar();
      }
    } on ApiError catch (e) {
      if (e.statusCode == 503) {
        state = const ChatError(
          message: 'AI chat is currently unavailable',
          isLlmUnavailable: true,
        );
      } else if (_isStaleIdolError(e)) {
        await _ref
            .read(sessionControllerProvider.notifier)
            .clearCurrentIdolId();
        state = const ChatError(message: 'Choose an idol to continue');
      } else {
        state = ChatError(message: e.message);
      }
    } catch (e) {
      state = ChatError(message: e.toString());
    }
  }

  /// Load a specific existing thread by ID (for chat history).
  Future<void> loadThread(String threadId) async {
    state = const ChatLoading();

    try {
      final thread = await _chatRepository.getThread(threadId);
      final messagesResponse = await _chatRepository.getMessages(threadId);

      _localMessages.clear();
      _localMessages.addAll(messagesResponse.messages);

      state = ChatLoaded(thread: thread, messages: messagesResponse.messages);

      if (thread.idolImageUrl == null) {
        generateAvatar();
      }
    } on ApiError catch (e) {
      if (_isStaleIdolError(e)) {
        await _ref
            .read(sessionControllerProvider.notifier)
            .clearCurrentIdolId();
        state = const ChatError(message: 'Choose an idol to continue');
      } else {
        state = ChatError(message: e.message);
      }
    } catch (e) {
      state = ChatError(message: e.toString());
    }
  }

  /// Send a message.
  /// POST /chat/threads/{threadId}/messages
  Future<void> sendMessage(String content) async {
    final currentState = state;
    if (currentState is! ChatLoaded) return;
    if (content.trim().isEmpty) return;

    final thread = currentState.thread;

    // Create optimistic user message
    final userMessage = ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
      threadId: thread.id,
    );

    // Add user message and show typing indicator
    final updatedMessages = [...currentState.messages, userMessage];
    _localMessages.add(userMessage);
    state = currentState.copyWith(messages: updatedMessages, isSending: true);

    try {
      // Send message to API
      final response = await _chatRepository.sendMessage(thread.id, content);

      // Create assistant message from response
      final assistantMessage = ChatMessage(
        id: response.messageId ?? 'ai_${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: response.reply,
        createdAt: DateTime.now(),
        threadId: thread.id,
      );

      // Add assistant message
      final finalMessages = [...updatedMessages, assistantMessage];
      _localMessages.add(assistantMessage);

      state = ChatLoaded(
        thread: thread,
        messages: finalMessages,
        isSending: false,
        llmUnavailable: false,
      );
    } on ApiError catch (e) {
      if (e.statusCode == 503) {
        // LLM not configured - show banner but keep messages
        state = currentState.copyWith(
          messages: updatedMessages,
          isSending: false,
          llmUnavailable: true,
        );
      } else {
        // Other error - add error message
        final errorMessage = ChatMessage(
          id: 'error_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: 'Sorry, I encountered an error. Please try again.',
          createdAt: DateTime.now(),
          threadId: thread.id,
        );

        state = currentState.copyWith(
          messages: [...updatedMessages, errorMessage],
          isSending: false,
        );
      }
    } catch (e) {
      // Network or other error
      final errorMessage = ChatMessage(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: 'Unable to send message. Please check your connection.',
        createdAt: DateTime.now(),
        threadId: thread.id,
      );

      final updatedState = state;
      if (updatedState is ChatLoaded) {
        state = updatedState.copyWith(
          messages: [...updatedState.messages, errorMessage],
          isSending: false,
        );
      }
    }
  }

  /// Send a message with real-time streaming response.
  /// Uses SSE endpoint for word-by-word display.
  Future<void> sendMessageStream(String content) async {
    final currentState = state;
    if (currentState is! ChatLoaded) return;
    if (content.trim().isEmpty) return;

    final thread = currentState.thread;

    // Create optimistic user message
    final userMessage = ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
      threadId: thread.id,
    );

    // Add user message and start streaming
    final updatedMessages = [...currentState.messages, userMessage];
    _localMessages.add(userMessage);
    state = currentState.copyWith(
      messages: updatedMessages,
      isSending: true,
      streamingContent: '',
    );

    try {
      String accumulatedContent = '';

      await for (final event in _chatRepository.sendMessageStream(
        thread.id,
        content,
      )) {
        switch (event) {
          case StreamChatChunk(:final content):
            accumulatedContent += content;
            final st = state;
            if (st is ChatLoaded) {
              state = st.copyWith(streamingContent: accumulatedContent);
            }
          case StreamChatDone(
            :final messageId,
            :final suggestedActions,
            :final followUpQuestions,
          ):
            // Streaming complete - add final message
            final assistantMessage = ChatMessage(
              id: messageId ?? 'ai_${DateTime.now().millisecondsSinceEpoch}',
              role: 'assistant',
              content: accumulatedContent,
              createdAt: DateTime.now(),
              threadId: thread.id,
            );

            final finalMessages = [...updatedMessages, assistantMessage];
            _localMessages.add(assistantMessage);

            state = ChatLoaded(
              thread: thread,
              messages: finalMessages,
              isSending: false,
              llmUnavailable: false,
              streamingContent: null,
              suggestedActions: suggestedActions,
              followUpQuestions: followUpQuestions,
            );
          case StreamChatError(:final error):
            throw Exception(error);
        }
      }
    } catch (e) {
      // Error - add error message
      final errorMessage = ChatMessage(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: 'Sorry, I encountered an error. Please try again.',
        createdAt: DateTime.now(),
        threadId: thread.id,
      );

      final st = state;
      if (st is ChatLoaded) {
        state = st.copyWith(
          messages: [...updatedMessages, errorMessage],
          isSending: false,
          clearStreaming: true,
        );
      }
    }
  }

  /// Generate AI avatar for current idol.
  Future<void> generateAvatar() async {
    final currentState = state;
    debugPrint(
      '🎨 [ChatController.generateAvatar] Started. currentState is ChatLoaded: ${currentState is ChatLoaded}',
    );
    if (currentState is! ChatLoaded) return;

    // Safety check - if we already have an image, don't generate another
    if (currentState.thread.idolImageUrl != null &&
        currentState.thread.idolImageUrl!.isNotEmpty) {
      debugPrint(
        '🎨 [ChatController.generateAvatar] Avatar already exists. Skipping.',
      );
      return;
    }

    try {
      // Fetch current user age to dictate idol portrayal accurately
      final userAge =
          _ref.read(sessionControllerProvider.notifier).userAge ?? 30;
      debugPrint(
        '🎨 [ChatController.generateAvatar] userAge: $userAge, idolId: ${currentState.thread.idolId}',
      );

      final imageUrl = await _idolsRepository.generateAvatar(
        currentState.thread.idolId,
        age: userAge,
      );
      debugPrint(
        '🎨 [ChatController.generateAvatar] Success! ImageURL: $imageUrl',
      );

      // Update thread with new image URL
      final updatedThread = currentState.thread.copyWith(
        idolImageUrl: imageUrl,
      );

      // Update state if still loaded
      state = currentState.copyWith(thread: updatedThread);

      debugPrint(
        '🎨 [ChatController.generateAvatar] Refreshing home controller...',
      );
      // Notify home controller to refresh so the avatar shows on the main screen
      _ref.read(homeControllerProvider.notifier).refresh();
    } catch (e, stack) {
      debugPrint('🎨 [ChatController.generateAvatar] FAILED: $e');
      debugPrint('🎨 Stack: $stack');
    }
  }

  /// Dismiss LLM unavailable banner
  void dismissLlmBanner() {
    final currentState = state;
    if (currentState is ChatLoaded) {
      state = currentState.copyWith(llmUnavailable: false);
    }
  }

  /// Clear chat history
  void clearMessages() {
    _localMessages.clear();
    final currentState = state;
    if (currentState is ChatLoaded) {
      state = currentState.copyWith(messages: []);
    }
  }
}
