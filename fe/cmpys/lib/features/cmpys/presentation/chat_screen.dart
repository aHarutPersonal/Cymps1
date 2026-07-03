import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../session/data/session_repository.dart';
import '../../session/models/session_models.dart';
import '../data/cmpys_record_data.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'detail_screens.dart';

/// CMPYS Chat — real AI conversation with the mentor.
///
/// Every reply streams from the backend `/sessions/{id}/guided-learning`
/// endpoint (the mentor persona LLM). There is no canned reply bot — if the
/// backend is unreachable, an explicit error bubble with retry appears.
///
/// The sparkle "report a win" flow still files the win into your record
/// (dimension classified locally), but the mentor's spoken reaction is the
/// real model reply, which also becomes the record entry's mentor note.
class CmpysChatScreen extends ConsumerStatefulWidget {
  const CmpysChatScreen({super.key});

  @override
  ConsumerState<CmpysChatScreen> createState() => _CmpysChatScreenState();
}

class _CmpysChatScreenState extends ConsumerState<CmpysChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_Msg> _msgs = [];
  bool _waiting = false; // sent, no chunks yet
  bool _streaming = false;

  /// In-flight reply text — a [ValueNotifier] so each SSE chunk repaints only
  /// the streaming bubble instead of rebuilding the whole screen.
  final ValueNotifier<String> _streamingText = ValueNotifier('');
  bool _winMode = false;
  String? _error;
  String? _lastSent;
  String? _pendingWinText; // win being reported, waiting for AI reaction

  static const _suggestions = [
    'What should I focus on first?',
    'I missed two days. What now?',
    'What should I read this week?',
  ];

  bool get _busy => _waiting || _streaming;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _streamingText.dispose();
    super.dispose();
  }

  bool _needsOnboarding = false;

  /// Session id from the last successful resolution — avoids a
  /// `GET /sessions/current` round-trip (plus store sync) before every send.
  /// Cleared on stream failure so the next attempt re-resolves.
  String? _cachedSessionId;

  /// Resolves a chat-capable session from the backend (source of truth) and
  /// keeps the local store in sync — this is also what corrects the mentor
  /// header if local state drifted. Guided-learning requires the session to
  /// be at blueprint or later; an unfinished onboarding sets
  /// [_needsOnboarding] so the error card offers the right action.
  Future<String?> _resolveSessionId() async {
    _needsOnboarding = false;
    Session? session;
    try {
      session = await ref.read(sessionRepositoryProvider).getLatestSession();
    } catch (_) {
      session = null;
    }
    if (session == null) {
      // Backend unreachable or no session at all — fall back to the stored id
      // (the call itself will fail visibly if it's invalid).
      final stored = ref.read(cmpysStoreProvider).sessionId;
      if (stored != null && stored.isNotEmpty) return stored;
      _needsOnboarding = true;
      return null;
    }

    // Align local state with the backend (mentor identity, results, id).
    ref.read(cmpysStoreProvider.notifier).syncFromSession(session);

    switch (session.phase) {
      case SessionPhase.blueprint:
      case SessionPhase.guidedLearning:
      case SessionPhase.completed:
        return session.id;
      default:
        _needsOnboarding = true;
        return null;
    }
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;

    final reportingWin = _winMode;
    setState(() {
      _msgs.add(_Msg(me: true, text: text));
      _input.clear();
      _winMode = false;
      _error = null;
      _waiting = true;
      _streamingText.value = '';
      if (reportingWin) _pendingWinText = text;
    });
    _scrollToBottom();
    await _streamReply(text, reportingWin: reportingWin);
  }

  Future<void> _retry() async {
    final last = _lastSent;
    if (last == null || _busy) return;
    setState(() {
      _error = null;
      _waiting = true;
      _streamingText.value = '';
    });
    await _streamReply(last, reportingWin: _pendingWinText != null);
  }

  Future<void> _streamReply(String text, {required bool reportingWin}) async {
    _lastSent = text;
    final idol = ref.read(cmpysStoreProvider).idol;

    final hadCachedId = _cachedSessionId != null;
    final sessionId = _cachedSessionId ?? await _resolveSessionId();
    if (sessionId == null) {
      if (!mounted) return;
      final mentor = ref.read(cmpysStoreProvider).idol.short;
      setState(() {
        _waiting = false;
        _error = _needsOnboarding
            ? 'Your onboarding with $mentor isn’t finished — complete it to unlock the conversation.'
            : 'Couldn’t reach your mentor session. Check your connection.';
      });
      return;
    }
    _cachedSessionId = sessionId;

    // For win reports, frame the message so the mentor reacts in character.
    final content = reportingWin
        ? 'I want to report a win I just achieved: "$text". React briefly in your own voice — does it move my trajectory?'
        : text;

    String acc = '';
    try {
      final repo = ref.read(sessionRepositoryProvider);
      await for (final ev
          in repo.sendGuidedLearningMessage(sessionId, content)) {
        if (!mounted) return;
        final type = ev['type'] as String? ?? '';
        if (type == 'chunk') {
          acc += (ev['content'] as String? ?? '');
          if (_waiting || !_streaming) {
            setState(() {
              _waiting = false;
              _streaming = true;
            });
          }
          _streamingText.value = acc;
          _scrollToBottom(streaming: true);
        } else if (type == 'error') {
          throw StateError(ev['message']?.toString() ?? 'chat error');
        }
      }
      if (!mounted) return;
      if (acc.trim().isEmpty) throw StateError('empty reply');

      setState(() {
        _msgs.add(_Msg(me: false, text: acc.trim(), rich: true));
        _streaming = false;
        _streamingText.value = '';
      });
      _scrollToBottom();

      // File the reported win with the AI's reaction as the mentor note.
      if (reportingWin && _pendingWinText != null) {
        final winText = _pendingWinText!;
        _pendingWinText = null;
        final dim = classifyWin(winText);
        ref.read(cmpysStoreProvider.notifier).addWin(
              title: winText,
              dim: dim,
              age: ref.read(cmpysStoreProvider).user.age,
              impact: 2,
              source: 'chat',
              idolNote: acc.trim(),
            );
        showCmpysToast(context, 'Added to your record',
            icon: Icons.check_rounded, tone: AppColors.green);
      }
    } catch (e) {
      if (!mounted) return;
      _cachedSessionId = null;
      if (hadCachedId && acc.isEmpty) {
        // The cached id may have gone stale — re-resolve once and retry,
        // matching the pre-cache behavior of resolving before every send.
        await _streamReply(text, reportingWin: reportingWin);
        return;
      }
      setState(() {
        _waiting = false;
        _streaming = false;
        _streamingText.value = '';
        _error =
            '${idol.short} got cut off. Check your connection and tap retry.';
      });
    }
  }

  void _startWinReport() {
    if (_busy) return;
    setState(() => _winMode = !_winMode);
  }

  void _scrollToBottom({bool streaming = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (streaming) {
        // Per-chunk: don't stack 280ms animations — snap if not at bottom.
        if (_scroll.offset < max) _scroll.jumpTo(max);
        return;
      }
      _scroll.animateTo(max,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final idol = ref.watch(cmpysStoreProvider.select((s) => s.idol));
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(idol),
            Expanded(child: _messages(idol)),
            _composer(idol),
          ],
        ),
      ),
    );
  }

  Widget _header(CmpysIdol idol) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => openIdolDetail(context, idol),
            child: CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: idol.tint,
              size: 40,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(idol.name, style: AppTypography.h4.copyWith(fontSize: 16)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: AppColors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('AI mentor · always here',
                        style: AppTypography.caption.copyWith(
                            color: AppColors.green, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CmpysNotesScreen())),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.paper2,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(PhosphorIconsRegular.note,
                  size: 19, color: AppColors.ink2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messages(CmpysIdol idol) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      children: [
        Center(
          child: Column(
            children: [
              CmpysMentorAvatar(
                slug: idol.slug,
                initials: idol.initials,
                color: idol.color,
                tint: idol.tint,
                size: 56,
              ),
              const SizedBox(height: 10),
              Text(idol.name,
                  style: AppTypography.display.copyWith(
                      fontSize: 17, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  'Ask anything. Useful answers come with quick actions — save them or add them to your plan.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.ink3, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final m in _msgs) _bubble(idol, m),
        if (_streaming) _streamingBubble(idol),
        if (_waiting) _waitingBubble(idol),
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
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: AppTypography.caption.copyWith(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_needsOnboarding)
            CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.sm,
              leadingIcon: Icons.arrow_forward_rounded,
              onTap: () => context.go(AppRoutes.cmpysOnboarding),
              child: const Text('Finish onboarding'),
            )
          else if (_lastSent != null)
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

  Widget _bubble(CmpysIdol idol, _Msg m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            m.me ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!m.me) ...[
            CmpysMentorAvatar(
                slug: idol.slug,
                initials: idol.initials,
                color: idol.color,
                tint: idol.tint,
                size: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  m.me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: m.me ? AppColors.gradGreen : null,
                    color: m.me ? null : AppColors.card,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(m.me ? 18 : 6),
                      topRight: const Radius.circular(18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: Radius.circular(m.me ? 6 : 18),
                    ),
                    border: m.me ? null : Border.all(color: AppColors.hair),
                  ),
                  child: Text(m.text,
                      style: AppTypography.body.copyWith(
                          fontSize: 15.5,
                          height: 1.45,
                          color: m.me ? Colors.white : AppColors.ink)),
                ),
                if (!m.me && m.rich) ...[
                  const SizedBox(height: 8),
                  _actionPill('Add to notes', PhosphorIconsRegular.note,
                      AppColors.blue, () {
                    ref.read(cmpysStoreProvider.notifier).saveNote(
                        kind: 'chat',
                        title: 'From ${idol.short}',
                        body: m.text,
                        from: idol.short);
                    showCmpysToast(context, 'Saved to notes',
                        icon: Icons.note_alt_outlined, tone: AppColors.blue);
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionPill(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.blueSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: AppTypography.captionMedium.copyWith(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _waitingBubble(CmpysIdol idol) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: idol.tint,
              size: 28),
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
                  bottomRight: Radius.circular(16)),
            ),
            child: const CmpysTypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _streamingBubble(CmpysIdol idol) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: idol.tint,
              size: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.hair),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16)),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: _streamingText,
                builder: (_, text, _) => Text(text,
                    style: AppTypography.body
                        .copyWith(fontSize: 15.5, height: 1.45)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer(CmpysIdol idol) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final showSuggestions = _msgs.isEmpty && !_busy && !_winMode;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + bottom + 96),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSuggestions)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _suggestions.length; i++) ...[
                    _suggestionChip(_suggestions[i], i),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          if (showSuggestions) const SizedBox(height: 10),
          if (_winMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                'Reporting a win — ${idol.short} will file it in your record.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.ochre2, fontSize: 12.5),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _startWinReport,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _winMode ? AppColors.ochre : AppColors.ochreSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(PhosphorIconsFill.sparkle,
                      size: 20,
                      color: _winMode ? Colors.white : AppColors.ochre2),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(22),
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
                          style: AppTypography.body.copyWith(fontSize: 15.5),
                          cursorColor: AppColors.green,
                          decoration: InputDecoration(
                            hintText: _winMode
                                ? 'Tell ${idol.short} what you did…'
                                : 'Message ${idol.short}…',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _send(_input.text);
                        },
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _input,
                          builder: (_, value, _) => Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(bottom: 1),
                            decoration: BoxDecoration(
                              color: value.text.trim().isEmpty
                                  ? AppColors.hair2
                                  : AppColors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_upward_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String s, int i) {
    const palette = [
      (bg: AppColors.greenSoft, fg: AppColors.green2),
      (bg: AppColors.lilacSoft, fg: Color(0xFF4C3FD6)),
      (bg: AppColors.claySoft, fg: Color(0xFFC2402F)),
    ];
    final p = palette[i % palette.length];
    return GestureDetector(
      onTap: () => _send(s),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(s,
            style: AppTypography.captionMedium.copyWith(
                color: p.fg, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

class _Msg {
  _Msg({required this.me, required this.text, this.rich = false});
  final bool me;
  final String text;
  final bool rich;
}
