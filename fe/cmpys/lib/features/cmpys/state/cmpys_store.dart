// CMPYS shared app store.
//
// One Riverpod StateNotifier holding every piece of mutable app state the
// design's screens read and write — tasks, milestones, achievements, dimension
// shifts, notes, saved items, idea interactions, settings, custom plan items,
// the user profile, and the active idol. Mirrors the prototype's single store
// (main.jsx) so toggles, counts, and saves stay consistent across all tabs and
// detail screens. Persisted to shared_preferences, one store per signed-in
// account (owner decision 2).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../session/models/session_models.dart';
import '../data/cmpys_record_data.dart';
import '../data/cmpys_seed.dart';
import 'week_unlock_ledger.dart';

export 'week_unlock_ledger.dart';

/// The unkeyed store an older build wrote: migrated once, to its owner
/// ([CmpysStore.openAccount]).
const _storeKey = 'cmpys_store_v1';

/// The unkeyed store's backup (older builds), migrated with it.
const _backupKey = 'cmpys_store_v1.bak';

/// Where [accountId]'s store is kept on this device.
String cmpysStoreKeyFor(String accountId) => '$_storeKey:$accountId';

/// Where [accountId]'s stored value that couldn't be read in full is copied
/// on load.
String cmpysStoreBackupKeyFor(String accountId) =>
    '${cmpysStoreKeyFor(accountId)}.bak';

// ─────────────────────────────────────────────────────────────────────────────
// Conversion helpers — raw comparisonScores map → seed-shaped objects
// ─────────────────────────────────────────────────────────────────────────────

/// Evidence-grounded comparison score versions this build can read: v2
/// (legacy ids such as `habits` and `clarity`) and v3 (`knowledge`,
/// `practice`, `capital`, `network`, `judgment`).
const _comparisonScoreReadableVersions = {2, 3};

bool _readableComparisonScores(Map<String, dynamic>? scores) =>
    _comparisonScoreReadableVersions.contains(scores?['version']) &&
    scores?['methodology'] == 'like_for_like_evidence';

/// Convert an evidence-grounded v2 or v3 `comparisonScores` map into
/// dimensions, in payload order. Labels come from the server (the id only
/// stands in for a blank label); ids are never mapped to display names here.
/// Older percentage scores are hidden while the backend regenerates them.
List<CmpysDimension>? dimsFromScores(Map<String, dynamic>? scores) {
  if (!_readableComparisonScores(scores)) return null;
  final raw = scores?['dimensions'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <CmpysDimension>[];
  for (final d in raw) {
    if (d is! Map) continue;
    final id = (d['id'] ?? '').toString();
    final label = (d['label'] ?? '').toString().trim();
    out.add(CmpysDimension(
      id: id,
      label: label.isEmpty ? id : label,
      // A wrong-typed score (e.g. "40") reads as no score, never a crash.
      you: d['you'] is num ? (d['you'] as num).toInt() : null,
      idol: d['idol'] is num ? (d['idol'] as num).toInt() : null,
      youNote: (d['you_note'] ?? '').toString(),
      idolNote: (d['idol_note'] ?? '').toString(),
      status: (d['status'] ?? 'insufficient_user_evidence').toString(),
      comparisonBasis: (d['comparison_basis'] ?? '').toString(),
      youEvidence: (d['you_evidence'] ?? 'none').toString(),
      idolEvidence: (d['idol_evidence'] ?? 'none').toString(),
    ));
  }
  return out.isEmpty ? null : out;
}

/// Convert raw milestones into seed-shaped CmpysMilestone with stable ids
/// (`m1`..). Returns null when absent so callers fall back to seed.
List<CmpysMilestone>? milestonesFromScores(Map<String, dynamic>? scores) {
  if (!_readableComparisonScores(scores)) return null;
  final raw = scores?['milestones'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <CmpysMilestone>[];
  for (var i = 0; i < raw.length; i++) {
    final m = raw[i];
    if (m is! Map) continue;
    final label = (m['label'] ?? m['text'] ?? '').toString();
    if (label.isEmpty) continue;
    // `hit_by_age` 0 (the backend's clamp of a missing age) means unknown.
    final age = m['hit_by_age'] is num ? (m['hit_by_age'] as num).toInt() : 0;
    out.add(CmpysMilestone(
      (m['id'] ?? 'm${i + 1}').toString(),
      label,
      age: age > 0 ? age : null,
    ));
  }
  return out.isEmpty ? null : out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-models
// ─────────────────────────────────────────────────────────────────────────────

class CmpysNote {
  CmpysNote({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.from,
    this.when = 'Just now',
    this.at,
  });
  final String id;
  final String kind; // chat | read | book | …
  final String title;
  final String body;
  final String? from;

  /// The label older builds stored ("Just now"); shown only for a note
  /// without [at].
  final String when;

  /// When the note was saved (milliseconds since the epoch). Null for notes
  /// stored before it was kept: Notes shows their [when] instead.
  final int? at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'from': from,
        'when': when,
        'at': at,
      };

  /// Parses a stored note tolerantly (a wrong-typed field reads as its
  /// default); a note without a string id throws ([tryParse] skips it).
  factory CmpysNote.fromJson(Map<String, dynamic> j) {
    String? text(Object? v) => v is String ? v : null;
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('A stored note has no id.');
    }
    return CmpysNote(
      id: id,
      kind: text(j['kind']) ?? 'chat',
      title: text(j['title']) ?? '',
      body: text(j['body']) ?? '',
      from: text(j['from']),
      when: text(j['when']) ?? 'Saved',
      at: j['at'] is num && (j['at'] as num) > 0
          ? (j['at'] as num).toInt()
          : null,
    );
  }

  /// A stored note, or null when it can't be read (not a map, or no id).
  static CmpysNote? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      return CmpysNote.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}

/// One message of a Mentor conversation kept on this device.
class CmpysChatMsg {
  const CmpysChatMsg({required this.me, required this.text, this.win = false});
  final bool me;
  final String text;

  /// A win reported from the Mentor tab ("Win reported" tag).
  final bool win;

  Map<String, dynamic> toJson() => {'me': me, 't': text, 'win': win};
  factory CmpysChatMsg.fromJson(Map<String, dynamic> j) => CmpysChatMsg(
        me: j['me'] == true,
        text: j['t']?.toString() ?? '',
        win: j['win'] == true,
      );
}

/// At most this many archived Mentor conversations are kept on the device.
const cmpysMaxChatThreads = 30;

/// At most this many messages are kept per conversation (the latest).
const cmpysMaxChatMsgs = 100;

/// A Mentor conversation kept on this device (`v3/chat.jsx` threads). The
/// server keeps one guided-learning transcript per session and has no thread
/// list, so threads are a device-side view of that transcript:
/// - an archived thread keeps its own copy of [msgs];
/// - the current thread shows [msgs] (carried over when an archived thread
///   is reopened) followed by the server messages after the boundary
///   ([afterId]; only when no id is known, the last message whose trimmed
///   content is [afterText]). With no boundary every server message belongs
///   to it.
///
/// [sessionId] scopes a thread to the onboarding session whose transcript it
/// views, so a new session never shows an earlier mentor's conversations.
class CmpysChatThread {
  const CmpysChatThread({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.updatedAt,
    this.msgs = const [],
    this.afterId,
    this.afterText,
    this.sessionId,
  });
  final String id;
  final String title;
  final DateTime startedAt;
  final DateTime updatedAt;
  final List<CmpysChatMsg> msgs;
  final String? afterId;
  final String? afterText;
  final String? sessionId;

  /// Whether this thread belongs to [session] (threads from before scoping,
  /// or an unknown session, match).
  bool inSession(String? session) =>
      sessionId == null || session == null || sessionId == session;

  CmpysChatThread copyWith({
    String? title,
    DateTime? updatedAt,
    List<CmpysChatMsg>? msgs,
    String? afterId,
    String? afterText,
    String? sessionId,
  }) =>
      CmpysChatThread(
        id: id,
        title: title ?? this.title,
        startedAt: startedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        msgs: msgs ?? this.msgs,
        afterId: afterId ?? this.afterId,
        afterText: afterText ?? this.afterText,
        sessionId: sessionId ?? this.sessionId,
      );

  /// This thread with only its latest [cmpysMaxChatMsgs] messages.
  CmpysChatThread capped() => msgs.length <= cmpysMaxChatMsgs
      ? this
      : copyWith(msgs: msgs.sublist(msgs.length - cmpysMaxChatMsgs));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'msgs': msgs.map((m) => m.toJson()).toList(),
        'afterId': afterId,
        'afterText': afterText,
        'sessionId': sessionId,
      };

  /// Parses a stored thread; null when it is malformed (no id). Malformed
  /// messages are skipped, and the message cap is applied.
  static CmpysChatThread? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      final j = raw.cast<String, dynamic>();
      final id = j['id'];
      if (id is! String || id.isEmpty) return null;
      DateTime at(Object? v) => DateTime.fromMillisecondsSinceEpoch(
            v is num ? v.toInt() : 0,
          );
      String? text(Object? v) => v is String ? v : null;
      final msgs = <CmpysChatMsg>[
        for (final m in (j['msgs'] is List ? j['msgs'] as List : const []))
          if (m is Map) CmpysChatMsg.fromJson(m.cast<String, dynamic>()),
      ];
      return CmpysChatThread(
        id: id,
        title: text(j['title']) ?? 'Conversation',
        startedAt: at(j['startedAt']),
        updatedAt: at(j['updatedAt']),
        msgs: msgs,
        afterId: text(j['afterId']),
        afterText: text(j['afterText']),
        sessionId: text(j['sessionId']),
      ).capped();
    } catch (_) {
      return null;
    }
  }
}

class CmpysSavedItem {
  CmpysSavedItem({
    required this.id,
    required this.kind,
    required this.title,
    this.sub,
  });
  final String id;
  final String kind; // task | read | video | book | idea
  final String title;
  final String? sub;

  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind, 'title': title, 'sub': sub};

  /// A stored saved item, or null when it can't be read (no string id).
  static CmpysSavedItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    String? text(Object? v) => v is String ? v : null;
    return CmpysSavedItem(
      id: id,
      kind: text(raw['kind']) ?? 'idea',
      title: text(raw['title']) ?? '',
      sub: text(raw['sub']),
    );
  }
}

class CmpysIdeaState {
  CmpysIdeaState({this.liked = false, this.saved = false, List<({String who, String text})>? comments})
      : comments = comments ?? [];
  bool liked;
  bool saved;
  List<({String who, String text})> comments;

  Map<String, dynamic> toJson() => {
        'liked': liked,
        'saved': saved,
        'comments': comments.map((c) => {'who': c.who, 'text': c.text}).toList(),
      };

  /// A stored idea state, or null when it isn't a map. Wrong-typed fields
  /// read as their defaults, and malformed comments are skipped.
  static CmpysIdeaState? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final comments = raw['comments'];
    return CmpysIdeaState(
      liked: raw['liked'] == true,
      saved: raw['saved'] == true,
      comments: [
        if (comments is List)
          for (final c in comments)
            if (c is Map)
              (
                who: c['who']?.toString() ?? 'You',
                text: c['text']?.toString() ?? '',
              ),
      ],
    );
  }
}

class CmpysCustomTask {
  CmpysCustomTask({required this.id, required this.title});
  final String id;
  final String title;
  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  /// A stored custom task, or null when it can't be read (no string id).
  static CmpysCustomTask? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final title = raw['title'];
    return CmpysCustomTask(id: id, title: title is String ? title : '');
  }
}

class CmpysSettings {
  CmpysSettings({
    this.reminder = true,
    this.mentorPing = true,
    this.digest = true,
    this.haptics = true,
    this.readSize = 1,
    this.readTheme = 'light',
  });
  bool reminder;
  bool mentorPing;
  bool digest;
  bool haptics;

  /// Reader text size step: 0 "A", 1 "A+" (default), 2 "A++".
  int readSize;

  /// Reader theme name (`ReaderTheme.name`): light, sepia or dark.
  String readTheme;

  CmpysSettings copy() => CmpysSettings(
      reminder: reminder,
      mentorPing: mentorPing,
      digest: digest,
      haptics: haptics,
      readSize: readSize,
      readTheme: readTheme);

  Map<String, dynamic> toJson() => {
        'reminder': reminder,
        'mentorPing': mentorPing,
        'digest': digest,
        'haptics': haptics,
        'readSize': readSize,
        'readTheme': readTheme,
      };
  factory CmpysSettings.fromJson(Map<String, dynamic> j) => CmpysSettings(
        reminder: j['reminder'] as bool? ?? true,
        mentorPing: j['mentorPing'] as bool? ?? true,
        digest: j['digest'] as bool? ?? true,
        haptics: j['haptics'] as bool? ?? true,
        // Older stores have neither field; anything unreadable falls back.
        readSize: switch (j['readSize']) {
          final int size when size >= 0 && size <= 2 => size,
          _ => 1,
        },
        readTheme: switch (j['readTheme']) {
          final String name when const {'light', 'sepia', 'dark'}
                  .contains(name) =>
            name,
          _ => 'light',
        },
      );
}

class CmpysUser {
  CmpysUser({
    this.name = '',
    this.age = 24,
    List<String>? interests,
    this.goalId,
  }) : interests = interests ?? [];
  String name;
  int age;
  List<String> interests;
  String? goalId;

  Map<String, dynamic> toJson() =>
      {'name': name, 'age': age, 'interests': interests, 'goalId': goalId};
  factory CmpysUser.fromJson(Map<String, dynamic> j) => CmpysUser(
        name: j['name'] as String? ?? '',
        age: (j['age'] as num?)?.toInt() ?? 24,
        interests:
            (j['interests'] as List?)?.map((e) => e.toString()).toList() ?? [],
        goalId: j['goalId'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Aggregate state
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class CmpysState {
  const CmpysState({
    required this.user,
    required this.idol,
    required this.tasks,
    required this.milestones,
    required this.achievements,
    required this.streak,
    required this.dayNum,
    required this.notes,
    required this.saved,
    required this.custom,
    required this.ideaState,
    required this.settings,
    this.sessionId,
    this.comparisonMd,
    this.blueprintMd,
    this.planJobId,
    this.liveComparisonScores,
    this.reflections = const {},
    this.chatThread,
    this.chatThreads = const [],
    this.weekUnlocks = const WeekUnlockLedger(),
  });

  final CmpysUser user;
  final CmpysIdol idol;
  final Map<String, bool> tasks; // itemId → done
  final Map<String, bool> milestones; // milestoneId → hit
  final List<CmpysWin> achievements;
  final int streak;
  final int dayNum;
  final List<CmpysNote> notes;
  final List<CmpysSavedItem> saved;
  final List<CmpysCustomTask> custom;
  final Map<String, CmpysIdeaState> ideaState;
  final CmpysSettings settings;

  /// Backend agentic-session id from onboarding. Used by Chat for the
  /// guided-learning endpoint and by Compare/Plan to refresh AI results.
  final String? sessionId;

  /// LLM-generated comparison + blueprint (markdown) from /generate-results.
  final String? comparisonMd;
  final String? blueprintMd;

  /// 12-week-plan generation job id from the onboarding `plan_job` SSE event.
  /// Polled (GET /jobs/{id}) until the Celery worker finishes writing the
  /// plan, after which /plans/current serves it.
  final String? planJobId;

  /// Raw `comparison_scores` map from the backend session. An empty map means
  /// the active session is known but its generated scores are still pending.
  final Map<String, dynamic>? liveComparisonScores;

  /// Today-tab reflections kept on this device, keyed by local date
  /// (`yyyy-MM-dd`). The server has no field for them.
  final Map<String, String> reflections;

  /// The open Mentor conversation and the archived ones, kept on this device
  /// (see [CmpysChatThread]). Null until the learner starts or reopens one.
  final CmpysChatThread? chatThread;
  final List<CmpysChatThread> chatThreads;

  /// The "Week unlocked" moments already shown on this account, per plan
  /// (see [CmpysStore.shouldShowWeekUnlock]).
  final WeekUnlockLedger weekUnlocks;

  /// A truly empty start: no pre-logged achievements, no fake streak, nothing
  /// checked off. Every entry the user sees is either backend-generated or
  /// explicitly entered by them.
  factory CmpysState.initial() => CmpysState(
        user: CmpysUser(name: '', age: 0),
        idol: cmpysPlaceholderIdol,
        tasks: const {},
        milestones: const {},
        achievements: const [],
        streak: 0,
        dayNum: 1,
        notes: const [],
        saved: const [],
        custom: const [],
        ideaState: const {},
        settings: CmpysSettings(),
      );

  CmpysState copyWith({
    CmpysUser? user,
    CmpysIdol? idol,
    Map<String, bool>? tasks,
    Map<String, bool>? milestones,
    List<CmpysWin>? achievements,
    int? streak,
    int? dayNum,
    List<CmpysNote>? notes,
    List<CmpysSavedItem>? saved,
    List<CmpysCustomTask>? custom,
    Map<String, CmpysIdeaState>? ideaState,
    CmpysSettings? settings,
    String? sessionId,
    String? comparisonMd,
    String? blueprintMd,
    String? planJobId,
    Map<String, dynamic>? liveComparisonScores,
    Map<String, String>? reflections,
    CmpysChatThread? chatThread,
    List<CmpysChatThread>? chatThreads,
    WeekUnlockLedger? weekUnlocks,
    bool clearComparisonMd = false,
    bool clearBlueprintMd = false,
  }) =>
      CmpysState(
        user: user ?? this.user,
        idol: idol ?? this.idol,
        tasks: tasks ?? this.tasks,
        milestones: milestones ?? this.milestones,
        achievements: achievements ?? this.achievements,
        streak: streak ?? this.streak,
        dayNum: dayNum ?? this.dayNum,
        notes: notes ?? this.notes,
        saved: saved ?? this.saved,
        custom: custom ?? this.custom,
        ideaState: ideaState ?? this.ideaState,
        settings: settings ?? this.settings,
        sessionId: sessionId ?? this.sessionId,
        comparisonMd:
            clearComparisonMd ? null : comparisonMd ?? this.comparisonMd,
        blueprintMd: clearBlueprintMd ? null : blueprintMd ?? this.blueprintMd,
        planJobId: planJobId ?? this.planJobId,
        liveComparisonScores: liveComparisonScores ?? this.liveComparisonScores,
        reflections: reflections ?? this.reflections,
        chatThread: chatThread ?? this.chatThread,
        chatThreads: chatThreads ?? this.chatThreads,
        weekUnlocks: weekUnlocks ?? this.weekUnlocks,
      );

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'idol': cmpysIdolToJson(idol),
        'tasks': tasks,
        'milestones': milestones,
        'achievements': achievements.map((w) => w.toJson()).toList(),
        'streak': streak,
        'dayNum': dayNum,
        'notes': notes.map((n) => n.toJson()).toList(),
        'saved': saved.map((s) => s.toJson()).toList(),
        'custom': custom.map((c) => c.toJson()).toList(),
        'ideaState': ideaState.map((k, v) => MapEntry(k, v.toJson())),
        'settings': settings.toJson(),
        'sessionId': sessionId,
        'comparisonMd': comparisonMd,
        'blueprintMd': blueprintMd,
        'planJobId': planJobId,
        'liveComparisonScores': liveComparisonScores,
        'reflections': reflections,
        'chatThread': chatThread?.toJson(),
        'chatThreads': chatThreads.map((t) => t.toJson()).toList(),
        'weekUnlocks': weekUnlocks.toJson(),
      };

  factory CmpysState.fromJson(Map<String, dynamic> j) => parseStored(j).state;

  /// Parses a stored state tolerantly and counts what had to be [dropped]:
  /// a list item or map entry that can't be read is skipped (the rest of
  /// its list still loads), and a top-level field that can't be read falls
  /// back to its initial value. Fields older builds didn't write read as
  /// their defaults.
  static ({CmpysState state, int dropped}) parseStored(
    Map<String, dynamic> j,
  ) {
    final base = CmpysState.initial();
    var dropped = 0;

    T field<T>(String key, T fallback, T Function(Object raw) parse) {
      final raw = j[key];
      if (raw == null) return fallback;
      try {
        return parse(raw);
      } catch (_) {
        dropped++;
        return fallback;
      }
    }

    List<T> list<T>(String key, List<T> fallback, T? Function(Object?) parse) =>
        field(key, fallback, (raw) {
          if (raw is! List) throw const FormatException('not a list');
          final out = <T>[];
          for (final item in raw) {
            final parsed = parse(item);
            if (parsed == null) {
              dropped++;
            } else {
              out.add(parsed);
            }
          }
          return out;
        });

    Map<String, bool> flags(Object raw) =>
        (raw as Map).map((k, v) => MapEntry(k.toString(), v == true));

    String? text(String key) => j[key] is String ? j[key] as String : null;

    final state = CmpysState(
      user: field(
        'user',
        base.user,
        (raw) => CmpysUser.fromJson((raw as Map).cast<String, dynamic>()),
      ),
      idol: field(
        'idol',
        base.idol,
        (raw) => cmpysIdolFromJson((raw as Map).cast<String, dynamic>()),
      ),
      tasks: field('tasks', base.tasks, flags),
      milestones: field('milestones', base.milestones, flags),
      achievements: list('achievements', base.achievements, CmpysWin.tryParse),
      streak: j['streak'] is num ? (j['streak'] as num).toInt() : base.streak,
      dayNum: j['dayNum'] is num ? (j['dayNum'] as num).toInt() : base.dayNum,
      notes: list('notes', base.notes, CmpysNote.tryParse),
      saved: list('saved', base.saved, CmpysSavedItem.tryParse),
      custom: list('custom', base.custom, CmpysCustomTask.tryParse),
      ideaState: field('ideaState', base.ideaState, (raw) {
        final out = <String, CmpysIdeaState>{};
        for (final e in (raw as Map).entries) {
          final parsed = CmpysIdeaState.tryParse(e.value);
          if (parsed == null) {
            dropped++;
          } else {
            out[e.key.toString()] = parsed;
          }
        }
        return out;
      }),
      settings: field(
        'settings',
        base.settings,
        (raw) => CmpysSettings.fromJson((raw as Map).cast<String, dynamic>()),
      ),
      sessionId: text('sessionId'),
      comparisonMd: text('comparisonMd'),
      blueprintMd: text('blueprintMd'),
      planJobId: text('planJobId'),
      liveComparisonScores: j['liveComparisonScores'] is Map
          ? (j['liveComparisonScores'] as Map).cast<String, dynamic>()
          : null,
      reflections: field(
        'reflections',
        base.reflections,
        (raw) => (raw as Map).map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ),
      ),
      chatThread: CmpysChatThread.tryParse(j['chatThread']),
      chatThreads: j['chatThreads'] is List
          ? [
              for (final t in j['chatThreads'] as List)
                ?CmpysChatThread.tryParse(t),
            ].take(cmpysMaxChatThreads).toList()
          : base.chatThreads,
      weekUnlocks: field(
        'weekUnlocks',
        base.weekUnlocks,
        WeekUnlockLedger.parse,
      ),
    );
    return (state: state, dropped: dropped);
  }

  // ── derived helpers (mirror record-data.jsx) ──

  /// Generated comparison dimensions exactly as the server scored them.
  /// The Record's on-device reassess never shifts them ("This isn’t a new
  /// assessment of your comparison scores"). Missing backend scores stay
  /// empty; demo values are never substituted.
  List<({
    String id,
    String label,
    int? you,
    int? idol,
    String youNote,
    String idolNote,
    String status,
    String comparisonBasis,
    String youEvidence,
    String idolEvidence,
  })> liveDims() {
    final base = dimsFromScores(liveComparisonScores) ?? const <CmpysDimension>[];
    return base
        .map((d) => (
              id: d.id,
              label: d.label,
              you: d.you,
              idol: d.idol,
              youNote: d.youNote,
              idolNote: d.idolNote,
              status: d.status,
              comparisonBasis: d.comparisonBasis,
              youEvidence: d.youEvidence,
              idolEvidence: d.idolEvidence,
            ))
        .toList();
  }

  /// Generated milestones from the active session, or an empty list while
  /// structured comparison data is unavailable.
  List<CmpysMilestone> liveMilestones() =>
      milestonesFromScores(liveComparisonScores) ?? const <CmpysMilestone>[];

  List<CmpysWin> pendingWins() =>
      achievements.where((a) => !a.assessed).toList();

  /// The age is set at intake: once an intake session (or a comparison)
  /// exists, this device can't change it, so comparisons stay fair (owner
  /// decision 3). The session's age stays the source of truth.
  bool get ageLocked =>
      sessionId != null ||
      comparisonMd?.trim().isNotEmpty == true ||
      (liveComparisonScores?.isNotEmpty ?? false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class CmpysStore extends StateNotifier<CmpysState> {
  /// A store with no account open: it holds state in memory and writes
  /// nothing until [openAccount] (the session opens the signed-in account
  /// before any screen reads the store).
  CmpysStore() : super(CmpysState.initial());

  /// Completes after the open account's persisted state has been hydrated.
  /// Backend sync waits on this barrier so a slower preferences read can
  /// never overwrite a fresher session (including newly generated
  /// comparison scores).
  Future<void> get ready => _loading;
  Future<void> _loading = Future<void>.value();

  /// The account whose data is loaded and persisted; null when none is
  /// open (signed out), and then nothing is written.
  String? get accountId => _accountId;
  String? _accountId;

  /// The open account's stored data has been read: a write before that
  /// would replace it with the placeholder state.
  bool _hydrated = true;

  /// Bumped by every open, close and reset, so a superseded load never
  /// lands.
  int _loadSeq = 0;

  int _noteSeq = 0;
  Timer? _persistTimer;

  /// Bumped by [reset], so a write encoded before it never lands after it.
  int _generation = 0;

  static const _persistDebounce = Duration(milliseconds: 300);

  @override
  void dispose() {
    // Flush a pending debounced persist so the last mutation isn't lost.
    if (_persistTimer?.isActive ?? false) {
      _persistTimer!.cancel();
      _persistNow();
    }
    super.dispose();
  }

  /// Opens [accountId]'s data on this device: a pending write for the
  /// account that was open lands in that account's store first, then
  /// [accountId]'s store is loaded (empty when it has none), so nothing
  /// leaks between accounts. Opening the account already open does nothing.
  ///
  /// An unkeyed store from an older build is migrated once, with its
  /// backup, to [unkeyedOwner] (the account it belonged to, or the first
  /// account that signs in) unless that account already has its own store;
  /// it is then removed. With no owner (a brand-new registration) it is
  /// removed without being adopted.
  Future<void> openAccount(String accountId, {required String? unkeyedOwner}) {
    if (accountId == _accountId) return _loading;
    _flushPending();
    _accountId = accountId;
    _hydrated = false;
    state = CmpysState.initial();
    final seq = ++_loadSeq;
    return _loading = _load(accountId, seq, unkeyedOwner: unkeyedOwner);
  }

  /// Closes the open account (an involuntary sign-out): a pending write
  /// lands in its store, which stays on this device for the next time that
  /// account signs in; memory goes back to the initial state.
  Future<void> closeAccount() async {
    final flush = _flushPending();
    _unbind();
    await flush;
  }

  /// Writes a pending debounced persist now, for the account that is open.
  Future<void> _flushPending() {
    if (!(_persistTimer?.isActive ?? false)) return Future<void>.value();
    _persistTimer!.cancel();
    return _persistNow();
  }

  void _unbind() {
    _loadSeq++;
    _accountId = null;
    _hydrated = true;
    _loading = Future<void>.value();
    state = CmpysState.initial();
  }

  /// Hydrates [accountId]'s store. A stored value that can't be read in
  /// full (bad JSON, or items that had to be skipped) is first copied to
  /// its backup, before any write can replace it, so a parsing bug never
  /// silently loses the learner's notes and wins.
  Future<void> _load(
    String accountId,
    int seq, {
    required String? unkeyedOwner,
  }) async {
    final key = cmpysStoreKeyFor(accountId);
    SharedPreferences prefs;
    String? raw;
    try {
      prefs = await SharedPreferences.getInstance();
      await _migrateUnkeyed(prefs, unkeyedOwner);
      raw = prefs.getString(key);
    } catch (e) {
      debugPrint('CMPYS store load failed: $e');
      if (seq == _loadSeq) _hydrated = true;
      return;
    }
    if (seq != _loadSeq) return;
    if (raw == null) {
      _hydrated = true;
      return;
    }
    var intact = false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      final parsed = CmpysState.parseStored(decoded.cast<String, dynamic>());
      state = parsed.state;
      intact = parsed.dropped == 0;
    } catch (e) {
      debugPrint('CMPYS store load failed: $e');
    }
    if (!intact) {
      try {
        await prefs.setString(cmpysStoreBackupKeyFor(accountId), raw);
      } catch (e) {
        debugPrint('CMPYS store backup failed: $e');
      }
    }
    if (seq == _loadSeq) _hydrated = true;
  }

  /// Moves an older build's unkeyed store (and its backup) to [owner]'s
  /// keys, once, without overwriting a store [owner] already has; with no
  /// owner it is only removed.
  static Future<void> _migrateUnkeyed(
    SharedPreferences prefs,
    String? owner,
  ) async {
    final legacy = prefs.getString(_storeKey);
    final legacyBackup = prefs.getString(_backupKey);
    if (legacy == null && legacyBackup == null) return;
    if (owner != null) {
      final key = cmpysStoreKeyFor(owner);
      final backupKey = cmpysStoreBackupKeyFor(owner);
      if (legacy != null && prefs.getString(key) == null) {
        await prefs.setString(key, legacy);
        if (legacyBackup != null && prefs.getString(backupKey) == null) {
          await prefs.setString(backupKey, legacyBackup);
        }
      }
    }
    await prefs.remove(_storeKey);
    await prefs.remove(_backupKey);
  }

  /// Debounced persist: encoding the whole state (including two full LLM
  /// markdown docs) on every checkbox tap/like/note is needlessly heavy, so
  /// rapid mutations coalesce into one write. Still best-effort; a pending
  /// write is flushed in [dispose] and when the account changes.
  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      final account = _accountId;
      // No account open (signed out): nothing is written.
      if (account == null) return;
      if (!_hydrated) {
        // Never write before hydration has finished (and backed up a store
        // it couldn't read): wait, then write what is loaded.
        await _loading;
        if (!mounted || _accountId != account || !_hydrated) return;
      }
      // Encode before the async gap so the flush-on-dispose path never reads
      // state after the notifier is disposed; the key is the account this
      // state belongs to.
      final encoded = jsonEncode(state.toJson());
      final generation = _generation;
      final prefs = await SharedPreferences.getInstance();
      // A reset meanwhile cleared the account: this write is stale.
      if (generation != _generation) return;
      await prefs.setString(cmpysStoreKeyFor(account), encoded);
    } catch (e) {
      debugPrint('CMPYS store persist failed: $e');
    }
  }

  void _set(CmpysState next) {
    state = next;
    _persist();
  }

  // ── tasks ──
  void toggleTask(String id) {
    final next = Map<String, bool>.from(state.tasks);
    next[id] = !(next[id] ?? false);
    _set(state.copyWith(tasks: next));
  }


  // ── achievements ──
  /// Adds a win to the record and returns its id. [synced] marks a win that
  /// was also saved to the server as an achievement, and [serverId] is that
  /// achievement's id (so the Record can delete both copies). A win whose
  /// [serverId] is already on the record replaces it (the server upserts a
  /// mission's achievement), keeping its record id. An [age] of 0 (unknown)
  /// is kept: the Record shows such a win under "Undated".
  ///
  /// Only a `chat` win starts with a mentor line (replaced by the mentor's
  /// streamed reply, [setWinIdolNote]); any other win has no mentor note
  /// unless [idolNote] is given, so the Record never shows a canned line the
  /// mentor didn't write.
  String addWin({
    required String title,
    required String dim,
    required int age,
    int impact = 2,
    String source = 'manual',
    String note = '',
    bool photo = false,
    String? idolNote,
    bool assessed = false,
    bool synced = false,
    String? serverId,
  }) {
    final existing = serverId == null
        ? null
        : state.achievements.where((w) => w.serverId == serverId).firstOrNull;
    final win = CmpysWin(
      id: existing?.id ?? 'w${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      dim: dim,
      age: age,
      impact: impact,
      source: source,
      assessed: assessed,
      note: note,
      photo: photo,
      idolNote: idolNote ?? (source == 'chat' ? idolReaction(dim, title) : null),
      synced: synced,
      serverId: serverId,
    );
    _set(state.copyWith(
      achievements: existing == null
          ? [...state.achievements, win]
          : [
              for (final w in state.achievements)
                if (identical(w, existing)) win else w,
            ],
    ));
    return win.id;
  }

  /// Replaces the Record's wins with [merge]'s result for the current state
  /// (the server restore; null means nothing changes), only while
  /// [accountId]'s data is the one open and loaded, so wins fetched for one
  /// account never land on another's Record. Returns whether it applied.
  bool restoreWins(
    String accountId,
    List<CmpysWin>? Function(CmpysState state) merge,
  ) {
    if (_accountId != accountId || !_hydrated) return false;
    final wins = merge(state);
    if (wins == null) return false;
    _set(state.copyWith(achievements: wins));
    return true;
  }

  /// Replaces a win's mentor note (the Mentor tab's streamed reply to a
  /// reported win).
  void setWinIdolNote(String id, String idolNote) {
    _set(state.copyWith(
      achievements: [
        for (final w in state.achievements)
          if (w.id == id) w.copyWith(idolNote: idolNote) else w,
      ],
    ));
  }

  // ── Mentor conversations (on this device) ──
  /// Stores the open conversation and/or the archived list. The archive is
  /// kept newest first and capped at [cmpysMaxChatThreads]; each thread
  /// keeps its latest [cmpysMaxChatMsgs] messages.
  void setChat({CmpysChatThread? current, List<CmpysChatThread>? archived}) {
    List<CmpysChatThread>? list;
    if (archived != null) {
      list = [for (final t in archived) t.capped()]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (list.length > cmpysMaxChatThreads) {
        list = list.sublist(0, cmpysMaxChatThreads);
      }
    }
    _set(state.copyWith(chatThread: current?.capped(), chatThreads: list));
  }

  void deleteChatThread(String id) {
    _set(state.copyWith(
        chatThreads: state.chatThreads.where((t) => t.id != id).toList()));
  }

  /// Claims a comparison milestone: marks it claimed and adds a `milestone`
  /// win that remembers [milestoneId]. [dim] is the milestone's own v3
  /// dimension when known; otherwise the position mapping applies.
  void claimMilestone(String milestoneId, String label,
      {required int age, String note = '', bool photo = false, String? dim}) {
    final winDim = dim ?? cmpysMilestoneDim[milestoneId] ?? 'judgment';
    final ms = Map<String, bool>.from(state.milestones)..[milestoneId] = true;
    final win = CmpysWin(
      id: 'w${DateTime.now().microsecondsSinceEpoch}',
      title: label,
      dim: winDim,
      age: age,
      impact: 3,
      source: 'milestone',
      assessed: false,
      note: note,
      photo: photo,
      // The mentor never wrote a note on a claim: none is shown.
      milestoneId: milestoneId,
    );
    _set(state.copyWith(
      milestones: ms,
      achievements: [...state.achievements, win],
    ));
  }

  /// Removes a win. Deleting a claim also clears its milestone's claimed
  /// state, so the milestone can be claimed again.
  void deleteWin(String id) {
    final claimed = state.achievements
        .where((w) => w.id == id)
        .map((w) => w.milestoneId)
        .nonNulls
        .toSet();
    final ms = claimed.isEmpty
        ? null
        : (Map<String, bool>.from(state.milestones)
            ..removeWhere((k, _) => claimed.contains(k)));
    _set(state.copyWith(
        milestones: ms,
        achievements: state.achievements.where((w) => w.id != id).toList()));
  }

  /// The Record's on-device reassess: marks every win reviewed. It changes
  /// the Record's own view only (the pending banner), never the server's
  /// comparison scores.
  void reassess() {
    final assessed =
        state.achievements.map((w) => w.copyWith(assessed: true)).toList();
    _set(state.copyWith(achievements: assessed));
  }

  // ── notes ──
  void saveNote(
      {required String kind, required String title, required String body, String? from}) {
    _noteSeq++;
    final note = CmpysNote(
      id: 'n${DateTime.now().microsecondsSinceEpoch}$_noteSeq',
      kind: kind,
      title: title,
      body: body,
      from: from,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    _set(state.copyWith(notes: [note, ...state.notes]));
  }

  void deleteNote(String id) {
    _set(state.copyWith(notes: state.notes.where((n) => n.id != id).toList()));
  }

  // ── saved ──
  /// Removes [id] from Saved. A saved idea also loses its reels bookmark, so
  /// the two never disagree.
  void unsave(String id) {
    final saved = state.saved.where((s) => s.id != id).toList();
    final idea = state.ideaState[id];
    if (idea == null || !idea.saved) {
      _set(state.copyWith(saved: saved));
      return;
    }
    final ideaNext = Map<String, CmpysIdeaState>.from(state.ideaState);
    ideaNext[id] = CmpysIdeaState(
        liked: idea.liked, saved: false, comments: idea.comments);
    _set(state.copyWith(saved: saved, ideaState: ideaNext));
  }

  // ── ideas ──
  CmpysIdeaState ideaOf(String id) =>
      state.ideaState[id] ?? CmpysIdeaState();

  void likeIdea(String id) {
    final cur = ideaOf(id);
    final next = Map<String, CmpysIdeaState>.from(state.ideaState);
    next[id] = CmpysIdeaState(
        liked: !cur.liked, saved: cur.saved, comments: cur.comments);
    _set(state.copyWith(ideaState: next));
  }

  /// Returns true if now saved.
  bool toggleIdeaSave(
      {required String id, required String title, required String author}) {
    final cur = ideaOf(id);
    final willSave = !cur.saved;
    final ideaNext = Map<String, CmpysIdeaState>.from(state.ideaState);
    ideaNext[id] = CmpysIdeaState(
        liked: cur.liked, saved: willSave, comments: cur.comments);
    final saved = willSave
        ? [
            CmpysSavedItem(id: id, kind: 'idea', title: title, sub: author),
            ...state.saved.where((s) => s.id != id),
          ]
        : state.saved.where((s) => s.id != id).toList();
    _set(state.copyWith(ideaState: ideaNext, saved: saved));
    return willSave;
  }

  void commentIdea(String id, ({String who, String text}) comment) {
    final cur = ideaOf(id);
    final next = Map<String, CmpysIdeaState>.from(state.ideaState);
    next[id] = CmpysIdeaState(
        liked: cur.liked,
        saved: cur.saved,
        comments: [...cur.comments, comment]);
    _set(state.copyWith(ideaState: next));
  }

  // ── reflections (Today tab, on this device) ──

  /// Stores [text] as the reflection for [dateKey] (`yyyy-MM-dd`); blank text
  /// removes it.
  void setReflection(String dateKey, String text) {
    final next = Map<String, String>.from(state.reflections);
    if (text.trim().isEmpty) {
      if (next.remove(dateKey) == null) return;
    } else {
      if (next[dateKey] == text) return;
      next[dateKey] = text;
    }
    _set(state.copyWith(reflections: next));
  }

  // ── settings ──
  void toggleSetting(String key) {
    final s = state.settings.copy();
    switch (key) {
      case 'reminder':
        s.reminder = !s.reminder;
        break;
      case 'mentorPing':
        s.mentorPing = !s.mentorPing;
        break;
      case 'digest':
        s.digest = !s.digest;
        break;
      case 'haptics':
        s.haptics = !s.haptics;
        break;
    }
    _set(state.copyWith(settings: s));
  }

  /// Reader text size step (0 "A", 1 "A+", 2 "A++"), kept on this device.
  void setReadSize(int size) {
    final next = size.clamp(0, 2);
    if (state.settings.readSize == next) return;
    _set(state.copyWith(settings: state.settings.copy()..readSize = next));
  }

  /// Reader theme name (light, sepia or dark), kept on this device.
  void setReadTheme(String name) {
    if (!const {'light', 'sepia', 'dark'}.contains(name)) return;
    if (state.settings.readTheme == name) return;
    _set(state.copyWith(settings: state.settings.copy()..readTheme = name));
  }

  // ── user / idol ──
  /// Edits the profile on this device. Once [CmpysState.ageLocked], [age]
  /// is ignored: the intake session's age stands.
  void updateUser({String? name, int? age, List<String>? interests}) {
    final u = CmpysUser(
      name: name ?? state.user.name,
      age: state.ageLocked ? state.user.age : (age ?? state.user.age),
      interests: interests ?? state.user.interests,
      goalId: state.user.goalId,
    );
    _set(state.copyWith(user: u));
  }

  // ── week unlocks ──

  /// Whether the "Week unlocked" moment for [week] of [planId] should show
  /// now: never for week 1, at most once per plan and week on this account,
  /// and only once the account's stored data has loaded (so an early check
  /// can't replay a moment already shown). False with no account open.
  bool shouldShowWeekUnlock(String planId, int week) =>
      _accountId != null &&
      _hydrated &&
      state.weekUnlocks.shouldShow(planId, week);

  /// Records that [week] of [planId] has been shown on this account and
  /// writes it at once (not debounced), so it shows only once even if the
  /// app is closed right after.
  Future<void> markWeekUnlockShown(String planId, int week) {
    final next = state.weekUnlocks.marked(planId, week);
    if (identical(next, state.weekUnlocks)) return Future<void>.value();
    _set(state.copyWith(weekUnlocks: next));
    return _flushPending();
  }

  /// Persist a plan-generation job id discovered outside onboarding (e.g.
  /// the recovery path that re-enqueues generation for a completed session).
  void setPlanJobId(String jobId) {
    if (jobId.isEmpty || state.planJobId == jobId) return;
    _set(state.copyWith(planJobId: jobId));
  }

  /// Clears the open account's data on this device (a deliberate logout):
  /// its store and backup are removed and the store closes, so the next
  /// account never inherits this user's mentor, achievements or notes.
  /// Other accounts' stores are left alone.
  Future<void> reset() async {
    // The account open when the logout was asked for is the one cleared.
    final account = _accountId;
    // Startup hydration must finish before clearing an expired account.
    await _loading;
    _persistTimer?.cancel(); // a pending write must not resurrect old state
    _generation++;
    if (_accountId == account) _unbind();
    if (account == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cmpysStoreKeyFor(account));
      // The backup is this account's data too.
      await prefs.remove(cmpysStoreBackupKeyFor(account));
    } catch (e) {
      debugPrint('CMPYS store reset failed: $e');
    }
  }

  /// Hydrates mentor + AI results from the backend's latest session — the
  /// source of truth. Repairs any drift between local state and the backend
  /// (e.g. an onboarding run that didn't finish cleanly, or an app reinstall).
  void syncFromSession(Session session) {
    final idolName = session.selectedIdol?.name;
    var next = state;

    if (idolName != null && idolName.trim().isNotEmpty) {
      final mismatch =
          state.idol.name.toLowerCase().trim() != idolName.toLowerCase().trim();
      if (mismatch || state.sessionId != session.id) {
        final idol = cmpysIdolFromSuggestion(
          name: idolName,
          era: session.selectedIdol?.era ?? '',
          summary: '',
          domains: const [],
        );
        next = next.copyWith(idol: idol);
      }
    }

    // Resolve the effective values first (copyWith keeps the old value when a
    // synced field is absent) and no-op when nothing changed — otherwise every
    // sync (app entry, Today tab, every chat send) causes a global rebuild
    // plus a full persist.
    final switchedSession = session.id != next.sessionId;
    // Another session than the stored one (not the first sync): nothing of
    // the old session's results may stand in for the new one's, so its
    // claimed milestones and written texts go even while the new texts are
    // still empty.
    final replacing = switchedSession && next.sessionId != null;
    String? text(String? fresh, String? kept) =>
        fresh != null && fresh.trim().isNotEmpty
        ? fresh
        : (replacing ? null : kept);
    final comparisonMd = text(session.comparisonOutput, next.comparisonMd);
    final blueprintMd = text(session.blueprintOutput, next.blueprintMd);
    final milestones = replacing ? const <String, bool>{} : next.milestones;
    final scores = session.comparisonScores ??
        (switchedSession ? const <String, dynamic>{} : next.liveComparisonScores);
    // The age is set at intake, so the session's age is the source of truth
    // (owner decision 3). Interests are editable on this device (Edit
    // profile): the session's only win for a new session or an empty local
    // value, so re-syncing the same session doesn't undo a device edit.
    final age = session.userAge > 0 ? session.userAge : next.user.age;
    final interests = session.userInterests.isNotEmpty &&
            (switchedSession || next.user.interests.isEmpty)
        ? session.userInterests
        : next.user.interests;

    final unchanged = identical(next, state) &&
        next.sessionId == session.id &&
        comparisonMd == next.comparisonMd &&
        blueprintMd == next.blueprintMd &&
        _scoresEqual(scores, next.liveComparisonScores) &&
        age == next.user.age &&
        listEquals(interests, next.user.interests);
    if (unchanged) return;

    next = next.copyWith(
      sessionId: session.id,
      comparisonMd: comparisonMd,
      clearComparisonMd: comparisonMd == null,
      blueprintMd: blueprintMd,
      clearBlueprintMd: blueprintMd == null,
      milestones: milestones,
      liveComparisonScores: scores,
      user: CmpysUser(
        name: next.user.name,
        age: age,
        interests: interests,
        goalId: next.user.goalId,
      ),
    );

    _set(next);
  }

  /// Deep-equality for the raw comparison-scores map. Each sync parses a fresh
  /// map from the backend response, so instance identity is never enough. The
  /// map is small (a handful of dimensions/milestones), so comparing the JSON
  /// encoding is cheap and avoids a hand-rolled deep compare.
  static bool _scoresEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  /// Called when onboarding completes — seeds user + idol + the AI results
  /// (comparison/blueprint markdown) and the backend session id used by Chat.
  void completeOnboarding({
    required String name,
    required int age,
    required List<String> interests,
    String? goalId,
    required CmpysIdol idol,
    String? sessionId,
    String? comparisonMd,
    String? blueprintMd,
    String? planJobId,
  }) {
    final u = CmpysUser(
        name: name, age: age, interests: interests, goalId: goalId);
    _set(state.copyWith(
      user: u,
      idol: idol,
      sessionId: sessionId,
      comparisonMd: comparisonMd,
      blueprintMd: blueprintMd,
      planJobId: planJobId,
    ));
  }
}

final cmpysStoreProvider =
    StateNotifierProvider<CmpysStore, CmpysState>((ref) => CmpysStore());
