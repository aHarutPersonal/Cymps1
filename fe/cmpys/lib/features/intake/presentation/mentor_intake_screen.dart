import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../chat/models/chat_models.dart';

abstract final class _IntakePalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const paperWarm = AppColors.surfaceHighlight;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
}

/// A hybrid chat and intake screen that provides a guided conversational experience.
class MentorIntakeScreen extends ConsumerStatefulWidget {
  const MentorIntakeScreen({super.key, this.threadId});

  final String? threadId;

  @override
  ConsumerState<MentorIntakeScreen> createState() => _MentorIntakeScreenState();
}

class _MentorIntakeScreenState extends ConsumerState<MentorIntakeScreen> {
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

  void _sendPayload(String text, Map<String, dynamic>? payload) {
    // In a real app, you might send the payload as JSON to the backend.
    // For now, we just send the text response.
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
      backgroundColor: _IntakePalette.canvas,
      appBar: _buildAppBar(chatState),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _IntakePalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _IntakePalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.48, 1],
          ),
        ),
        child: SafeArea(top: false, child: _buildBody(chatState)),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ChatState state) {
    if (state is ChatLoaded) {
      final isSending = state.isSending;
      return AppBar(
        backgroundColor: _IntakePalette.canvas.withValues(alpha: 0.92),
        scrolledUnderElevation: 0,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: _IntakePalette.line)),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: _IntakePalette.ink,
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
                      color: _IntakePalette.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: _IntakePalette.ink,
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
                    state.thread.idolName ?? 'AI Mentor',
                    style: AppTypography.h4.copyWith(
                      color: _IntakePalette.ink,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isSending
                              ? _IntakePalette.coral
                              : const Color(0xFF2E9B64),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSending ? 'Thinking...' : 'Achievement diagnostic',
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          color: isSending
                              ? _IntakePalette.coralDark
                              : const Color(0xFF2E7E57),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AppBar(
      backgroundColor: _IntakePalette.canvas.withValues(alpha: 0.92),
      elevation: 0,
    );
  }

  Widget _buildBody(ChatState state) {
    if (state is ChatLoading || state is ChatInitial) {
      return const Center(
        child: CircularProgressIndicator(color: _IntakePalette.coral),
      );
    }
    if (state is ChatError) {
      return Center(
        child: Text(
          'Error: ${state.message}',
          style: AppTypography.body.copyWith(color: _IntakePalette.ink),
        ),
      );
    }
    if (state is! ChatLoaded) return const SizedBox();

    final messages = state.messages;
    final isSending = state.isSending;

    return Column(
      children: [
        _IntakeContextHeader(
          idolName: state.thread.idolName ?? 'your mentor',
          messageCount: messages.length,
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: 24,
            ),
            itemCount: messages.length + (isSending ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == messages.length && isSending) {
                final streamingContent = state.streamingContent;
                if (streamingContent != null && streamingContent.isNotEmpty) {
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
        ElegantAnswerDock(
          state: state,
          textController: _messageController,
          onSend: _sendMessage,
          onActionSubmit: _sendPayload,
        ),
      ],
    );
  }
}

class ElegantAnswerDock extends StatefulWidget {
  const ElegantAnswerDock({
    super.key,
    required this.state,
    required this.textController,
    required this.onSend,
    required this.onActionSubmit,
  });

  final ChatLoaded state;
  final TextEditingController textController;
  final VoidCallback onSend;
  final Function(String, Map<String, dynamic>?) onActionSubmit;

  @override
  State<ElegantAnswerDock> createState() => _ElegantAnswerDockState();
}

class _IntakeContextHeader extends StatelessWidget {
  const _IntakeContextHeader({
    required this.idolName,
    required this.messageCount,
  });

  final String idolName;
  final int messageCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _IntakePalette.paper.withValues(alpha: 0.86),
        borderRadius: AppRadii.br20,
        border: Border.all(color: _IntakePalette.line),
        boxShadow: [
          BoxShadow(
            color: _IntakePalette.ink.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _IntakePalette.mint,
              borderRadius: AppRadii.br12,
              border: Border.all(
                color: _IntakePalette.ink.withValues(alpha: 0.08),
              ),
            ),
            child: const Icon(
              Icons.psychology_alt_outlined,
              color: _IntakePalette.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mentor interview',
                  style: AppTypography.captionUpper.copyWith(
                    color: _IntakePalette.coralDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Build the achievement mirror with $idolName',
                  style: AppTypography.h4.copyWith(color: _IntakePalette.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: _IntakePalette.paperWarm,
              borderRadius: AppRadii.brFull,
              border: Border.all(color: _IntakePalette.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                '$messageCount',
                style: AppTypography.captionMedium.copyWith(
                  color: _IntakePalette.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElegantAnswerDockState extends State<ElegantAnswerDock> {
  @override
  Widget build(BuildContext context) {
    final actions = widget.state.suggestedActions;
    final hasActions = actions != null && actions.isNotEmpty;
    final isSending = widget.state.isSending;

    return AnimatedSize(
      duration: AppDurations.normal,
      curve: Curves.easeInOutBack,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: _IntakePalette.paper.withValues(alpha: 0.94),
          border: const Border(top: BorderSide(color: _IntakePalette.line)),
          boxShadow: [
            BoxShadow(
              color: _IntakePalette.ink.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasActions && !isSending) ...[
              _buildStructuredInputs(actions),
              const SizedBox(height: 16),
            ],
            // Always show contextual text field for open-ended replies or fallbacks
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _IntakePalette.canvas,
                      borderRadius: AppRadii.br16,
                      border: Border.all(color: _IntakePalette.line),
                    ),
                    child: TextField(
                      controller: widget.textController,
                      style: AppTypography.body.copyWith(
                        color: _IntakePalette.ink,
                      ),
                      cursorColor: _IntakePalette.coral,
                      keyboardAppearance: Brightness.light,
                      enabled: !isSending,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: hasActions
                            ? 'Or type your own answer...'
                            : 'Ask anything...',
                        hintStyle: AppTypography.body.copyWith(
                          color: _IntakePalette.muted,
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
                      onSubmitted: (_) => widget.onSend(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: isSending ? null : widget.onSend,
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSending
                          ? _IntakePalette.line
                          : _IntakePalette.coral,
                      shape: BoxShape.circle,
                      boxShadow: isSending
                          ? null
                          : [
                              BoxShadow(
                                color: _IntakePalette.coral.withValues(
                                  alpha: 0.28,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                    ),
                    child: Center(
                      child: isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _IntakePalette.muted,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward,
                              size: 24,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredInputs(List<SuggestedAction> actions) {
    // Determine the primary type based on the first action
    final primaryType = actions.first.type;

    switch (primaryType) {
      case 'boolean':
        return Row(
          children: actions.map((a) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: BinaryChoiceChip(
                  label: a.label,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onActionSubmit(a.label, a.payload);
                  },
                ),
              ),
            );
          }).toList(),
        );
      case 'select':
      case 'multi_choice':
        return Column(
          children: actions.map((a) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MultiSelectCard(
                label: a.label,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onActionSubmit(a.label, a.payload);
                },
              ),
            );
          }).toList(),
        );
      case 'scale':
        return CircularScalePicker(
          min: 1,
          max: 10,
          onSelect: (val) {
            HapticFeedback.mediumImpact();
            widget.onActionSubmit(val.toString(), {'value': val});
          },
        );
      default:
        // Fallback to simple suggestion chips wrapped
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actions.map((a) {
            return BinaryChoiceChip(
              label: a.label,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onActionSubmit(a.label, a.payload);
              },
            );
          }).toList(),
        );
    }
  }
}

class BinaryChoiceChip extends StatelessWidget {
  const BinaryChoiceChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: _IntakePalette.paperWarm,
          borderRadius: AppRadii.br12,
          border: Border.all(color: _IntakePalette.line),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.buttonSmall.copyWith(
              color: _IntakePalette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class MultiSelectCard extends StatelessWidget {
  const MultiSelectCard({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _IntakePalette.paperWarm,
          borderRadius: AppRadii.br12,
          border: Border.all(color: _IntakePalette.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.body.copyWith(
                color: _IntakePalette.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _IntakePalette.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CircularScalePicker extends StatefulWidget {
  const CircularScalePicker({
    super.key,
    required this.min,
    required this.max,
    required this.onSelect,
  });

  final int min;
  final int max;
  final ValueChanged<int> onSelect;

  @override
  State<CircularScalePicker> createState() => _CircularScalePickerState();
}

class _CircularScalePickerState extends State<CircularScalePicker> {
  int _currentValue = 5;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _currentValue.toString(),
          style: AppTypography.h1.copyWith(
            color: _IntakePalette.coralDark,
            fontSize: 42,
          ),
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _IntakePalette.coral,
            inactiveTrackColor: _IntakePalette.line,
            thumbColor: _IntakePalette.ink,
            overlayColor: _IntakePalette.coral.withValues(alpha: 0.16),
            trackHeight: 6,
          ),
          child: Slider(
            value: _currentValue.toDouble(),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            onChanged: (val) {
              setState(() {
                _currentValue = val.toInt();
                HapticFeedback.selectionClick();
              });
            },
            onChangeEnd: (val) => widget.onSelect(val.toInt()),
          ),
        ),
      ],
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
    String content = message.content;

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
              color: _IntakePalette.paper,
              border: Border.all(color: _IntakePalette.line),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 17,
                color: _IntakePalette.coralDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isUser
                  ? MediaQuery.sizeOf(context).width * 0.74
                  : double.infinity,
            ),
            padding: EdgeInsets.all(isUser ? 12 : 16),
            decoration: BoxDecoration(
              color: isUser ? _IntakePalette.ink : _IntakePalette.paper,
              border: Border.all(
                color: isUser ? Colors.transparent : _IntakePalette.line,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isUser ? 22 : 6),
                topRight: Radius.circular(isUser ? 6 : 22),
                bottomLeft: const Radius.circular(22),
                bottomRight: const Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(
                  color: _IntakePalette.ink.withValues(
                    alpha: isUser ? 0.14 : 0.06,
                  ),
                  blurRadius: isUser ? 18 : 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              content,
              style: AppTypography.body.copyWith(
                color: isUser ? Colors.white : _IntakePalette.ink,
                fontWeight: isUser ? FontWeight.w600 : FontWeight.normal,
                height: isUser ? null : 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Streaming bubble
class _StreamingBubble extends StatefulWidget {
  const _StreamingBubble({required this.content});
  final String content;

  @override
  State<_StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<_StreamingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
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
            color: _IntakePalette.paper,
            border: Border.all(color: _IntakePalette.line),
          ),
          child: const Center(
            child: Icon(
              Icons.auto_awesome,
              size: 17,
              color: _IntakePalette.coralDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _IntakePalette.paper,
              border: Border.all(color: _IntakePalette.line),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(
                  color: _IntakePalette.ink.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              '${widget.content} ▋',
              style: AppTypography.body.copyWith(
                color: _IntakePalette.ink,
                height: 1.45,
              ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _IntakePalette.paper,
            border: Border.all(color: _IntakePalette.line),
          ),
          child: const Center(
            child: Icon(
              Icons.auto_awesome,
              size: 17,
              color: _IntakePalette.coralDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _IntakePalette.paper,
            border: Border.all(color: _IntakePalette.line),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(22),
            ),
            boxShadow: [
              BoxShadow(
                color: _IntakePalette.ink.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
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
                      color: _IntakePalette.muted.withValues(alpha: opacity),
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
