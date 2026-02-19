import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/loading_state.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_models.dart';
import '../../notes/controllers/notes_controller.dart';
import '../../plans/controllers/plans_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Initialize chat on first open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatControllerProvider.notifier).initialize();
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
    // Use streaming for real-time response
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

    // Scroll to bottom when messages change
    ref.listen(chatControllerProvider, (prev, next) {
      if (next is ChatLoaded && prev is ChatLoaded) {
        if (next.messages.length > prev.messages.length) {
          _scrollToBottom();
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: _buildBody(chatState),
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    return switch (state) {
      ChatInitial() || ChatLoading() => const LoadingState(
          message: 'Starting chat...',
        ),
      ChatError(:final message, :final isLlmUnavailable) =>
        _buildErrorState(message, isLlmUnavailable),
      ChatLoaded() => _buildChatContent(state),
    };
  }

  Widget _buildErrorState(String message, bool isLlmUnavailable) {
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
                color: isLlmUnavailable
                    ? AppColors.warning.withOpacity(0.1)
                    : AppColors.error.withOpacity(0.1),
                borderRadius: AppRadii.br16,
              ),
              child: Center(
                child: SvgPicture.asset(
                  isLlmUnavailable ? AppAssets.iconSparkles : AppAssets.iconAlertCircle,
                  width: 32,
                  height: 32,
                  colorFilter: ColorFilter.mode(
                    isLlmUnavailable ? AppColors.warning : AppColors.error,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              isLlmUnavailable ? 'AI Temporarily Unavailable' : 'Unable to start chat',
              style: AppTypography.h3,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              isLlmUnavailable
                  ? 'The AI coach is being configured.\nPlease try again later.'
                  : message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Try Again',
              onPressed: () => ref.read(chatControllerProvider.notifier).initialize(),
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
        // Header
        Padding(
          padding: AppSpacing.screenH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s8),
              Row(
                children: [
                  state.thread.idolImageUrl != null
                      ? Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.br12,
                            image: DecorationImage(
                              image: NetworkImage(state.thread.idolImageUrl!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.accent, AppColors.accentLight],
                            ),
                            borderRadius: AppRadii.br12,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              AppAssets.iconSparkles,
                              width: 22,
                              height: 22,
                              colorFilter: const ColorFilter.mode(
                                AppColors.textPrimary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.thread.idolName ?? 'AI Coach',
                          style: AppTypography.h3,
                        ),
                        Text(
                          isSending ? 'Typing...' : 'Online',
                          style: AppTypography.caption.copyWith(
                            color: isSending ? AppColors.accent : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: SvgPicture.asset(
                      AppAssets.iconEllipsisVertical,
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                    onSelected: (value) {
                      if (value == 'generate_avatar') {
                        ref.read(chatControllerProvider.notifier).generateAvatar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Generating avatar...')),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'generate_avatar',
                        child: Text('Generate Avatar'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        // LLM unavailable banner
        if (llmUnavailable) _LlmUnavailableBanner(
          onDismiss: () => ref.read(chatControllerProvider.notifier).dismissLlmBanner(),
        ),
        const Divider(color: AppColors.border, height: 1),
        // Messages
        Expanded(
          child: messages.isEmpty
              ? _buildEmptyChat()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(
                    left: AppSpacing.s24,
                    right: AppSpacing.s24,
                    top: AppSpacing.s16,
                    bottom: AppSpacing.s24,
                  ),
                  itemCount: messages.length + (isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length && isSending) {
                      // Show streaming content or typing indicator
                      final streamingContent = state.streamingContent;
                      if (streamingContent != null && streamingContent.isNotEmpty) {
                        return _StreamingBubble(content: streamingContent);
                      }
                      return const _TypingIndicator();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                      child: _ChatBubble(message: messages[index]),
                    );
                  },
                ),
        ),
        // Quick actions
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenH,
            children: [
              _QuickAction(
                label: 'Create plan',
                onTap: () => _quickMessage('Create a plan for this week'),
              ),
              const SizedBox(width: AppSpacing.s8),
              _QuickAction(
                label: 'Compare timeline',
                onTap: () => _quickMessage('Show me the timeline comparison'),
              ),
              const SizedBox(width: AppSpacing.s8),
              _QuickAction(
                label: 'Get advice',
                onTap: () => _quickMessage('What should I focus on next?'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        // Input
        Container(
          padding: EdgeInsets.only(
            left: AppSpacing.s24,
            right: AppSpacing.s24,
            top: AppSpacing.s12,
            bottom: MediaQuery.of(context).padding.bottom + AppSpacing.s12,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: AppTypography.body,
                  enabled: !isSending,
                  decoration: InputDecoration(
                    hintText: 'Ask anything...',
                    hintStyle: AppTypography.body.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.br12,
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.br12,
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadii.br12,
                      borderSide: const BorderSide(color: AppColors.textPrimary),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.br12,
                      borderSide: BorderSide(color: AppColors.borderLight.withOpacity(0.5)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16,
                      vertical: AppSpacing.s12,
                    ),
                    filled: true,
                    fillColor: AppColors.bg,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              GestureDetector(
                onTap: isSending ? null : _sendMessage,
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSending ? AppColors.surface2 : AppColors.textPrimary,
                    borderRadius: AppRadii.brFull,
                  ),
                  child: Center(
                    child: isSending
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textTertiary,
                            ),
                          )
                        : SvgPicture.asset(
                            AppAssets.iconSend,
                            width: 20,
                            height: 20,
                            colorFilter: const ColorFilter.mode(
                              AppColors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                  ),
                ),
              ),
            ],
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
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadii.br16,
                boxShadow: AppShadows.accent,
              ),
              child: Center(
                child: SvgPicture.asset(
                  AppAssets.iconSparkles,
                  width: 32,
                  height: 32,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
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

/// LLM unavailable banner (503 error)
class _LlmUnavailableBanner extends StatelessWidget {
  const _LlmUnavailableBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: AppColors.warning.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            AppAssets.iconInfo,
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(
              AppColors.warning,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              'AI responses temporarily unavailable',
              style: AppTypography.caption.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: SvgPicture.asset(
              AppAssets.iconX,
              width: 14,
              height: 14,
              colorFilter: ColorFilter.mode(
                AppColors.warning.withOpacity(0.7),
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat message bubble
class _ChatBubble extends ConsumerWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.isUser;
    
    // Parse suggestion tag if present
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
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentLight],
              ),
              borderRadius: AppRadii.br8,
            ),
            child: Center(
              child: SvgPicture.asset(
                AppAssets.iconSparkles,
                width: 14,
                height: 14,
                colorFilter: const ColorFilter.mode(
                  AppColors.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: AppSpacing.p12,
                decoration: BoxDecoration(
                  color: isUser ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? Border.all(color: AppColors.borderLight)
                      : const Border(left: BorderSide(color: AppColors.emerald, width: 2)),
                ),
                child: Text(
                  content,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (suggestion != null) ...[
                const SizedBox(height: AppSpacing.s8),
                InkWell(
                  onTap: () async {
                    try {
                      await ref.read(plansControllerProvider.notifier).createItem(
                        title: suggestion!,
                         description: "Suggested by AI Coach during chat conversation.",
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
                      horizontal: AppSpacing.s12,
                      vertical: AppSpacing.s8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: AppRadii.brFull,
                      border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_circle_outline,
                          size: 16,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Flexible(
                          child: Text(
                            'Add to Plan: $suggestion',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.accent,
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
              // Save to Notes action for assistant messages
              if (!isUser) ...[
                const SizedBox(height: AppSpacing.s8),
                InkWell(
                  onTap: () async {
                    try {
                      await ref.read(notesControllerProvider.notifier).createNote(
                        title: 'Chat Note',
                        content: content,
                      );
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
                      horizontal: AppSpacing.s12,
                      vertical: AppSpacing.s6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: AppRadii.brFull,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.note_add_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.s4),
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

/// Streaming chat bubble - shows content as it's being streamed
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
    _cursorAnimation = Tween<double>(begin: 0, end: 1).animate(_cursorController);
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentLight],
            ),
            borderRadius: AppRadii.br8,
          ),
          child: Center(
            child: SvgPicture.asset(
              AppAssets.iconSparkles,
              width: 14,
              height: 14,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Flexible(
          child: Container(
            padding: AppSpacing.p12,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: AnimatedBuilder(
              animation: _cursorAnimation,
              builder: (context, child) {
                return RichText(
                  text: TextSpan(
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    children: [
                      TextSpan(text: widget.content.replaceAll(RegExp(r'\[SUGGESTION:.*?\]'), '')),
                      TextSpan(
                        text: '▋',
                        style: TextStyle(
                          color: AppColors.accent.withOpacity(_cursorAnimation.value),
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

/// Typing indicator
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentLight],
            ),
            borderRadius: AppRadii.br8,
          ),
          child: Center(
            child: SvgPicture.asset(
              AppAssets.iconSparkles,
              width: 14,
              height: 14,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Container(
          padding: AppSpacing.p12,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: AppColors.border),
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
                      color: AppColors.textSecondary.withOpacity(opacity),
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

/// Quick action chip
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.brFull,
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
