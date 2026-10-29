import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/coalesced_text.dart';
import '../../../../core/ui/motion/motion_config.dart';
import '../../../../core/ui/v3/v3.dart';
import '../../../session/data/session_repository.dart';
import '../../../session/models/interview_response_ui.dart';
import '../../../session/models/session_models.dart';
import '../../data/cmpys_seed.dart';
import 'intake_answer_composer.dart';
import 'mentor_image.dart';

/// Idol-led intake — fully AI-driven (design `v3/onboard2.jsx` `Intake`).
///
/// Drives the backend `/sessions/{id}/interview` SSE endpoint: the mentor asks
/// LLM-generated questions *in its own voice*, adapting to the user's previous
/// answers, and each `done` event carries the control for the next answer.
/// The server owns completion; the closing line is followed by "Open the
/// mentor lab".
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
  final ScrollController _scroll = ScrollController();
  final List<_M> _msgs = [];

  /// Keeps the answer panel's state (focus, typed text) when
  /// [V3FooterScaffold] moves it between its overlay and keyboard slots.
  final GlobalKey _panelKey = GlobalKey(debugLabel: 'intake-panel');
  bool _scrollFrameScheduled = false;
  bool _scrollShouldAnimate = false;
  double _bodyBottomPadding = -1;

  bool _typing = true; // waiting for the first chunk of a turn
  InterviewResponseUi? _responseUi; // user's active response composer
  String? _questionId;
  bool _finished = false; // the server closed the interview
  String? _error; // visible error; retry re-sends _lastSent
  String? _validationError; // recoverable validation shown in the composer
  String? _validationDraft; // rejected text kept editable for correction
  String? _lastSent;
  bool _lastSentWasKickoff = false;
  bool _lastSentMissingEvidence = false;
  String? _lastQuestionId;
  _OptimisticAnswer? _optimisticAnswer;
  int _turns = 0;

  /// New (v3) sessions have 12 answer keys and 13 turns; the server's `done`
  /// event corrects this for legacy sessions (9 turns).
  int _maxTurns = 13;
  Timer? _advanceTimer;
  bool _advanced = false;

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
    _advanceTimer?.cancel();
    _scroll.dispose();
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
          SelectIdolRequest(
            idolName: widget.idol.name,
            wikidataId: widget.idol.wikidataId,
          ),
        );
      }
      if (session.phase == SessionPhase.comparison ||
          session.phase == SessionPhase.blueprint ||
          session.phase == SessionPhase.completed) {
        widget.draft.backendIdolId = session.selectedIdol?.id;
        // Interview already finished in a previous attempt.
        if (mounted) _advance();
        return;
      }
      widget.draft.backendIdolId = session.selectedIdol?.id;
      await _sendTurn(_kickoff, isKickoff: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _error = _setupErrorMessage(e);
        // Mentor selection did not complete, so Retry must re-run bootstrap
        // and selection. Sending the kickoff directly would always 409.
        _lastSent = null;
        _lastSentWasKickoff = false;
        _lastSentMissingEvidence = false;
        _lastQuestionId = null;
      });
    }
  }

  Future<void> _answer(String text, {bool missingEvidence = false}) async {
    if (text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final answeredQuestionId = _questionId;
    final answeredResponseUi = _responseUi;
    final answerKey = answeredQuestionId ?? 'turn_$_turns';
    final answer = text.trim();
    final bubble = _M(me: true, text: answer, missing: missingEvidence);
    final hadPreviousDraft = widget.draft.intakeAnswers.containsKey(answerKey);
    final previousDraft = widget.draft.intakeAnswers[answerKey];
    setState(() {
      _msgs.add(bubble);
      _responseUi = null;
      _questionId = null;
      _validationError = null;
      _validationDraft = null;
      _optimisticAnswer = _OptimisticAnswer(
        bubble: bubble,
        draftKey: answerKey,
        hadPreviousDraft: hadPreviousDraft,
        previousDraft: previousDraft,
        responseUi: answeredResponseUi,
        questionId: answeredQuestionId,
      );
    });
    widget.draft.intakeAnswers[answerKey] = answer;
    _scrollToBottom();
    await _sendTurn(
      answer,
      questionId: answeredQuestionId,
      missingEvidence: missingEvidence,
    );
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
      isKickoff: _lastSentWasKickoff,
      questionId: _lastQuestionId,
      missingEvidence: _lastSentMissingEvidence,
    );
  }

  Future<void> _sendTurn(
    String content, {
    bool isKickoff = false,
    String? questionId,
    bool missingEvidence = false,
  }) async {
    setState(() {
      _typing = true;
      _error = null;
    });
    _lastSent = content;
    _lastSentWasKickoff = isKickoff;
    _lastSentMissingEvidence = missingEvidence;
    _lastQuestionId = questionId;

    final repo = ref.read(sessionRepositoryProvider);
    bool transition = false;
    InterviewResponseUi? nextResponseUi;
    String? nextQuestionId;
    // The mentor's reply streams into one bubble that stays in the transcript
    // when the turn completes, so its word-by-word reveal is not restarted.
    _M? live;
    var accepting = true;
    final streamed = CoalescedText(
      onUpdate: (value) {
        if (!mounted || !accepting) return;
        final text = _stripMarker(value);
        if (text.trim().isEmpty) return;
        setState(() {
          final bubble = live;
          if (bubble == null) {
            final created = _M(me: false, text: text, stream: true);
            live = created;
            _msgs.add(created);
            _typing = false;
          } else {
            bubble.text = text;
          }
        });
        _scrollToBottom(streaming: true);
      },
    );

    try {
      await for (final ev in repo.sendInterviewMessage(
        _sessionId!,
        content,
        isKickoff: isKickoff,
        questionId: questionId,
        missingEvidence: missingEvidence,
      )) {
        if (!mounted) return;
        final type = ev['type'] as String? ?? '';
        if (type == 'chunk') {
          streamed.add(ev['content'] as String? ?? '');
        } else if (type == 'done') {
          transition = ev['phase_transition'] == true;
          _turns = (ev['turn'] as int?) ?? _turns + 1;
          _maxTurns = (ev['max_turns'] as int?) ?? _maxTurns;
          if (!transition) {
            nextResponseUi = InterviewResponseUi.fromJson(ev['response_ui']);
            nextQuestionId = ev['question_id']?.toString();
          }
        } else if (type == 'error') {
          throw _InterviewStreamError(
            message: ev['message']?.toString() ?? 'interview error',
            code: ev['code']?.toString(),
          );
        }
      }
      if (!mounted) return;
      final display = _stripMarker(streamed.close()).trim();
      accepting = false;
      if (display.isEmpty) {
        throw StateError('empty interview response');
      }

      setState(() {
        final bubble = live;
        if (bubble == null) {
          _msgs.add(_M(me: false, text: display, stream: true, complete: true));
        } else {
          bubble
            ..text = display
            ..complete = true;
        }
        _typing = false;
        _responseUi = transition
            ? null
            : nextResponseUi ?? InterviewResponseUi.text();
        _questionId = transition ? null : nextQuestionId;
        _validationError = null;
        _validationDraft = null;
        _optimisticAnswer = null;
        if (transition) _finished = true;
      });
      _scrollToBottom();
    } catch (e) {
      accepting = false;
      if (!mounted) return;
      // A failed or superseded turn never leaves partial mentor text behind.
      final partial = live;
      if (partial != null) _msgs.remove(partial);
      debugPrint('💥 interview send failed: $e');
      final turnInProgress =
          e is ApiError && e.code == 'interview_turn_in_progress';
      final invalidAnswer =
          (e is ApiError && e.code == 'invalid_interview_answer') ||
          (e is _InterviewStreamError && e.code == 'invalid_interview_answer');
      if (invalidAnswer) {
        // Validation rejected this answer without advancing the interview.
        // Restore the same composer locally so the question is not replayed
        // or duplicated, and keep the user's text available for correction.
        streamed.dispose();
        final optimistic = _optimisticAnswer;
        setState(() {
          _discardOptimisticAnswer();
          _responseUi = optimistic?.responseUi ?? InterviewResponseUi.text();
          _questionId = optimistic?.questionId;
          _validationError = switch (e) {
            ApiError() => e.message,
            _InterviewStreamError() => e.message,
            _ => 'Please check this answer and try again.',
          };
          _validationDraft = content;
          _typing = false;
          _error = null;
          _lastSent = null;
          _lastSentWasKickoff = false;
          _lastSentMissingEvidence = false;
          _lastQuestionId = null;
        });
        _scrollToBottom();
        return;
      }
      final streamNeedsResync =
          e is _InterviewStreamError &&
          const {
            'stale_interview_question',
            'interview_session_changed',
            'interview_turn_superseded',
          }.contains(e.code);
      final rejectedOptimisticAnswer =
          e is ApiError && e.statusCode == 409 && !turnInProgress;
      final shouldResync =
          (!isKickoff &&
              e is ApiError &&
              e.statusCode == 409 &&
              !turnInProgress) ||
          streamNeedsResync;
      if (shouldResync) {
        // Stop the failed stream's coalescing timer before bootstrap starts a
        // replacement stream, or a delayed partial chunk can overwrite it.
        streamed.dispose();
        setState(() {
          if (rejectedOptimisticAnswer) _discardOptimisticAnswer();
          _typing = false;
          _error = null;
          _validationError = null;
          _validationDraft = null;
          _lastSent = null;
          _lastSentWasKickoff = false;
          _lastSentMissingEvidence = false;
          _lastQuestionId = null;
        });
        await _bootstrap();
        return;
      }
      final setupConflict = isKickoff && e is ApiError && e.statusCode == 409;
      setState(() {
        _typing = false;
        _error = _turnErrorMessage(e);
        if (setupConflict) {
          _lastSent = null;
          _lastSentWasKickoff = false;
          _lastSentMissingEvidence = false;
          _lastQuestionId = null;
        }
      });
    } finally {
      streamed.dispose();
    }
  }

  String _setupErrorMessage(Object error) {
    if (error is NetworkError) {
      return 'Couldn’t reach ${widget.idol.short}. Check your connection and retry.';
    }
    if (error is TimeoutError) {
      return '${widget.idol.short} is taking longer than expected. Tap retry.';
    }
    return 'Couldn’t prepare ${widget.idol.short}. Tap retry to try the setup again.';
  }

  void _discardOptimisticAnswer() {
    final optimistic = _optimisticAnswer;
    if (optimistic == null) return;
    _msgs.remove(optimistic.bubble);
    if (optimistic.hadPreviousDraft) {
      widget.draft.intakeAnswers[optimistic.draftKey] =
          optimistic.previousDraft!;
    } else {
      widget.draft.intakeAnswers.remove(optimistic.draftKey);
    }
    _optimisticAnswer = null;
  }

  String _turnErrorMessage(Object error) {
    if (error is ApiError && error.code == 'interview_turn_in_progress') {
      return '${widget.idol.short} is still finishing that reply. Tap retry in a moment.';
    }
    if (error is _InterviewStreamError &&
        error.code == 'interview_turn_in_progress') {
      return '${widget.idol.short} is still finishing that reply. Tap retry in a moment.';
    }
    if (error is ApiError && error.statusCode == 409) {
      return '${widget.idol.short} isn’t ready yet. Tap retry to finish setup.';
    }
    if (error is SseIncompleteException) {
      return '${widget.idol.short} got cut off before finishing. Tap retry.';
    }
    if (error is NetworkError) {
      return 'Couldn’t reach ${widget.idol.short}. Check your connection and retry.';
    }
    if (error is TimeoutError) {
      return '${widget.idol.short} is taking longer than expected. Tap retry.';
    }
    return '${widget.idol.short} couldn’t finish that reply. Tap retry.';
  }

  /// The interview finished in an earlier attempt: there is no closing line
  /// to show here, so move on to the mentor lab.
  void _advance() {
    if (_finished) return;
    setState(() {
      _finished = true;
      _typing = false;
      _responseUi = null;
      _questionId = null;
      _optimisticAnswer = null;
    });
    _advanceTimer = Timer(const Duration(milliseconds: 600), _openLab);
  }

  void _openLab() {
    _advanceTimer?.cancel();
    if (_advanced || !mounted) return;
    _advanced = true;
    widget.onDone();
  }

  void _scrollToBottom({bool streaming = false}) {
    _scrollShouldAnimate = _scrollShouldAnimate || !streaming;
    if (_scrollFrameScheduled) return;
    _scrollFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollFrameScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final animate = _scrollShouldAnimate && MotionConfig.enabled(context);
      _scrollShouldAnimate = false;
      final max = _scroll.position.maxScrollExtent;
      if (!animate) {
        if (_scroll.offset < max) _scroll.jumpTo(max);
        return;
      }
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 280),
        curve: AppMotion.out,
      );
    });
  }

  // ── Header ───────────────────────────────────────────────────────────────

  /// Visible questions: every turn but the closing one.
  int get _questionTotal => math.max(1, _maxTurns - 1);

  /// The question on screen, or the one being prepared after an answer.
  int get _questionNumber {
    final n = _optimisticAnswer != null ? _turns + 1 : _turns;
    return n.clamp(1, _questionTotal);
  }

  double get _progress => _finished
      ? 1
      : ((_questionNumber - 1) / _questionTotal).clamp(0, 1).toDouble();

  Widget _avatar(double size) => V3Avatar(
    image: cmpysIdolImage(widget.idol),
    initials: widget.idol.initials,
    tint: widget.idol.tint,
    size: size,
    gray: true,
  );

  Widget _header() {
    // V3TopBar caps its own text scaling, so the fixed 52 pt bar never
    // overflows at very large text sizes.
    return V3TopBar(
      solid: true,
      title: 'Intake with ${widget.idol.short}',
      sub: _finished
          ? 'Complete'
          : 'Question $_questionNumber of $_questionTotal',
      right: V3Ring(
        value: _progress,
        size: 34,
        strokeWidth: 3,
        color: AppColors.ember,
        child: _avatar(24),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The panel keeps at least ~160 pt of transcript (the question) in
        // view on a phone, and never less than 55% of the space under the
        // bar; a taller control scrolls inside it.
        final available =
            constraints.maxHeight - 52 - MediaQuery.paddingOf(context).top;
        final panelMax = math.max(
          0.0,
          math.max(available * 0.55, available - 160) - 24,
        );
        return V3FooterScaffold(
          topBar: _header(),
          footerHorizontalPadding: 16,
          keyboardBottomPadding: 12,
          body: (context, bottomPadding) {
            if (bottomPadding != _bodyBottomPadding) {
              _bodyBottomPadding = bottomPadding;
              _scrollToBottom(streaming: true);
            }
            return _transcript(bottomPadding);
          },
          footer: KeyedSubtree(key: _panelKey, child: _panel(panelMax)),
        );
      },
    );
  }

  Widget _transcript(double bottomPadding) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scrollToBottom(streaming: true);
        return true;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bubbleMax = math.max(120.0, (constraints.maxWidth - 32) * 0.78);
          return SingleChildScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding + 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: Text(
                    'Answers are saved to your session as you go.',
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      11.5,
                    ).copyWith(color: AppColors.ink3),
                  ),
                ),
                for (final m in _msgs)
                  _Bubble(
                    key: ObjectKey(m),
                    me: m.me,
                    maxWidth: bubbleMax,
                    avatar: m.me ? null : _avatar(28),
                    tag: m.missing
                        ? const V3Tag(
                            color: AppColors.gold2,
                            background: AppColors.goldSoft,
                            icon: V3Icons.info,
                            child: Text('Recorded as missing evidence'),
                          )
                        : null,
                    child: _messageText(m),
                  ),
                if (_typing && _error == null)
                  _Bubble(
                    key: const ValueKey('intake-typing'),
                    me: false,
                    maxWidth: bubbleMax,
                    avatar: _avatar(28),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: V3Typing(),
                    ),
                  ),
                if (_error != null) _errorCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _messageText(_M m) {
    final style = AppTypography.sans(
      15,
    ).copyWith(color: m.me ? Colors.white : AppColors.ink, height: 1.45);
    if (m.stream && !m.streamDone) {
      return SizeChangedLayoutNotifier(
        child: V3Stream(
          text: m.text,
          speed: const Duration(milliseconds: 22),
          style: style,
          onDone: () {
            // Settle once the whole reply (not a partial chunk) has shown.
            if (m.complete) m.streamDone = true;
          },
        ),
      );
    }
    return _IntakeMessageText(
      text: m.text,
      isAnswer: m.me,
      isCurrent: identical(m, _msgs.last),
      style: style,
    );
  }

  Widget _errorCard() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: AppRadii.br16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: V3Icon(V3Icons.alert, size: 17, color: AppColors.danger),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: AppTypography.sans(
                    13,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.danger, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          V3Button(
            kind: V3ButtonKind.line,
            size: V3Size.sm,
            icon: V3Icons.refresh,
            onPressed: _retry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// The answer panel: it rises in once a question is answerable, and becomes
  /// "Open the mentor lab" after the closing line.
  Widget _panel(double maxHeight) {
    if (_finished && !_advanced && _advanceTimer == null) {
      return V3Rise(
        key: const ValueKey('intake-finish'),
        duration: const Duration(milliseconds: 450),
        offset: 40,
        child: V3Button(
          full: true,
          icon: V3Icons.sparkle,
          onPressed: _openLab,
          child: const Text('Open the mentor lab'),
        ),
      );
    }
    final responseUi = _responseUi;
    if (responseUi == null || _finished) return const SizedBox.shrink();
    final questionKey = _questionId ?? 'turn-$_turns-${responseUi.kind.name}';
    return V3Rise(
      key: ValueKey('panel-$questionKey'),
      duration: const Duration(milliseconds: 450),
      offset: 40,
      child: IntakeAnswerComposer(
        key: ValueKey(questionKey),
        responseUi: responseUi,
        initialText: _validationDraft,
        validationMessage: _validationError,
        maxHeight: maxHeight,
        onSubmit: _answer,
        onSubmitMissingEvidence: (text) => _answer(text, missingEvidence: true),
      ),
    );
  }
}

/// One transcript bubble (the design's `Bubble`): mentor turns on card with
/// the grey avatar, the learner's on ink, and an optional tag underneath.
class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.me,
    required this.maxWidth,
    required this.child,
    this.avatar,
    this.tag,
  });

  final bool me;
  final double maxWidth;
  final Widget child;
  final Widget? avatar;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(20);
    const tail = Radius.circular(6);
    return V3Rise(
      duration: const Duration(milliseconds: 450),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: me
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!me && avatar != null) ...[avatar!, const SizedBox(width: 8)],
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: me ? AppColors.ink : AppColors.card,
                        borderRadius: BorderRadius.only(
                          topLeft: round,
                          topRight: round,
                          bottomLeft: me ? round : tail,
                          bottomRight: me ? tail : round,
                        ),
                        border: me ? null : Border.all(color: AppColors.hair),
                      ),
                      child: child,
                    ),
                    if (tag != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: tag,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keep the current question complete, while earlier long turns remain
/// available on demand instead of filling the conversation with repeated text.
class _IntakeMessageText extends StatefulWidget {
  const _IntakeMessageText({
    required this.text,
    required this.isAnswer,
    required this.isCurrent,
    required this.style,
  });

  final String text;
  final bool isAnswer;
  final bool isCurrent;
  final TextStyle style;

  @override
  State<_IntakeMessageText> createState() => _IntakeMessageTextState();
}

class _IntakeMessageTextState extends State<_IntakeMessageText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final collapsible = !widget.isCurrent && widget.text.length > 240;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.text,
          maxLines: collapsible && !_expanded ? 3 : null,
          overflow: collapsible && !_expanded ? TextOverflow.ellipsis : null,
          style: widget.style,
        ),
        if (collapsible)
          V3Pressable(
            onTap: () => setState(() => _expanded = !_expanded),
            focusRadius: AppRadii.br8,
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                _expanded ? 'Show less' : 'Read full message',
                style: AppTypography.sans(13, FontWeight.w600).copyWith(
                  color: widget.isAnswer
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.ember2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InterviewStreamError implements Exception {
  const _InterviewStreamError({required this.message, this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class _M {
  _M({
    required this.me,
    required this.text,
    this.missing = false,
    this.stream = false,
    this.complete = false,
  });
  final bool me;
  String text;

  /// The learner's answer was sent as missing evidence.
  final bool missing;

  /// A mentor reply revealed word by word ([V3Stream]).
  final bool stream;

  /// The turn's `done` arrived, so [text] is final.
  bool complete;

  /// The reveal finished; render plain text from now on.
  bool streamDone = false;
}

class _OptimisticAnswer {
  const _OptimisticAnswer({
    required this.bubble,
    required this.draftKey,
    required this.hadPreviousDraft,
    required this.previousDraft,
    required this.responseUi,
    required this.questionId,
  });

  final _M bubble;
  final String draftKey;
  final bool hadPreviousDraft;
  final String? previousDraft;
  final InterviewResponseUi? responseUi;
  final String? questionId;
}
