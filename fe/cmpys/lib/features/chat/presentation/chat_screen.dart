import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/ambient_background.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/loading_state.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_models.dart';
import '../../notes/controllers/notes_controller.dart';
import '../../plans/controllers/plans_controller.dart';

/// Extra bottom clearance for the floating nav bar rendered by AppShell.
/// Nav bar is 56px tall + ~8px bottom gap = 64px. The SafeArea handles
/// the system bottom inset, so we only need to add the nav bar space.
const _kNavBarClearance = 64.0;

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.threadId});

  /// Optional thread ID to load a specific thread (from chat history).
  final String? threadId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.threadId != null && widget.threadId!.isNotEmpty) {
        ref.read(chatControllerProvider.notifier).loadThread(widget.threadId!);
      } else {
        ref.read(chatControllerProvider.notifier).initialize();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    ref.read(chatControllerProvider.notifier).sendMessageStream(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppDurations.normal,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _quickMessage(String message) {
    _messageController.text = message;
    _sendMessage();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    ref.listen(chatControllerProvider, (prev, next) {
      if (next is ChatLoaded && prev is ChatLoaded) {
        if (next.messages.length > prev.messages.length) {
          _scrollToBottom();
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(chatState),
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          top: false,
          child: _buildBody(chatState),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ChatState state) {
    if (state is ChatLoaded) {
      final isSending = state.isSending;
      return AppBar(
        backgroundColor: AppColors.bg.withValues(alpha: 0.82),
        scrolledUnderElevation: 0,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppColors.glassBorder)),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            // Dismiss keyboard before popping
            FocusScope.of(context).unfocus();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            state.thread.idolImageUrl != null
                ? Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: NetworkImage(state.thread.idolImageUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.thread.idolName ?? 'AI Coach',
                    style: AppTypography.h4.copyWith(fontSize: 16),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isSending
                              ? AppColors.peach
                              : AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSending ? 'Thinking...' : 'AI Active',
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          color: isSending
                              ? AppColors.peach
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onSelected: (value) {
              if (value == 'history') {
                context.push(AppRoutes.chatThreads);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history, size: 18),
                    SizedBox(width: 8),
                    Text('Chat History'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    return AppBar(
      backgroundColor: AppColors.bg.withValues(alpha: 0.82),
      scrolledUnderElevation: 0,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          size: 20,
          color: AppColors.textPrimary,
        ),
        onPressed: () {
          FocusScope.of(context).unfocus();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    return switch (state) {
      ChatInitial() ||
      ChatLoading() => const LoadingState(message: 'Starting chat...'),
      ChatError(:final message, :final isLlmUnavailable) => _buildErrorState(
        message,
        isLlmUnavailable,
      ),
      ChatLoaded() => _buildChatContent(state),
    };
  }

  Widget _buildErrorState(String message, bool isLlmUnavailable) {
    final needsIdol =
        message.toLowerCase().contains('idol') ||
        message.toLowerCase().contains('choose an idol');

    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color:
                    (needsIdol
                            ? AppColors.accent
                            : (isLlmUnavailable
                                  ? AppColors.warning
                                  : AppColors.error))
                        .withValues(alpha: 0.1),
                borderRadius: AppRadii.br24,
              ),
              child: Center(
                child: Icon(
                  needsIdol
                      ? Icons.explore_outlined
                      : (isLlmUnavailable
                            ? Icons.auto_awesome
                            : Icons.error_outline),
                  size: 32,
                  color: needsIdol
                      ? AppColors.accent
                      : (isLlmUnavailable
                            ? AppColors.warning
                            : AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              needsIdol
                  ? 'Choose Your North Star'
                  : (isLlmUnavailable
                        ? 'AI Temporarily Unavailable'
                        : 'Unable to start chat'),
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              needsIdol
                  ? 'Pick a benchmark before starting a mentor conversation.'
                  : (isLlmUnavailable
                        ? 'The AI coach is being configured.\nPlease try again later.'
                        : message),
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: needsIdol ? 'Choose Idol' : 'Try Again',
              onPressed: needsIdol
                  ? () => context.goToIdolSuggest()
                  : () =>
                        ref.read(chatControllerProvider.notifier).initialize(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatContent(ChatLoaded state) {
    final messages = state.messages;
    final isSending = state.isSending;
    final llmUnavailable = state.llmUnavailable;

    return Column(
      children: [
        // LLM unavailable banner
        if (llmUnavailable)
          _LlmUnavailableBanner(
            onDismiss: () =>
                ref.read(chatControllerProvider.notifier).dismissLlmBanner(),
          ),

        // -- MESSAGES --
        Expanded(
          child: messages.isEmpty
              ? _buildEmptyChat()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 16,
                    bottom: 24,
                  ),
                  itemCount: messages.length + (isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length && isSending) {
                      final streamingContent = state.streamingContent;
                      if (streamingContent != null &&
                          streamingContent.isNotEmpty) {
                        return _StreamingBubble(content: streamingContent);
                      }
                      return const _TypingIndicator();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ChatBubble(message: messages[index]),
                    );
                  },
                ),
        ),

        // -- SUGGESTION CHIPS --
        if (state.suggestedActions?.isNotEmpty == true ||
            state.followUpQuestions?.isNotEmpty == true)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                if (state.suggestedActions != null)
                  ...state.suggestedActions!.map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SuggestionChip(
                        label: action.label,
                        onTap: () => _quickMessage(action.label),
                      ),
                    ),
                  ),
                if (state.followUpQuestions != null)
                  ...state.followUpQuestions!.map(
                    (question) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SuggestionChip(
                        label: question,
                        onTap: () => _quickMessage(question),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // -- INPUT --
        // SafeArea handles the system bottom inset (home indicator).
        // The extra bottom padding accounts for the floating nav bar
        // rendered by the parent AppShell scaffold (56px bar + 8px gap).
        Padding(
          padding: const EdgeInsets.only(bottom: _kNavBarClearance),
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.94),
                border: const Border(
                  top: BorderSide(color: AppColors.glassBorder),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.charcoal.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.br20,
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        cursorColor: AppColors.accent,
                        keyboardAppearance: Brightness.light,
                        enabled: !isSending,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          hintText: 'Ask anything...',
                          hintStyle: AppTypography.body.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: isSending ? null : _sendMessage,
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSending
                            ? AppColors.surfaceHighlight
                            : AppColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: isSending ? null : AppShadows.glowSubtle,
                      ),
                      child: Center(
                        child: isSending
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : const Icon(
                                Icons.send,
                                size: 20,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: AppRadii.br24,
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome, size: 32, color: Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text('Start a conversation', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Ask me anything about your goals,\ncompare with your idol, or get advice',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// LLM unavailable banner
class _LlmUnavailableBanner extends StatelessWidget {
  const _LlmUnavailableBanner({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI responses temporarily unavailable',
              style: AppTypography.caption.copyWith(color: AppColors.warning),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              size: 14,
              color: AppColors.warning.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat message bubble — light design
class _ChatBubble extends ConsumerWidget {
  const _ChatBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.isUser;

    String content = message.content;
    String? suggestion;

    if (!isUser) {
      final regex = RegExp(r'\[SUGGESTION:\s*(.*?)\]');
      final match = regex.firstMatch(content);
      if (match != null) {
        suggestion = match.group(1);
        content = content.replaceAll(regex, '').trim();
      }
    }

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.peach],
              ),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, size: 17, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: isUser
                      ? MediaQuery.sizeOf(context).width * 0.74
                      : double.infinity,
                ),
                padding: EdgeInsets.all(isUser ? 12 : 16),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppColors.accent.withValues(alpha: 0.95)
                      : AppColors.surface.withValues(alpha: 0.85),
                  border: Border.all(
                    color: isUser ? Colors.transparent : AppColors.glassBorder,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 22 : 6),
                    topRight: Radius.circular(isUser ? 6 : 22),
                    bottomLeft: const Radius.circular(22),
                    bottomRight: const Radius.circular(22),
                  ),
                  boxShadow: isUser ? AppShadows.glowSubtle : null,
                ),
                child: Text(
                  content,
                  style: AppTypography.body.copyWith(
                    color: isUser ? Colors.white : AppColors.textSecondary,
                    fontWeight: isUser ? FontWeight.w600 : FontWeight.normal,
                    height: isUser ? null : 1.45,
                  ),
                ),
              ),
              if (suggestion != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    try {
                      await ref
                          .read(plansControllerProvider.notifier)
                          .createItem(
                            title: suggestion!,
                            description:
                                "Suggested by AI Coach during chat conversation.",
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Action added to your plan!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to add: $e')),
                        );
                      }
                    }
                  },
                  borderRadius: AppRadii.brFull,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.brFull,
                      border: Border.all(
                        color: AppColors.peach.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_circle_outline,
                          size: 16,
                          color: AppColors.peach,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Add to Plan: $suggestion',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.peach,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!isUser) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    try {
                      await ref
                          .read(notesControllerProvider.notifier)
                          .createNote(title: 'Chat Note', content: content);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Saved to Notes!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save: $e')),
                        );
                      }
                    }
                  },
                  borderRadius: AppRadii.brFull,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.brFull,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.note_add_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Save to Notes',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isUser) const SizedBox(width: 36),
      ],
    );
  }
}

/// Streaming chat bubble
class _StreamingBubble extends StatefulWidget {
  const _StreamingBubble({required this.content});
  final String content;

  @override
  State<_StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<_StreamingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;
  late Animation<double> _cursorAnimation;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);
    _cursorAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(_cursorController);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.peach],
            ),
          ),
          child: const Center(
            child: Icon(Icons.auto_awesome, size: 17, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.96),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.42),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
              boxShadow: AppShadows.md,
            ),
            child: AnimatedBuilder(
              animation: _cursorAnimation,
              builder: (context, child) {
                return RichText(
                  text: TextSpan(
                    style: AppTypography.body,
                    children: [
                      TextSpan(
                        text: widget.content.replaceAll(
                          RegExp(r'\[SUGGESTION:.*?\]'),
                          '',
                        ),
                      ),
                      TextSpan(
                        text: '▋',
                        style: TextStyle(
                          color: AppColors.accent.withValues(
                            alpha: _cursorAnimation.value,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Typing indicator — 3 bouncing dots
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.peach],
            ),
          ),
          child: const Center(
            child: Icon(Icons.auto_awesome, size: 17, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.96),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.42)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(22),
            ),
            boxShadow: AppShadows.md,
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final delay = index * 0.2;
                  final value = ((_controller.value + delay) % 1.0);
                  final opacity = 0.3 + (0.7 * (1 - (value - 0.5).abs() * 2));
                  return Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Suggestion chip — glass capsule
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.brFull,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
