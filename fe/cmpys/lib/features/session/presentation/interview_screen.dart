import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../controllers/session_controller.dart';
import '../models/session_models.dart';

abstract final class _InterviewPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coral = AppColors.brandAccent;
}

/// Phase 3: chat-style achievement interview with the selected idol.
class InterviewScreen extends ConsumerStatefulWidget {
  const InterviewScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends ConsumerState<InterviewScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_InterviewMessage> _messages = [];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_InterviewMessage(content: text, isUser: true));
    });
    _messageController.clear();
    _scrollToBottom();

    ref.read(sessionControllerProvider.notifier).sendInterviewMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      if (next is SessionActive) {
        if (prev is SessionActive &&
            prev.isStreaming &&
            !next.isStreaming &&
            next.streamedContent.isNotEmpty) {
          setState(() {
            _messages.add(
              _InterviewMessage(content: next.streamedContent, isUser: false),
            );
          });
          _scrollToBottom();
        }

        if (next.session.phase == SessionPhase.comparison) {
          context.go('/agentic/results', extra: next.session.id);
        }
      }
    });

    final state = ref.watch(sessionControllerProvider);
    final isStreaming = state is SessionActive && state.isStreaming;
    final turnCount = state is SessionActive
        ? state.session.interviewTurnCount
        : 0;
    final idolName = state is SessionActive
        ? state.session.selectedIdol?.name ?? 'Your mentor'
        : 'Your mentor';

    return Scaffold(
      backgroundColor: _InterviewPalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _InterviewPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _InterviewPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.5, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _InterviewHeader(idolName: idolName, turnCount: turnCount),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  itemCount:
                      _messages.length +
                      (isStreaming ? 1 : 0) +
                      (_messages.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_messages.isEmpty && index == 0) {
                      return _InterviewBubble(
                        message: _InterviewMessage(
                          content:
                              'I will ask about achievements, constraints, and the choices behind your progress. Start with one recent win or obstacle.',
                          isUser: false,
                        ),
                      );
                    }

                    final offset = _messages.isEmpty ? 1 : 0;
                    final messageIndex = index - offset;
                    if (messageIndex < _messages.length) {
                      return _InterviewBubble(message: _messages[messageIndex]);
                    }

                    if (state is SessionActive &&
                        state.streamedContent.isNotEmpty) {
                      return _InterviewBubble(
                        message: _InterviewMessage(
                          content: state.streamedContent,
                          isUser: false,
                        ),
                        isStreaming: true,
                      );
                    }
                    return const _TypingBubble();
                  },
                ),
              ),
              _InterviewComposer(
                controller: _messageController,
                isStreaming: isStreaming,
                onSend: _sendMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InterviewHeader extends StatelessWidget {
  const _InterviewHeader({required this.idolName, required this.turnCount});

  final String idolName;
  final int turnCount;

  @override
  Widget build(BuildContext context) {
    final progress = ((turnCount + 1) / 5).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _InterviewPalette.paper.withValues(alpha: 0.92),
          borderRadius: AppRadii.br20,
          border: Border.all(color: _InterviewPalette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _InterviewPalette.mint,
                    borderRadius: AppRadii.br12,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: _InterviewPalette.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idolName,
                        style: AppTypography.h4.copyWith(
                          color: _InterviewPalette.ink,
                        ),
                      ),
                      Text(
                        'Achievement diagnostic ${turnCount + 1} of 5',
                        style: AppTypography.caption.copyWith(
                          color: _InterviewPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: AppRadii.brFull,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: _InterviewPalette.line,
                color: _InterviewPalette.coral,
                minHeight: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterviewBubble extends StatelessWidget {
  const _InterviewBubble({required this.message, this.isStreaming = false});

  final _InterviewMessage message;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: isUser ? _InterviewPalette.ink : _InterviewPalette.paper,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 22 : 6),
            topRight: Radius.circular(isUser ? 6 : 22),
            bottomLeft: const Radius.circular(22),
            bottomRight: const Radius.circular(22),
          ),
          border: Border.all(
            color: isUser ? Colors.transparent : _InterviewPalette.line,
          ),
          boxShadow: [
            BoxShadow(
              color: _InterviewPalette.ink.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          isStreaming ? '${message.content} ▋' : message.content,
          style: AppTypography.body.copyWith(
            color: isUser ? Colors.white : _InterviewPalette.ink,
            height: 1.45,
            fontWeight: isUser ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 42,
          child: LinearProgressIndicator(color: _InterviewPalette.coral),
        ),
      ),
    );
  }
}

class _InterviewComposer extends StatelessWidget {
  const _InterviewComposer({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: _InterviewPalette.paper.withValues(alpha: 0.94),
        border: const Border(top: BorderSide(color: _InterviewPalette.line)),
        boxShadow: [
          BoxShadow(
            color: _InterviewPalette.ink.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _InterviewPalette.canvas,
                  borderRadius: AppRadii.br16,
                  border: Border.all(color: _InterviewPalette.line),
                ),
                child: TextField(
                  controller: controller,
                  enabled: !isStreaming,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: AppTypography.body.copyWith(
                    color: _InterviewPalette.ink,
                  ),
                  cursorColor: _InterviewPalette.coral,
                  decoration: InputDecoration(
                    hintText: isStreaming
                        ? 'Waiting for response...'
                        : 'Share your answer...',
                    hintStyle: AppTypography.body.copyWith(
                      color: _InterviewPalette.muted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: _InterviewPalette.coral,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _InterviewPalette.line,
              ),
              onPressed: isStreaming ? null : onSend,
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterviewMessage {
  const _InterviewMessage({required this.content, required this.isUser});
  final String content;
  final bool isUser;
}
