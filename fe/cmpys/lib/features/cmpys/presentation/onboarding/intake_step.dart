import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/network/coalesced_text.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../session/data/session_repository.dart';
import '../../../session/models/session_models.dart';
import '../../data/cmpys_seed.dart';

/// Idol-led intake — fully AI-driven.
///
/// Drives the backend `/sessions/{id}/interview` SSE endpoint: the mentor asks
/// LLM-generated questions *in its own voice*, in real time, adapting to the
/// user's previous answers. The mentor decides when it has enough; the session
/// then transitions to the comparison phase and we advance.
///
/// There is **no scripted fallback** — if the backend is unreachable the user
/// sees an explicit error with a retry, never canned questions.
class CmpysIntakeChatStep extends ConsumerStatefulWidget {
  const CmpysIntakeChatStep({
    super.key,
    required this.idol,
    required this.draft,
    required this.onDone,
  });
  final CmpysIdol idol;
  final CmpysOnboardingDraft draft;
  final VoidCallback onDone;

  @override
  ConsumerState<CmpysIntakeChatStep> createState() =>
      _CmpysIntakeChatStepState();
}

class _CmpysIntakeChatStepState extends ConsumerState<CmpysIntakeChatStep> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_M> _msgs = [];
  bool _scrollFrameScheduled = false;
  bool _scrollShouldAnimate = false;

  bool _typing = true; // waiting for first chunk of a turn
  bool _streaming = false; // chunks arriving

  /// In-flight mentor text — a [ValueNotifier] so each SSE chunk repaints
  /// only the streaming bubble instead of rebuilding the whole step.
  final ValueNotifier<String> _streamingText = ValueNotifier('');
  bool _awaitingText = false; // user's turn to answer
  bool _finished = false; // phase transitioned, advancing
  String? _error; // visible error; retry re-sends _lastSent
  String? _lastSent;
  bool _lastSentWasKickoff = false;
  int _turns = 0;
  int _maxTurns = 5;

  /// Hidden protocol message that elicits the mentor's opening question.
  /// Sent with `isKickoff: true` so the backend never persists it as the
  /// user's own words.
  static const _kickoff = 'Hi — I’m ready. Ask me your first question.';

  /// Machine-read end-of-interview token the mentor appends to its closing
  /// turn. Stripped from anything shown to the user.
  static const _completionMarker = '[INTERVIEW_COMPLETE]';

  String _stripMarker(String text) =>
      text.replaceAll(_completionMarker, '').trimRight();

  String? get _sessionId => widget.draft.sessionId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _streamingText.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _error = null;
      _typing = true;
    });
    if (_sessionId == null) {
      setState(() {
        _typing = false;
        _error =
            'No active session. Go back to mentor selection and try again.';
      });
      return;
    }
    try {
      final repo = ref.read(sessionRepositoryProvider);
      var session = await repo.getSession(_sessionId!);
      if (session.phase == SessionPhase.idolSelection ||
          session.phase == SessionPhase.intake) {
        session = await repo.selectIdol(
          _sessionId!,
          SelectIdolRequest(idolName: widget.idol.name),
        );
      }
      if (session.phase == SessionPhase.comparison ||
          session.phase == SessionPhase.blueprint ||
          session.phase == SessionPhase.completed) {
        // Interview already finished in a previous attempt.
        _advance();
        return;
      }
      await _sendTurn(_kickoff, showAsUser: false, isKickoff: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _streaming = false;
        _error = 'Couldn’t reach ${widget.idol.short}. Check your connection.';
        _lastSent = _kickoff;
        _lastSentWasKickoff = true;
      });
    }
  }

  Future<void> _answer(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _msgs.add(_M(me: true, text: text.trim()));
      _awaitingText = false;
      _input.clear();
    });
    widget.draft.intakeAnswers['turn_$_turns'] = text.trim();
    _scrollToBottom();
    await _sendTurn(text.trim(), showAsUser: true);
  }

  Future<void> _retry() async {
    final last = _lastSent;
    if (last == null) {
      _bootstrap();
      return;
    }
    setState(() => _error = null);
    await _sendTurn(
      last,
      showAsUser: false,
      isRetry: true,
      isKickoff: _lastSentWasKickoff,
    );
  }

  Future<void> _sendTurn(
    String content, {
    required bool showAsUser,
    bool isRetry = false,
    bool isKickoff = false,
  }) async {
    setState(() {
      _typing = true;
      _streaming = false;
      _streamingText.value = '';
      _error = null;
    });
    _lastSent = content;
    _lastSentWasKickoff = isKickoff;

    final repo = ref.read(sessionRepositoryProvider);
    bool transition = false;
    final streamed = CoalescedText(
      onUpdate: (value) {
        if (!mounted) return;
        _streamingText.value = _stripMarker(value);
        _scrollToBottom(streaming: true);
      },
    );

    try {
      await for (final ev in repo.sendInterviewMessage(
        _sessionId!,
        content,
        isKickoff: isKickoff,
      )) {
        if (!mounted) return;
        final type = ev['type'] as String? ?? '';
        if (type == 'chunk') {
          if (_typing || !_streaming) {
            setState(() {
              _typing = false;
              _streaming = true;
            });
          }
          streamed.add(ev['content'] as String? ?? '');
        } else if (type == 'done') {
          transition = ev['phase_transition'] == true;
          _turns = (ev['turn'] as int?) ?? _turns + 1;
          _maxTurns = (ev['max_turns'] as int?) ?? _maxTurns;
        } else if (type == 'error') {
          throw StateError(ev['message']?.toString() ?? 'interview error');
        }
      }
      if (!mounted) return;
      final display = _stripMarker(streamed.close()).trim();
      if (display.isEmpty) {
        throw StateError('empty interview response');
      }

      setState(() {
        _msgs.add(_M(me: false, text: display));
        _typing = false;
        _streaming = false;
        _streamingText.value = '';
        _awaitingText = !transition;
      });
      _scrollToBottom();

      if (transition) _advance();
    } catch (e) {
      if (!mounted) return;
      debugPrint('💥 interview send failed: $e');
      setState(() {
        _typing = false;
        _streaming = false;
        _streamingText.value = '';
        _error =
            '${widget.idol.short} got cut off. Tap retry to continue the conversation.';
      });
    } finally {
      streamed.dispose();
    }
  }

  void _advance() {
    if (_finished) return;
    _finished = true;
    setState(() => _awaitingText = false);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.onDone();
    });
  }

  void _scrollToBottom({bool streaming = false}) {
    _scrollShouldAnimate = _scrollShouldAnimate || !streaming;
    if (_scrollFrameScheduled) return;
    _scrollFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollFrameScheduled = false;
      final animate = _scrollShouldAnimate;
      _scrollShouldAnimate = false;
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (!animate) {
        if (_scroll.offset < max) _scroll.jumpTo(max);
        return;
      }
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double get _progress => ((_turns / _maxTurns) * 100).clamp(5, 100).toDouble();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(child: _messages()),
        _answerArea(),
      ],
    );
  }

  Widget _header() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.hair, width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CmpysMentorAvatar(
                slug: widget.idol.slug,
                initials: widget.idol.initials,
                color: widget.idol.color,
                tint: widget.idol.tint,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.idol.name,
                      style: AppTypography.h4.copyWith(fontSize: 16),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Getting to know you',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.green2,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text('INTAKE', style: AppTypography.kicker),
            ],
          ),
          const SizedBox(height: 10),
          CmpysBar(value: _progress, height: 3, color: AppColors.green),
        ],
      ),
    );
  }

  Widget _messages() {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${widget.idol.name.toUpperCase()} · AI MENTOR',
              style: AppTypography.kicker.copyWith(fontSize: 10.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final m in _msgs) _bubble(m),
        if (_streaming) _streamingBubble(),
        if (_typing) _typingBubble(),
        if (_error != null) _errorCard(),
      ],
    );
  }

  Widget _errorCard() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.claySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3C9C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CmpysButton(
            variant: CmpysBtnVariant.outline,
            size: CmpysBtnSize.sm,
            leadingIcon: Icons.refresh_rounded,
            onTap: _retry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _avatar(28),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.hair),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: const CmpysTypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _streamingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _avatar(28),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.hair),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: _streamingText,
                builder: (_, text, _) => Text(
                  text,
                  style: AppTypography.body.copyWith(
                    fontSize: 15.5,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(double size) => CmpysMentorAvatar(
    slug: widget.idol.slug,
    initials: widget.idol.initials,
    color: widget.idol.color,
    tint: widget.idol.tint,
    size: size,
  );

  Widget _bubble(_M m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: m.me
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!m.me) _avatar(28),
          if (!m.me) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                gradient: m.me ? AppColors.gradGreen : null,
                color: m.me ? null : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(m.me ? 18 : 6),
                  topRight: const Radius.circular(18),
                  bottomLeft: const Radius.circular(18),
                  bottomRight: Radius.circular(m.me ? 6 : 18),
                ),
                border: m.me
                    ? null
                    : Border.all(color: AppColors.hair, width: 1),
              ),
              child: Text(
                m.text,
                style: AppTypography.body.copyWith(
                  fontSize: 15.5,
                  height: 1.45,
                  color: m.me ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerArea() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final pad = EdgeInsets.fromLTRB(14, 10, 14, 18 + bottomInset);

    if (!_awaitingText) {
      final status = _finished
          ? 'Analyzing your answers…'
          : _error != null
          ? 'Waiting to retry…'
          : '${widget.idol.short} is thinking…';
      return Container(
        padding: pad,
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.hair, width: 1)),
        ),
        child: Center(
          child: Text(
            status,
            style: AppTypography.caption.copyWith(
              color: AppColors.ink3,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: pad,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.hair, width: 1)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hair2, width: 1.5),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                autofocus: true,
                style: AppTypography.body.copyWith(fontSize: 15.5),
                cursorColor: AppColors.green,
                decoration: const InputDecoration(
                  hintText: 'Type your answer…',
                  border: InputBorder.none,
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _answer(_input.text),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (_, value, _) => Container(
                  width: 44,
                  height: 44,
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: BoxDecoration(
                    color: value.text.trim().isEmpty
                        ? AppColors.hair2
                        : AppColors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _M {
  _M({required this.me, required this.text});
  final bool me;
  final String text;
}
