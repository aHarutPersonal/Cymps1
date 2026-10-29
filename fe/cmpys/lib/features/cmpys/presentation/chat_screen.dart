import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/coalesced_text.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../../plan/state/current_plan_provider.dart';
import '../../session/data/session_repository.dart';
import '../../session/models/session_models.dart';
import '../data/cmpys_seed.dart';
import '../data/reported_win.dart';
import '../state/cmpys_store.dart';
import 'detail_screens.dart';
import 'onboarding/mentor_image.dart';

/// The empty state's prompt cards (`v3/chat.jsx`).
const _emptyPrompts = <(V3Icons, String)>[
  (V3Icons.target, 'What should I focus on this week?'),
  (V3Icons.edit, 'Review my owner-earnings answer'),
  (V3Icons.book, 'What should I read next?'),
  (V3Icons.clock, 'I only have 20 minutes today'),
];

/// The suggestion chips over the composer (`CHAT_PROMPTS`). The backend
/// returns no suggestions, so these are the design's fixed prompts.
const _chatPrompts = <String>[
  'How do I estimate maintenance capex?',
  'I only have 20 minutes today',
  'Which company should I practise on?',
];

/// The guided-learning request's `content` limit (`max_length=10000`).
const chatMaxContent = 10000;

/// The most characters of a win's evidence (note, link) put in the mentor
/// prompt; the achievement keeps the full text.
const winPromptEvidenceMax = 1000;

String _clipEvidence(String text) {
  final t = text.trim();
  return t.length <= winPromptEvidenceMax
      ? t
      : '${t.substring(0, winPromptEvidenceMax)}…';
}

/// What a reported win sends to the mentor, so the reply reacts to it in
/// character: the earlier builds' sentence, byte-identical, then a fixed
/// "Win details:" block with the dimension, size and evidence. Restored
/// transcripts are recognised by it ([parseWinPrompt]), old and new.
String winPrompt(V3Win win) {
  final dim = winDimOf(win.dim);
  final size = winSizes.firstWhere(
    (s) => s.value == win.size,
    orElse: () => winSizes.first,
  );
  final head =
      'I want to report a win I just achieved: "${win.text}". React briefly in your own voice — does it move my trajectory?';
  final details = [
    'Win details:',
    '- Dimension: ${dim.label} (${dim.description})',
    '- Size: ${size.label} (${size.description})',
    if (win.note.trim().isNotEmpty) '- Evidence: ${_clipEvidence(win.note)}',
    if (win.link.trim().isNotEmpty) '- Link: ${_clipEvidence(win.link)}',
  ].join('\n');
  final prompt = '$head\n\n$details';
  // The text is capped at 120 and the evidence clipped to 1,000 each, so
  // this stays near 2,400 characters; the final clip is only a guard.
  return prompt.length <= chatMaxContent
      ? prompt
      : prompt.substring(0, chatMaxContent);
}

final _winPromptPattern = RegExp(
  r'^I want to report a win I just achieved: "([\s\S]*?)"\. React briefly in your own voice — does it move my trajectory\?(?:\n\nWin details:\n[\s\S]*)?$',
);

/// The win text of a [winPrompt] message (with or without the details
/// block), or null for any other message.
String? parseWinPrompt(String content) =>
    _winPromptPattern.firstMatch(content)?.group(1);

/// The index of the first server message that belongs to [thread] (see
/// [CmpysChatThread]).
/// - A known [CmpysChatThread.afterId] decides alone; when it has scrolled
///   out of the server's window, every returned message belongs here.
/// - Otherwise the last message whose trimmed content equals the trimmed
///   [CmpysChatThread.afterText].
/// - An unanswered turn at the boundary that has an answer after it was
///   re-sent from this thread (the server reuses a pending turn with the
///   same text instead of storing it twice), so it belongs here too.
int chatThreadStart(
  List<Map<String, dynamic>> messages,
  CmpysChatThread thread,
) {
  final int at;
  if (thread.afterId != null) {
    at = messages.indexWhere((m) => m['id'] == thread.afterId);
  } else if (thread.afterText != null) {
    final text = thread.afterText!.trim();
    at = messages.lastIndexWhere(
      (m) => (m['content']?.toString() ?? '').trim() == text,
    );
  } else {
    return 0;
  }
  if (at < 0) return 0;
  if (messages[at]['role'] == 'user' &&
      at + 1 < messages.length &&
      messages[at + 1]['role'] != 'user') {
    return at;
  }
  return at + 1;
}

/// A thread's "when" in the history sheet and the restored label: "Today",
/// a weekday within the last week ("Mon"), else a date ("12 Oct").
String chatThreadWhen(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff < 7) return DateFormat('EEE', 'en_US').format(at);
  return DateFormat('d MMM', 'en_US').format(at);
}

/// The history sheet's group for a thread last active at [at]: "This week"
/// (since Monday), "Last week" or "Earlier".
String chatThreadDay(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final weekStart = DateTime(n.year, n.month, n.day - (n.weekday - 1));
  if (!at.isBefore(weekStart)) return 'This week';
  final lastWeek = DateTime(weekStart.year, weekStart.month, weekStart.day - 7);
  if (!at.isBefore(lastWeek)) return 'Last week';
  return 'Earlier';
}

/// Mentor chat (`v3/chat.jsx` ChatTab).
///
/// Every reply streams from the backend `/sessions/{id}/guided-learning`
/// endpoint (the mentor persona LLM); the transcript is restored from its
/// `/messages` endpoint. There is no canned reply bot: when a reply fails,
/// the failed bubble offers "Retry reply", which re-sends the same message
/// (the server reuses the pending turn, so it is never duplicated).
///
/// The server keeps one transcript per session and has no thread list, so
/// conversations (History, New chat) are kept on this device in
/// [CmpysState.chatThread] / [CmpysState.chatThreads].
///
/// "Report a win" opens the [WinSheet]: the win is saved as a `manual`
/// achievement and on the record ([saveReportedWin]), then sent to the
/// mentor, whose streamed reply becomes the record entry's mentor note.
class CmpysChatScreen extends ConsumerStatefulWidget {
  const CmpysChatScreen({super.key});

  /// The composer's send button.
  static const sendKey = ValueKey('chat-send');

  @override
  ConsumerState<CmpysChatScreen> createState() => _CmpysChatScreenState();
}

class _Msg {
  _Msg({required this.me, required this.text, this.win = false, String? wire})
    : wire = wire ?? text;

  /// A message as the server stored it; a reported win is shown as its text.
  factory _Msg.server(Map<String, dynamic> m) {
    final me = m['role'] == 'user';
    final content = m['content'] as String? ?? '';
    final win = me ? parseWinPrompt(content) : null;
    return _Msg(me: me, text: win ?? content, win: win != null, wire: content);
  }

  factory _Msg.local(CmpysChatMsg m) =>
      _Msg(me: m.me, text: m.text, win: m.win);

  final bool me;
  final String text;
  final bool win;

  /// The content as sent to (or stored by) the server.
  final String wire;

  CmpysChatMsg toLocal() => CmpysChatMsg(me: me, text: text, win: win);
}

enum _FailKind { reply, notSent, onboarding }

class _Failure {
  const _Failure.reply(this.sub)
    : kind = _FailKind.reply,
      title = 'The reply didn’t finish';

  /// The server refused the message (4xx): it was not stored, so there is
  /// nothing to retry; the learner edits and sends again.
  const _Failure.notSent(this.sub)
    : kind = _FailKind.notSent,
      title = 'Your message wasn’t sent';
  const _Failure.onboarding(this.title) : kind = _FailKind.onboarding, sub = '';
  final _FailKind kind;
  final String title;
  final String sub;
}

class _CmpysChatScreenState extends ConsumerState<CmpysChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'chat composer');
  bool _scrollFrameScheduled = false;
  bool _scrollShouldAnimate = false;

  final List<_Msg> _msgs = [];
  bool _loadingHistory = true;

  /// The transcript could not be loaded. Until a retry succeeds, the open
  /// conversation is only partly on screen, so it is never written back to
  /// the store and threads can't be switched (see [_saveThread]).
  bool _historyFailed = false;
  bool _waiting = false; // sent, no chunks yet
  bool _streaming = false;

  /// In-flight reply text — a [ValueNotifier] so each SSE chunk repaints only
  /// the streaming bubble instead of rebuilding the whole screen.
  final ValueNotifier<String> _streamingText = ValueNotifier('');

  /// The finished reply, kept in the streaming bubble until [V3Stream] has
  /// revealed all of it ([_streamShown]).
  String? _finalReply;
  String? _streamShown;

  _Failure? _failure;

  /// The last message's content as sent, for "Retry reply".
  String? _lastSent;

  /// The record win waiting for the mentor's reply as its note.
  String? _pendingWinId;

  /// The open conversation (on this device; see [CmpysChatThread]).
  late CmpysChatThread _thread = _newThread('Conversation');

  /// A conversation started here shows "New conversation"; a restored one
  /// shows "Conversation restored · when" ([_restoredWhen] null: unknown).
  bool _threadFresh = false;
  String? _restoredWhen;

  /// The server transcript's last message, the boundary for a new thread.
  String? _serverTailId;
  String? _serverTailText;

  /// Counts sends, so a boundary lookup that raced a send is discarded.
  int _sendSeq = 0;

  bool get _busy => _loadingHistory || _waiting || _streaming;
  bool get _replying => _waiting || _streaming;

  /// Threads may be switched (History, New chat) only on a fully loaded,
  /// idle conversation.
  bool get _canSwitch => !_busy && !_historyFailed;

  @override
  void initState() {
    super.initState();
    _composerFocus.addListener(_handleComposerFocusChanged);
    Future.microtask(_restoreHistory);
  }

  CmpysChatThread _newThread(
    String title, {
    String? afterId,
    String? afterText,
    String? sessionId,
  }) {
    final now = DateTime.now();
    return CmpysChatThread(
      id: 'th${now.microsecondsSinceEpoch}',
      title: title,
      startedAt: now,
      updatedAt: now,
      afterId: afterId,
      afterText: afterText,
      sessionId: sessionId,
    );
  }

  Future<void> _restoreHistory() async {
    if (!mounted) return;
    setState(() {
      _loadingHistory = true;
      _historyFailed = false;
    });
    try {
      final store = ref.read(cmpysStoreProvider.notifier);
      await store.ready;
      if (!mounted) return;
      // Bind to the stored conversation before any network call: if the
      // restore fails, this is what stays open (and it is never replaced).
      final stored = ref.read(cmpysStoreProvider).chatThread;
      if (stored != null) _thread = stored;

      final id = await _resolveSessionId();
      if (!mounted) return;
      // A thread from another (earlier) session isn't this transcript's.
      final mine = stored != null && stored.inSession(id) ? stored : null;
      final thread = mine ?? _newThread('Conversation', sessionId: id);
      final restored = [for (final m in thread.msgs) _Msg.local(m)];
      _Failure? failure;
      String? lastSent;
      String? tailId;
      String? tailText;
      if (id != null) {
        final messages = await ref
            .read(sessionRepositoryProvider)
            .learningMessages(id);
        if (!mounted) return;
        _cachedSessionId = id;
        final start = chatThreadStart(messages, thread);
        for (final m in messages.skip(start)) {
          restored.add(_Msg.server(m));
        }
        if (messages.isNotEmpty) {
          tailId = messages.last['id']?.toString();
          tailText = messages.last['content']?.toString();
        }
        if (start < messages.length && messages.last['role'] == 'user') {
          lastSent = messages.last['content']?.toString();
          failure = const _Failure.reply('Your message was saved. Try again.');
        }
      }
      _msgs
        ..clear()
        ..addAll(restored);
      _thread =
          mine ??
          (restored.isEmpty
              ? _newThread('New conversation', sessionId: id)
              : thread);
      _threadFresh = restored.isEmpty;
      _restoredWhen = mine == null ? null : chatThreadWhen(mine.updatedAt);
      _serverTailId = tailId;
      _serverTailText = tailText;
      _lastSent = lastSent;
      _failure = failure;
      _historyFailed = false;
    } catch (_) {
      if (!mounted) return;
      _historyFailed = true;
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
        if (_msgs.isNotEmpty) _scrollToBottom(streaming: true);
      }
    }
  }

  void _handleComposerFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_composerFocus.hasFocus) _scrollToBottom();
  }

  void _dismissKeyboard() {
    _composerFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _composerFocus.removeListener(_handleComposerFocusChanged);
    _composerFocus.dispose();
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

  /// This learner's session for scoping threads: the resolved one, else the
  /// store's (the cache is cleared after a failed reply).
  String? get _sessionId =>
      _cachedSessionId ?? ref.read(cmpysStoreProvider).sessionId;

  /// Resolves a chat-capable session from the backend (source of truth) and
  /// keeps the local store in sync — this is also what corrects the mentor
  /// header if local state drifted. Guided-learning requires the session to
  /// be at blueprint or later; an unfinished onboarding sets
  /// [_needsOnboarding] so the failure offers the right action.
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

  /// Updates the open conversation's title and last activity, and stores it
  /// unless the transcript failed to load (a partial view must never replace
  /// the stored conversation, its boundary or carried messages).
  void _saveThread({String? title}) {
    _thread = _thread.copyWith(
      title: title,
      updatedAt: DateTime.now(),
      sessionId: _thread.sessionId ?? _sessionId,
    );
    if (_historyFailed) return;
    ref.read(cmpysStoreProvider.notifier).setChat(current: _thread);
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    String? title;
    if (_thread.title == 'New conversation' || _msgs.isEmpty && _threadFresh) {
      title = text.length > 42 ? '${text.substring(0, 40)}…' : text;
    }
    // A reported win whose reply failed gets no note from a later answer.
    _pendingWinId = null;
    await _ask(_Msg(me: true, text: text), title: title);
  }

  Future<void> _ask(_Msg msg, {String? title}) async {
    setState(() {
      _msgs.add(msg);
      _input.clear();
      _failure = null;
      _waiting = true;
      _finalReply = null;
      _streamShown = null;
      _streamingText.value = '';
    });
    _saveThread(title: title);
    _scrollToBottom();
    await _streamReply(msg.wire, added: msg);
  }

  /// "Retry reply": the same content again, once, with no new bubble (the
  /// server reuses its stored pending turn).
  Future<void> _retryReply() async {
    final last = _lastSent;
    if (last == null || _busy) return;
    setState(() {
      _failure = null;
      _waiting = true;
      _finalReply = null;
      _streamShown = null;
      _streamingText.value = '';
    });
    _scrollToBottom();
    await _streamReply(last);
  }

  Future<void> _streamReply(String content, {_Msg? added}) async {
    _sendSeq++;
    _lastSent = content;
    final prevTailId = _serverTailId;
    final prevTailText = _serverTailText;
    // The server stores the user turn as it receives it.
    _serverTailId = null;
    _serverTailText = content;
    final idol = ref.read(cmpysStoreProvider).idol;

    final sessionId = _cachedSessionId ?? await _resolveSessionId();
    if (sessionId == null) {
      if (!mounted) return;
      _serverTailId = prevTailId;
      _serverTailText = prevTailText;
      final mentor = ref.read(cmpysStoreProvider).idol.short;
      setState(() {
        _waiting = false;
        _failure = _needsOnboarding
            ? _Failure.onboarding(
                'Your onboarding with $mentor isn’t finished — complete it to unlock the conversation.',
              )
            : const _Failure.reply(
                'Couldn’t reach your mentor session. Check your connection.',
              );
      });
      return;
    }
    _cachedSessionId = sessionId;

    final streamed = CoalescedText(
      onUpdate: (value) {
        if (!mounted) return;
        _streamingText.value = value;
        _scrollToBottom(streaming: true);
      },
    );
    // Any event means the server accepted (and stored) the message.
    var received = false;
    try {
      final repo = ref.read(sessionRepositoryProvider);
      await for (final ev in repo.sendGuidedLearningMessage(
        sessionId,
        content,
      )) {
        if (!mounted) return;
        received = true;
        final type = ev['type'] as String? ?? '';
        if (type == 'chunk') {
          if (_waiting || !_streaming) {
            setState(() {
              _waiting = false;
              _streaming = true;
            });
          }
          streamed.add(ev['content'] as String? ?? '');
        } else if (type == 'error') {
          throw StateError(ev['message']?.toString() ?? 'chat error');
        } else if (type == 'done') {
          break;
        }
      }
      if (!mounted) return;
      final reply = streamed.close().trim();
      if (reply.isEmpty) throw StateError('empty reply');
      setState(() {
        _waiting = false;
        _streaming = true;
        _finalReply = reply;
        _streamingText.value = reply;
      });
      if (_streamShown == reply) _commitReply();
    } catch (e) {
      if (!mounted) return;
      streamed.close(emitPending: false);
      _cachedSessionId = null;
      final status = e is ApiError ? (e.statusCode ?? 0) : 0;
      // Only a new message the server rejected as content (400/413/422) is
      // "not sent"; a retry is of a turn the server may already hold.
      final refused =
          added != null &&
          !received &&
          (status == 400 || status == 413 || status == 422);
      setState(() {
        _waiting = false;
        _streaming = false;
        _finalReply = null;
        _streamingText.value = '';
        if (!received) {
          // Nothing came back, so nothing new is known to be stored: the
          // transcript's tail stays what it was (a New chat taken now must
          // not use this text as its boundary).
          _serverTailId = prevTailId;
          _serverTailText = prevTailText;
        }
        if (refused) {
          // The typed text goes back into the composer to edit.
          _lastSent = null;
          if (!added.win) {
            _msgs.remove(added);
            if (_input.text.trim().isEmpty) {
              _input.value = TextEditingValue(
                text: added.text,
                selection: TextSelection.collapsed(offset: added.text.length),
              );
            }
          }
          _failure = _Failure.notSent(
            added.win
                ? 'Your win is saved on your record.'
                : status == 413 || status == 422
                ? 'It may be too long. Shorten it and send it again.'
                : 'Edit it and send it again.',
          );
        } else {
          _failure = _Failure.reply(
            _mentorErrorMessage(e, idol.short, saved: received),
          );
        }
      });
    } finally {
      streamed.dispose();
    }
  }

  /// [V3Stream] revealed [text]; a finished reply moves into the transcript.
  void _streamCaughtUp(String text) {
    _streamShown = text;
    if (_finalReply != null && _finalReply == text) _commitReply();
  }

  void _commitReply() {
    final reply = _finalReply;
    if (reply == null || !mounted) return;
    setState(() {
      _msgs.add(_Msg(me: false, text: reply));
      _streaming = false;
      _finalReply = null;
      _streamShown = null;
      _streamingText.value = '';
      _lastSent = null;
    });
    _serverTailId = null;
    _serverTailText = reply;
    _saveThread();
    final winId = _pendingWinId;
    if (winId != null) {
      _pendingWinId = null;
      ref.read(cmpysStoreProvider.notifier).setWinIdolNote(winId, reply);
    }
    _scrollToBottom();
  }

  /// The failed reply's line. "Your message was saved." only when the server
  /// answered at all (it stores the turn before streaming).
  String _mentorErrorMessage(
    Object error,
    String mentor, {
    required bool saved,
  }) {
    if (error is SseIncompleteException) {
      return '$mentor got cut off before finishing. Tap retry.';
    }
    if (error is TimeoutError) {
      return '$mentor is taking longer than expected. Tap retry.';
    }
    if (error is NetworkError) {
      return 'Couldn’t reach $mentor. Check your connection and tap retry.';
    }
    if (error is ApiError && error.statusCode == 429) {
      return '$mentor is handling many requests. Wait a moment and retry.';
    }
    if (error is ApiError &&
        (error.statusCode ?? 0) >= 400 &&
        (error.statusCode ?? 0) < 500) {
      return 'Couldn’t reach your conversation. Try again.';
    }
    if (error is ApiError && (error.statusCode ?? 0) >= 500) {
      return '$mentor is temporarily unavailable. Tap retry.';
    }
    return saved
        ? 'Your message was saved. Try again.'
        : '$mentor couldn’t finish that reply. Tap retry.';
  }

  // ── conversations (on this device) ──

  /// The open conversation with the messages on screen.
  CmpysChatThread get _currentSnapshot =>
      _thread.copyWith(msgs: [for (final m in _msgs) m.toLocal()]);

  /// The archived list with the open conversation (if it has messages) on top.
  List<CmpysChatThread> _archiveCurrent() {
    final archived = ref
        .read(cmpysStoreProvider)
        .chatThreads
        .where((t) => t.id != _thread.id)
        .toList();
    if (_msgs.isNotEmpty) {
      archived.insert(
        0,
        CmpysChatThread(
          id: _thread.id,
          title: _thread.title,
          startedAt: _thread.startedAt,
          updatedAt: _thread.updatedAt,
          msgs: [for (final m in _msgs) m.toLocal()],
          sessionId: _thread.sessionId ?? _sessionId,
        ),
      );
    }
    return archived;
  }

  void _newChat() {
    if (!_canSwitch) return;
    final archived = _archiveCurrent();
    final fresh = _newThread(
      'New conversation',
      afterId: _serverTailId,
      afterText: _serverTailText,
      sessionId: _sessionId,
    );
    ref
        .read(cmpysStoreProvider.notifier)
        .setChat(current: fresh, archived: archived);
    setState(() {
      _thread = fresh;
      _msgs.clear();
      _failure = null;
      _lastSent = null;
      _threadFresh = true;
      _restoredWhen = null;
      _input.clear();
    });
    unawaited(_resolveBoundary(fresh.id));
  }

  /// A boundary set from text (the tail was sent or answered here) is
  /// replaced by the server's tail id, so a repeated message can't be
  /// mistaken for it on the next restore. The lookup is dropped if anything
  /// was sent or the thread changed meanwhile.
  Future<void> _resolveBoundary(String threadId) async {
    if (_thread.afterId != null) return;
    final seq = _sendSeq;
    try {
      final sessionId = _cachedSessionId ?? await _resolveSessionId();
      if (sessionId == null || !mounted) return;
      final messages = await ref
          .read(sessionRepositoryProvider)
          .learningMessages(sessionId);
      if (!mounted ||
          _thread.id != threadId ||
          _sendSeq != seq ||
          _thread.afterId != null ||
          messages.isEmpty) {
        return;
      }
      final id = messages.last['id']?.toString();
      if (id == null) return;
      _serverTailId = id;
      _serverTailText = messages.last['content']?.toString();
      _thread = _thread.copyWith(afterId: id, afterText: _serverTailText);
      if (!_historyFailed) {
        ref.read(cmpysStoreProvider.notifier).setChat(current: _thread);
      }
    } catch (_) {
      // The text boundary still works.
    }
  }

  void _openThread(String id) {
    if (!_canSwitch) return;
    final store = ref.read(cmpysStoreProvider);
    final match = store.chatThreads.where((t) => t.id == id);
    if (match.isEmpty) return;
    final picked = match.first;
    final archived = _archiveCurrent().where((t) => t.id != id).toList();
    final current = CmpysChatThread(
      id: picked.id,
      title: picked.title,
      startedAt: picked.startedAt,
      updatedAt: picked.updatedAt,
      msgs: picked.msgs,
      afterId: _serverTailId,
      afterText: _serverTailText,
      sessionId: picked.sessionId ?? _sessionId,
    );
    ref
        .read(cmpysStoreProvider.notifier)
        .setChat(current: current, archived: archived);
    setState(() {
      _thread = current;
      _msgs
        ..clear()
        ..addAll(picked.msgs.map(_Msg.local));
      _failure = null;
      _lastSent = null;
      _threadFresh = false;
      _restoredWhen = chatThreadWhen(picked.updatedAt);
    });
    unawaited(_resolveBoundary(current.id));
    _scrollToBottom(streaming: true);
  }

  void _deleteThread(BuildContext toastContext, String id) {
    ref.read(cmpysStoreProvider.notifier).deleteChatThread(id);
    showV3Toast(toastContext, 'Conversation deleted', icon: V3Icons.trash);
  }

  Future<void> _openHistory() async {
    if (!_canSwitch) return;
    _dismissKeyboard();
    await showV3Sheet<void>(
      context,
      title: 'Conversations',
      max: 0.88,
      builder: (sheetContext) => _HistorySheet(
        current: _currentSnapshot,
        sessionId: _sessionId,
        onOpen: (id) {
          Navigator.of(sheetContext).pop();
          _openThread(id);
        },
        onNew: () {
          Navigator.of(sheetContext).pop();
          _newChat();
        },
        onDelete: (id) => _deleteThread(sheetContext, id),
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  // ── notes ──

  Future<void> _openNoteSheet(CmpysIdol idol, String text) async {
    _dismissKeyboard();
    await showV3Sheet<void>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.iris, width: 3)),
            ),
            child: Text(
              text.length > 160 ? '${text.substring(0, 160)}…' : text,
              style: AppTypography.read(
                15,
              ).copyWith(height: 1.55, color: AppColors.ink2),
            ),
          ),
          const SizedBox(height: 18),
          V3Button(
            full: true,
            kind: V3ButtonKind.dark,
            icon: V3Icons.note,
            onPressed: () {
              ref
                  .read(cmpysStoreProvider.notifier)
                  .saveNote(
                    kind: 'chat',
                    title: '${idol.short} · Chat',
                    body: text,
                    from: idol.short,
                  );
              Navigator.of(sheetContext).pop();
              if (mounted) {
                showV3Toast(context, 'Saved to notes', icon: V3Icons.note);
              }
            },
            child: const Text('Save to notes'),
          ),
          const SizedBox(height: 8),
          V3Button(
            full: true,
            kind: V3ButtonKind.ghost,
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 10),
          Text(
            'Notes are saved on this device.',
            textAlign: TextAlign.center,
            style: AppTypography.sans(12).copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  // ── wins ──

  Future<void> _reportWin(CmpysIdol idol) async {
    if (_busy) return;
    _dismissKeyboard();
    String? winId;
    final win = await showWinSheet(
      context,
      mode: WinSheetMode.chat,
      mentorShort: idol.short,
      mentorImage: cmpysIdolImage(idol),
      mentorInitials: idol.initials,
      mentorTint: idol.tint,
      age: ref.read(cmpysStoreProvider).user.age,
      onSave: (w) async {
        winId = await saveReportedWin(ref, w, source: 'chat');
      },
    );
    if (win == null || !mounted || _busy) return;
    _pendingWinId = winId;
    await _ask(_Msg(me: true, text: win.text, win: true, wire: winPrompt(win)));
  }

  void _scrollToBottom({bool streaming = false}) {
    _scrollShouldAnimate = _scrollShouldAnimate || !streaming;
    if (_scrollFrameScheduled) return;
    _scrollFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollFrameScheduled = false;
      final animate = _scrollShouldAnimate;
      _scrollShouldAnimate = false;
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (!animate || !MotionConfig.enabled(context)) {
        // Per-chunk: don't stack 280ms animations — snap if not at bottom.
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

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final idol = ref.watch(cmpysStoreProvider.select((s) => s.idol));
    // The plan's week for the empty state, once the plan has been loaded
    // elsewhere (the chat never starts a plan fetch of its own).
    final week = ref.exists(currentPlanProvider)
        ? ref.watch(currentPlanProvider.select((s) => s.plan?.currentWeek()))
        : null;
    return Scaffold(
      // The shell does not consume keyboard insets; the active branch owns
      // the single resize so the composer never gets inset twice.
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(idol),
            Expanded(child: _messages(idol, week)),
            _composer(idol),
          ],
        ),
      ),
    );
  }

  Widget _avatar(CmpysIdol idol, double size) => V3Avatar(
    image: cmpysIdolImage(idol),
    initials: idol.initials,
    tint: idol.tint,
    size: size,
    gray: true,
  );

  Widget _header(CmpysIdol idol) {
    final motion = MotionConfig.enabled(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: V3Pressable(
              semanticLabel: 'Open ${idol.name} profile',
              focusRadius: BorderRadius.circular(16),
              onTap: () => openIdolDetail(context, idol),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 44,
                    child: Stack(
                      children: [
                        _avatar(idol, 44),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.sage,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.paper,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          idol.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            16,
                            FontWeight.w600,
                          ).copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 1),
                        AnimatedSwitcher(
                          duration: motion
                              ? const Duration(milliseconds: 400)
                              : Duration.zero,
                          child: Text(
                            _thread.title,
                            key: ValueKey(_thread.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.sans(
                              12,
                            ).copyWith(color: AppColors.ink3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          V3IconButton(
            icon: V3Icons.history,
            label: 'Chat history',
            size: 38,
            onPressed: _canSwitch ? _openHistory : null,
          ),
          V3IconButton(
            icon: V3Icons.edit,
            label: 'New chat',
            size: 38,
            onPressed: _canSwitch ? _newChat : null,
          ),
          V3IconButton(
            icon: V3Icons.trophy,
            label: 'Report a win',
            size: 38,
            color: AppColors.gold2,
            onPressed: _busy ? null : () => _reportWin(idol),
          ),
        ],
      ),
    );
  }

  Widget _messages(CmpysIdol idol, int? week) {
    final showEmpty =
        _msgs.isEmpty && !_busy && _failure == null && !_historyFailed;
    final lastIsReply = _msgs.isNotEmpty && !_msgs.last.me;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleMax = (constraints.maxWidth - 32) * 0.78;
        return ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          children: [
            if (_historyFailed)
              Padding(
                key: const ValueKey('history-failed'),
                padding: const EdgeInsets.only(bottom: 10),
                child: _failureBubble(
                  idol,
                  maxWidth: bubbleMax,
                  title:
                      'Couldn’t restore your conversation. Retry to load it.',
                  action: V3Button(
                    size: V3Size.sm,
                    kind: V3ButtonKind.dark,
                    icon: V3Icons.refresh,
                    onPressed: _replying ? null : _restoreHistory,
                    child: const Text('Retry'),
                  ),
                ),
              )
            else if (showEmpty)
              KeyedSubtree(
                key: ValueKey('empty-${_thread.id}'),
                child: _emptyState(idol, week),
              )
            else if (!_loadingHistory || _msgs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _threadFresh
                      ? 'New conversation'
                      : _restoredWhen == null
                      ? 'Conversation restored'
                      : 'Conversation restored · $_restoredWhen',
                  textAlign: TextAlign.center,
                  style: AppTypography.sans(
                    11.5,
                  ).copyWith(color: AppColors.ink3),
                ),
              ),
            for (final m in _msgs)
              Padding(
                key: ObjectKey(m),
                padding: const EdgeInsets.only(bottom: 10),
                child: m.me
                    ? _Bubble(
                        me: true,
                        maxWidth: bubbleMax,
                        tag: m.win
                            ? const V3Tag(
                                background: AppColors.goldSoft,
                                color: AppColors.gold2,
                                icon: V3Icons.trophy,
                                child: Text('Win reported'),
                              )
                            : null,
                        child: Text(m.text),
                      )
                    // Keyboard- and switch-reachable; no press scale.
                    : V3Pressable(
                        pressedScale: 1,
                        focusRadius: BorderRadius.circular(20),
                        onTap: () => _openNoteSheet(idol, m.text),
                        child: Semantics(
                          onTapHint: 'Save to notes',
                          child: _Bubble(
                            me: false,
                            maxWidth: bubbleMax,
                            avatar: _avatar(idol, 28),
                            child: Text(m.text),
                          ),
                        ),
                      ),
              ),
            if (_loadingHistory || _waiting)
              Padding(
                key: const ValueKey('typing'),
                padding: const EdgeInsets.only(bottom: 10),
                child: _Bubble(
                  me: false,
                  maxWidth: bubbleMax,
                  avatar: _avatar(idol, 28),
                  child: const V3Typing(semanticLabel: 'Writing a reply'),
                ),
              ),
            if (_streaming)
              Padding(
                key: const ValueKey('streaming-reply'),
                padding: const EdgeInsets.only(bottom: 10),
                // Follows the bubble as V3Stream reveals it, so the reply
                // stays in view.
                child: _OnResize(
                  onResize: () => _scrollToBottom(streaming: true),
                  child: _Bubble(
                    me: false,
                    maxWidth: bubbleMax,
                    avatar: _avatar(idol, 28),
                    child: ValueListenableBuilder<String>(
                      valueListenable: _streamingText,
                      builder: (_, text, _) => V3Stream(
                        text: text,
                        speed: const Duration(milliseconds: 26),
                        onDone: () => _streamCaughtUp(text),
                      ),
                    ),
                  ),
                ),
              ),
            if (_failure != null)
              Padding(
                key: ValueKey(_failure),
                padding: const EdgeInsets.only(bottom: 10),
                child: _replyFailure(idol, _failure!, bubbleMax),
              ),
            if (!_busy && _failure == null && lastIsReply)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 6),
                child: Text(
                  'Tap a reply to save it as a note',
                  style: AppTypography.sans(
                    11.5,
                  ).copyWith(color: AppColors.ink3),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyState(CmpysIdol idol, int? week) {
    final about = week == null
        ? '${idol.short} knows your plan and your last practice results. Ask anything.'
        : '${idol.short} knows your plan, week $week and your last practice results. Ask anything.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 28, 10, 0),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 96,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: _Halo()),
                V3Pop(
                  duration: const Duration(milliseconds: 600),
                  child: _avatar(idol, 96),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          V3Rise(
            delay: const Duration(milliseconds: 120),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'New conversation\n'),
                  TextSpan(
                    text: 'with ${idol.short}',
                    style: AppTypography.displayItalic(32),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: AppTypography.display(32).copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 10),
          V3Rise(
            delay: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                about,
                textAlign: TextAlign.center,
                style: AppTypography.sans(
                  14,
                ).copyWith(height: 1.5, color: AppColors.ink2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 8),
                    Expanded(child: _promptCard(row * 2 + col)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _promptCard(int i) {
    final (icon, prompt) = _emptyPrompts[i];
    return V3Rise(
      delay: Duration(milliseconds: 260 + i * 60),
      child: V3Pressable(
        onTap: () => _send(prompt),
        focusRadius: BorderRadius.circular(AppRadii.r),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(14),
          decoration: v3Card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              V3Icon(icon, size: 18, color: AppColors.ember),
              const SizedBox(height: 10),
              Text(
                prompt,
                style: AppTypography.sans(
                  13.5,
                  FontWeight.w500,
                ).copyWith(height: 1.35, color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyFailure(CmpysIdol idol, _Failure failure, double maxWidth) {
    final Widget? action = switch (failure.kind) {
      _FailKind.onboarding => V3Button(
        size: V3Size.sm,
        kind: V3ButtonKind.dark,
        iconRight: V3Icons.arrowR,
        onPressed: () => context.go(AppRoutes.cmpysOnboarding),
        child: const Text('Finish onboarding'),
      ),
      _FailKind.notSent => null,
      _FailKind.reply =>
        _lastSent == null
            ? null
            : V3Button(
                size: V3Size.sm,
                kind: V3ButtonKind.dark,
                icon: V3Icons.refresh,
                onPressed: _retryReply,
                child: const Text('Retry reply'),
              ),
    };
    return _failureBubble(
      idol,
      maxWidth: maxWidth,
      title: failure.title,
      sub: failure.sub,
      action: action,
    );
  }

  /// The design's failed-reply bubble (danger-soft, alert icon).
  Widget _failureBubble(
    CmpysIdol idol, {
    required double maxWidth,
    required String title,
    String sub = '',
    Widget? action,
  }) {
    return V3Rise(
      duration: const Duration(milliseconds: 400),
      offset: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _avatar(idol, 28),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const V3Icon(
                        V3Icons.alert,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.sans(
                            14,
                            FontWeight.w600,
                          ).copyWith(color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: AppTypography.sans(
                        13,
                      ).copyWith(color: AppColors.ink2),
                    ),
                  ],
                  if (action != null) ...[const SizedBox(height: 10), action],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer(CmpysIdol idol) {
    final motion = MotionConfig.enabled(context);
    final quick = motion ? const Duration(milliseconds: 250) : Duration.zero;
    final showChips = !_busy && _failure == null && _msgs.isNotEmpty;
    return Container(
      color: AppColors.paper,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        AppShell.bottomNavClearance(context, extra: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MaybeAnimatedSize(
            motion: motion,
            child: showChips
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SingleChildScrollView(
                      key: const ValueKey('chat-suggestions'),
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        children: [
                          for (var i = 0; i < _chatPrompts.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            V3Rise(
                              delay: Duration(milliseconds: i * 50),
                              child: V3Chip(
                                icon: V3Icons.sparkle,
                                onPressed: () => _send(_chatPrompts[i]),
                                child: Text(_chatPrompts[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          TextFieldTapRegion(
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(27),
                border: Border.all(color: AppColors.hair),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 24,
                    spreadRadius: -16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _composerFocus,
                      minLines: 1,
                      maxLines:
                          MediaQuery.textScalerOf(context).scale(15.5) > 24
                          ? 2
                          : 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textAlignVertical: TextAlignVertical.center,
                      textCapitalization: TextCapitalization.sentences,
                      onTapOutside: (_) => _dismissKeyboard(),
                      style: AppTypography.sans(
                        15.5,
                      ).copyWith(color: AppColors.ink),
                      cursorColor: AppColors.ember,
                      decoration: InputDecoration(
                        hintText: 'Ask ${idol.short}',
                        hintMaxLines: 1,
                        hintStyle: AppTypography.sans(
                          15.5,
                        ).copyWith(color: AppColors.ink3),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, value, _) {
                      final typed = value.text.trim().isNotEmpty;
                      final canSend = typed && !_busy;
                      return V3Pressable(
                        key: CmpysChatScreen.sendKey,
                        semanticLabel: 'Send',
                        focusRadius: BorderRadius.circular(21),
                        onTap: canSend ? () => _send(_input.text) : null,
                        child: AnimatedContainer(
                          duration: quick,
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: canSend ? AppColors.ember : AppColors.paper2,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: AnimatedRotation(
                            duration: motion
                                ? const Duration(milliseconds: 300)
                                : Duration.zero,
                            curve: AppMotion.spring,
                            turns: typed ? -0.25 : 0,
                            child: V3Icon(
                              V3Icons.send,
                              size: 18,
                              strokeWidth: 2.2,
                              color: canSend ? Colors.white : AppColors.ink3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [AnimatedSize] with motion; the bare child without (a zero-duration
/// AnimatedSize re-dirties itself during layout).
class _MaybeAnimatedSize extends StatelessWidget {
  const _MaybeAnimatedSize({required this.motion, required this.child});
  final bool motion;
  final Widget child;

  @override
  Widget build(BuildContext context) => motion
      ? AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: AppMotion.out,
          alignment: Alignment.topCenter,
          child: child,
        )
      : child;
}

/// Calls [onResize] whenever its child's laid-out size changes (the
/// streaming bubble growing as [V3Stream] reveals words).
class _OnResize extends SingleChildRenderObjectWidget {
  const _OnResize({required this.onResize, super.child});
  final VoidCallback onResize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOnResize(onResize);

  @override
  void updateRenderObject(BuildContext context, _RenderOnResize renderObject) {
    renderObject.onResize = onResize;
  }
}

class _RenderOnResize extends RenderProxyBox {
  _RenderOnResize(this.onResize);
  VoidCallback onResize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      // Only schedules a post-frame scroll; nothing changes during layout.
      onResize();
    }
  }
}

/// A chat bubble (`Bubble` in `v3/onboard2.jsx`): ink for the learner, a
/// card with the mentor's avatar for replies, an optional tag under it.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.me,
    required this.child,
    required this.maxWidth,
    this.avatar,
    this.tag,
  });
  final bool me;
  final Widget child;
  final double maxWidth;
  final Widget? avatar;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    return V3Rise(
      duration: const Duration(milliseconds: 450),
      child: Row(
        mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!me && avatar != null) ...[avatar!, const SizedBox(width: 8)],
          ConstrainedBox(
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
                    border: me ? null : Border.all(color: AppColors.hair),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(me ? 20 : 6),
                      bottomRight: Radius.circular(me ? 6 : 20),
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    style: AppTypography.sans(15).copyWith(
                      height: 1.45,
                      color: me ? Colors.white : AppColors.ink,
                    ),
                    child: child,
                  ),
                ),
                if (tag != null) ...[const SizedBox(height: 5), tag!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty state's halo: two ember rings growing from .7 to 2.2× and
/// fading, 2.6 s, the second 1.3 s behind.
class _Halo extends StatefulWidget {
  const _Halo();

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionConfig.enabled(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionConfig.enabled(context)) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 2; i++)
              Positioned.fill(child: _ring((_controller.value + i * 0.5) % 1)),
          ],
        ),
      ),
    );
  }

  Widget _ring(double t) {
    final v = AppMotion.out.transform(t);
    return Opacity(
      opacity: (0.6 * (1 - v)).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.7 + 1.5 * v,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ember, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// "Conversations" (`HistorySheet`): search, the open conversation under
/// "Current", the archived ones grouped This week / Last week / Earlier,
/// delete, and a new chat.
class _HistorySheet extends ConsumerStatefulWidget {
  const _HistorySheet({
    required this.current,
    required this.sessionId,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
    required this.onClose,
  });

  final CmpysChatThread current;

  /// Only this session's conversations are listed.
  final String? sessionId;
  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;
  final VoidCallback onClose;

  @override
  ConsumerState<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<_HistorySheet> {
  String _q = '';

  bool _match(CmpysChatThread t) {
    if (_q.isEmpty) return true;
    final hay = '${t.title} ${t.msgs.map((m) => m.text).join(' ')}';
    return hay.toLowerCase().contains(_q.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.current;
    final threads = ref
        .watch(cmpysStoreProvider.select((s) => s.chatThreads))
        .where((t) => t.id != cur.id && t.inSession(widget.sessionId))
        .toList();
    final now = DateTime.now();
    final groups = [
      for (final g in const ['This week', 'Last week', 'Earlier'])
        (
          g,
          threads
              .where((t) => chatThreadDay(t.updatedAt, now: now) == g)
              .where(_match)
              .toList(),
        ),
    ].where((e) => e.$2.isNotEmpty).toList();
    final showCurrent = _match(cur) && cur.msgs.isNotEmpty;
    var index = 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: V3Field(
                placeholder: 'Search conversations',
                onChanged: (v) => setState(() => _q = v.trim()),
                right: const V3Icon(
                  V3Icons.search,
                  size: 17,
                  color: AppColors.ink3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            V3Pressable(
              semanticLabel: 'New chat',
              focusRadius: BorderRadius.circular(16),
              onTap: widget.onNew,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const V3Icon(
                  V3Icons.plus,
                  size: 22,
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        if (showCurrent) ...[
          const SizedBox(height: 18),
          _kick('Current'),
          _row(cur, current: true, i: index++),
        ],
        for (final (g, list) in groups) ...[
          const SizedBox(height: 14),
          _kick(g),
          for (final t in list) _row(t, i: index++),
        ],
        if (_q.isNotEmpty && groups.isEmpty && !showCurrent)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text(
              'No conversations match “$_q”.',
              textAlign: TextAlign.center,
              style: AppTypography.sans(14).copyWith(color: AppColors.ink2),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'Every conversation uses your current plan and progress as context.',
          textAlign: TextAlign.center,
          style: AppTypography.sans(
            12,
          ).copyWith(height: 1.45, color: AppColors.ink3),
        ),
      ],
    );
  }

  Widget _kick(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: AppTypography.kick),
  );

  Widget _row(CmpysChatThread t, {bool current = false, required int i}) {
    final last = t.msgs.isEmpty ? null : t.msgs.last;
    final preview = last == null
        ? 'No messages yet'
        : '${last.me ? 'You: ' : ''}${last.text}';
    return V3Rise(
      key: ValueKey('thread-${t.id}'),
      delay: Duration(milliseconds: i * 45),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: current ? AppColors.emberSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: current ? null : Border.all(color: AppColors.hair),
        ),
        child: Row(
          children: [
            Expanded(
              child: V3Pressable(
                focusRadius: BorderRadius.circular(14),
                onTap: current ? widget.onClose : () => widget.onOpen(t.id),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: current ? AppColors.ember : AppColors.paper2,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: V3Icon(
                        V3Icons.chat,
                        size: 18,
                        color: current ? Colors.white : AppColors.ink2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.sans(
                                    15,
                                    FontWeight.w600,
                                  ).copyWith(color: AppColors.ink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                current ? 'Open' : chatThreadWhen(t.updatedAt),
                                style: AppTypography.sans(
                                  11.5,
                                ).copyWith(color: AppColors.ink3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.sans(
                              13,
                            ).copyWith(color: AppColors.ink2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!current)
              V3Pressable(
                semanticLabel: 'Delete conversation',
                focusRadius: BorderRadius.circular(12),
                onTap: () => widget.onDelete(t.id),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: V3Icon(V3Icons.trash, size: 16, color: AppColors.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
