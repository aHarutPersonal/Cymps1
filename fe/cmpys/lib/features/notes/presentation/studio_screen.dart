import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/loading_state.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../chat/models/chat_models.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
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
    HapticFeedback.lightImpact();
    _messageController.clear();
    ref.read(chatControllerProvider.notifier).sendMessageStream(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    ref.listen(chatControllerProvider, (previous, next) {
      if (next is ChatLoaded && previous is ChatLoaded) {
        if (next.messages.length > previous.messages.length ||
            next.streamingContent != previous.streamingContent) {
          _scrollToBottom();
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PrototypeGridBackground(
        gridSize: 20,
        child: SafeArea(bottom: false, child: _buildBody(chatState)),
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    return switch (state) {
      ChatInitial() ||
      ChatLoading() => const LoadingState(message: 'Opening Studio...'),
      ChatError(:final message) => _StudioError(
        message: message,
        onRetry: () => ref.read(chatControllerProvider.notifier).initialize(),
      ),
      ChatLoaded() => _StudioChat(
        state: state,
        controller: _messageController,
        scrollController: _scrollController,
        onSend: _sendMessage,
        onHistory: () => context.push(AppRoutes.chatThreads),
      ),
    };
  }
}

class _StudioChat extends StatelessWidget {
  const _StudioChat({
    required this.state,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onHistory,
  });

  final ChatLoaded state;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final messages = state.messages;
    final showSeedConversation = messages.isEmpty && !state.isSending;
    final displayMessages = showSeedConversation
        ? _prototypeSeedMessages(state.thread)
        : messages;

    return Column(
      children: [
        _StudioHeader(thread: state.thread, onHistory: onHistory),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            children: [
              if (showSeedConversation) const _ContextReference(),
              ...displayMessages.map(
                (message) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _StudioBubble(message: message),
                ),
              ),
              if (state.isSending) ...[
                if (state.streamingContent?.trim().isNotEmpty == true)
                  _StudioStreamingBubble(text: state.streamingContent!.trim())
                else
                  const _StudioTypingBubble(),
              ],
            ],
          ),
        ),
        _StudioComposer(controller: controller, onSend: onSend),
      ],
    );
  }

  List<ChatMessage> _prototypeSeedMessages(ChatThread thread) {
    final now = DateTime.now();
    return [
      ChatMessage(
        id: 'seed-mentor-1',
        role: 'assistant',
        content:
            "Regarding our previous module on the Circle of Competence: have you audited your current operational limits yet?",
        createdAt: now.subtract(const Duration(minutes: 3)),
        threadId: thread.id,
      ),
      ChatMessage(
        id: 'seed-user-1',
        role: 'user',
        content:
            "Yes. I realized my circle is smaller than I thought, so I'm narrowing the next move before scaling it.",
        createdAt: now.subtract(const Duration(minutes: 2)),
        threadId: thread.id,
      ),
      ChatMessage(
        id: 'seed-mentor-2',
        role: 'assistant',
        content:
            'Correct. Better to master a specific moat than remain broad and imprecise. Precision is leverage.',
        createdAt: now.subtract(const Duration(minutes: 1)),
        threadId: thread.id,
      ),
    ];
  }
}

class _StudioHeader extends StatelessWidget {
  const _StudioHeader({required this.thread, required this.onHistory});

  final ChatThread thread;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final idolName = thread.idolName ?? 'Your Mentor';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 58, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.86),
        border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          _MentorAvatar(thread: thread),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.h4.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Strategic_Consultation',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _StudioIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'Chat history',
            onTap: onHistory,
          ),
        ],
      ),
    );
  }
}

class _MentorAvatar extends StatelessWidget {
  const _MentorAvatar({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.mint),
      ),
      child: thread.idolImageUrl?.isNotEmpty == true
          ? Image.network(
              thread.idolImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _avatarFallback(),
            )
          : _avatarFallback(),
    );
  }

  Widget _avatarFallback() {
    return const ColoredBox(
      color: AppColors.surfaceHighlight,
      child: Icon(Icons.auto_awesome_rounded, color: AppColors.textTertiary),
    );
  }
}

class _StudioIconButton extends StatelessWidget {
  const _StudioIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadii.br12,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.br12,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: AppRadii.br12,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.textTertiary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _ContextReference extends StatelessWidget {
  const _ContextReference();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      margin: const EdgeInsets.fromLTRB(18, 0, 0, 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.58),
        borderRadius: AppRadii.br12,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, color: AppColors.mint),
          const SizedBox(width: 10),
          Text(
            'REF: Logic_Node.014',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioBubble extends StatelessWidget {
  const _StudioBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.76,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isUser ? AppColors.textPrimary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isUser ? 16 : 4),
                topRight: Radius.circular(isUser ? 4 : 16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(16),
              ),
              border: isUser ? null : Border.all(color: AppColors.border),
              boxShadow: isUser ? null : AppShadows.sm,
            ),
            child: Text(
              message.content,
              style: AppTypography.caption.copyWith(
                color: isUser ? Colors.white : AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${_clock(message.createdAt)} // ${isUser ? 'ENCRYPTED' : 'BUFFERED'}',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _clock(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _StudioStreamingBubble extends StatelessWidget {
  const _StudioStreamingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _StudioBubble(
      message: ChatMessage(
        id: 'streaming',
        role: 'assistant',
        content: text,
        createdAt: DateTime.now(),
      ),
    );
  }
}

class _StudioTypingBubble extends StatelessWidget {
  const _StudioTypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.sm,
        ),
        child: Text(
          'Thinking...',
          style: AppTypography.captionUpper.copyWith(
            color: AppColors.mint,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

class _StudioComposer extends StatelessWidget {
  const _StudioComposer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 34),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                _ReferenceChip(
                  icon: Icons.menu_book_rounded,
                  label: 'RE: INTEL_INV',
                  active: true,
                ),
                SizedBox(width: 8),
                _ReferenceChip(
                  icon: Icons.attach_file_rounded,
                  label: 'ATTACH',
                  active: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighlight,
                    borderRadius: AppRadii.br16,
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: 'Ask your mentor...',
                      hintStyle: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                height: 56,
                child: ElevatedButton(
                  onPressed: onSend,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: AppColors.brandAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: AppRadii.br16),
                  ),
                  child: const Icon(Icons.send_rounded, size: 23),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: active
            ? AppColors.mint.withValues(alpha: 0.06)
            : AppColors.surfaceHighlight,
        borderRadius: AppRadii.br12,
        border: Border.all(
          color: active ? AppColors.mint : AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? AppColors.mint : AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTypography.captionUpper.copyWith(
              color: active ? AppColors.textPrimary : AppColors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioError extends StatelessWidget {
  const _StudioError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.p24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              color: AppColors.textTertiary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text('Studio Unavailable', style: AppTypography.h3),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
