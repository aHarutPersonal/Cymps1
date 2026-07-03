// CMPYS shared app store.
//
// One Riverpod StateNotifier holding every piece of mutable app state the
// design's screens read and write — tasks, milestones, achievements, dimension
// shifts, notes, saved items, idea interactions, settings, custom plan items,
// the user profile, and the active idol. Mirrors the prototype's single store
// (main.jsx) so toggles, counts, and saves stay consistent across all tabs and
// detail screens. Persisted to shared_preferences.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../session/models/session_models.dart';
import '../data/cmpys_record_data.dart';
import '../data/cmpys_seed.dart';

const _storeKey = 'cmpys_store_v1';

// ─────────────────────────────────────────────────────────────────────────────
// Conversion helpers — raw comparisonScores map → seed-shaped objects
// ─────────────────────────────────────────────────────────────────────────────

/// Convert a raw `comparisonScores` map (from the session) into seed-shaped
/// dimensions. Returns null when absent/empty so callers fall back to seed.
List<CmpysDimension>? dimsFromScores(Map<String, dynamic>? scores) {
  final raw = scores?['dimensions'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <CmpysDimension>[];
  for (final d in raw) {
    if (d is! Map) continue;
    out.add(CmpysDimension(
      id: (d['id'] ?? '').toString(),
      label: (d['label'] ?? '').toString(),
      you: (d['you'] as num?)?.toInt() ?? 0,
      idol: (d['idol'] as num?)?.toInt() ?? 0,
      youNote: (d['you_note'] ?? '').toString(),
      idolNote: (d['idol_note'] ?? '').toString(),
    ));
  }
  return out.isEmpty ? null : out;
}

/// Convert raw milestones into seed-shaped CmpysMilestone with stable ids
/// (`m1`..). Returns null when absent so callers fall back to seed.
List<CmpysMilestone>? milestonesFromScores(Map<String, dynamic>? scores) {
  final raw = scores?['milestones'];
  if (raw is! List || raw.isEmpty) return null;
  final out = <CmpysMilestone>[];
  for (var i = 0; i < raw.length; i++) {
    final m = raw[i];
    if (m is! Map) continue;
    final label = (m['label'] ?? m['text'] ?? '').toString();
    if (label.isEmpty) continue;
    out.add(CmpysMilestone((m['id'] ?? 'm${i + 1}').toString(), label));
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
  });
  final String id;
  final String kind; // chat | read | book | …
  final String title;
  final String body;
  final String? from;
  final String when;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'from': from,
        'when': when,
      };
  factory CmpysNote.fromJson(Map<String, dynamic> j) => CmpysNote(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'chat',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        from: j['from'] as String?,
        when: j['when'] as String? ?? 'Saved',
      );
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
  factory CmpysSavedItem.fromJson(Map<String, dynamic> j) => CmpysSavedItem(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'idea',
        title: j['title'] as String? ?? '',
        sub: j['sub'] as String?,
      );
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
  factory CmpysIdeaState.fromJson(Map<String, dynamic> j) => CmpysIdeaState(
        liked: j['liked'] as bool? ?? false,
        saved: j['saved'] as bool? ?? false,
        comments: (j['comments'] as List?)
                ?.map((e) => (
                      who: (e as Map)['who']?.toString() ?? 'You',
                      text: e['text']?.toString() ?? '',
                    ))
                .toList() ??
            [],
      );
}

class CmpysCustomTask {
  CmpysCustomTask({required this.id, required this.title});
  final String id;
  final String title;
  Map<String, dynamic> toJson() => {'id': id, 'title': title};
  factory CmpysCustomTask.fromJson(Map<String, dynamic> j) =>
      CmpysCustomTask(id: j['id'] as String, title: j['title'] as String? ?? '');
}

class CmpysSettings {
  CmpysSettings({
    this.reminder = true,
    this.mentorPing = true,
    this.digest = true,
    this.haptics = true,
  });
  bool reminder;
  bool mentorPing;
  bool digest;
  bool haptics;

  CmpysSettings copy() => CmpysSettings(
      reminder: reminder, mentorPing: mentorPing, digest: digest, haptics: haptics);

  Map<String, dynamic> toJson() => {
        'reminder': reminder,
        'mentorPing': mentorPing,
        'digest': digest,
        'haptics': haptics,
      };
  factory CmpysSettings.fromJson(Map<String, dynamic> j) => CmpysSettings(
        reminder: j['reminder'] as bool? ?? true,
        mentorPing: j['mentorPing'] as bool? ?? true,
        digest: j['digest'] as bool? ?? true,
        haptics: j['haptics'] as bool? ?? true,
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
    required this.dimShift,
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
  });

  final CmpysUser user;
  final CmpysIdol idol;
  final Map<String, bool> tasks; // itemId → done
  final Map<String, bool> milestones; // milestoneId → hit
  final List<CmpysWin> achievements;
  final Map<String, int> dimShift; // dimId → +delta
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

  /// Raw `comparison_scores` map from the backend session. When present,
  /// [liveDims] and [liveMilestones] use these real values; when null they
  /// fall back to the seed data.
  final Map<String, dynamic>? liveComparisonScores;

  /// A truly empty start: no pre-logged achievements, no fake streak, nothing
  /// checked off. Every entry the user sees is either backend-generated or
  /// explicitly entered by them.
  factory CmpysState.initial() => CmpysState(
        user: CmpysUser(name: '', age: 24),
        idol: defaultIdol(),
        tasks: const {},
        milestones: const {},
        achievements: const [],
        dimShift: const {},
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
    Map<String, int>? dimShift,
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
  }) =>
      CmpysState(
        user: user ?? this.user,
        idol: idol ?? this.idol,
        tasks: tasks ?? this.tasks,
        milestones: milestones ?? this.milestones,
        achievements: achievements ?? this.achievements,
        dimShift: dimShift ?? this.dimShift,
        streak: streak ?? this.streak,
        dayNum: dayNum ?? this.dayNum,
        notes: notes ?? this.notes,
        saved: saved ?? this.saved,
        custom: custom ?? this.custom,
        ideaState: ideaState ?? this.ideaState,
        settings: settings ?? this.settings,
        sessionId: sessionId ?? this.sessionId,
        comparisonMd: comparisonMd ?? this.comparisonMd,
        blueprintMd: blueprintMd ?? this.blueprintMd,
        planJobId: planJobId ?? this.planJobId,
        liveComparisonScores: liveComparisonScores ?? this.liveComparisonScores,
      );

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'idol': cmpysIdolToJson(idol),
        'tasks': tasks,
        'milestones': milestones,
        'achievements': achievements.map((w) => w.toJson()).toList(),
        'dimShift': dimShift,
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
      };

  factory CmpysState.fromJson(Map<String, dynamic> j) {
    final base = CmpysState.initial();
    return CmpysState(
      user: j['user'] is Map
          ? CmpysUser.fromJson((j['user'] as Map).cast<String, dynamic>())
          : base.user,
      idol: j['idol'] is Map
          ? cmpysIdolFromJson((j['idol'] as Map).cast<String, dynamic>())
          : base.idol,
      tasks: (j['tasks'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v == true)) ??
          base.tasks,
      milestones: (j['milestones'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v == true)) ??
          base.milestones,
      achievements: (j['achievements'] as List?)
              ?.map((e) => CmpysWin.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          base.achievements,
      dimShift: (j['dimShift'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          base.dimShift,
      streak: (j['streak'] as num?)?.toInt() ?? base.streak,
      dayNum: (j['dayNum'] as num?)?.toInt() ?? base.dayNum,
      notes: (j['notes'] as List?)
              ?.map((e) => CmpysNote.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          base.notes,
      saved: (j['saved'] as List?)
              ?.map((e) =>
                  CmpysSavedItem.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          base.saved,
      custom: (j['custom'] as List?)
              ?.map((e) =>
                  CmpysCustomTask.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          base.custom,
      ideaState: (j['ideaState'] as Map?)?.map((k, v) => MapEntry(
                k.toString(),
                CmpysIdeaState.fromJson((v as Map).cast<String, dynamic>()),
              )) ??
          base.ideaState,
      settings: j['settings'] is Map
          ? CmpysSettings.fromJson((j['settings'] as Map).cast<String, dynamic>())
          : base.settings,
      sessionId: j['sessionId'] as String?,
      comparisonMd: j['comparisonMd'] as String?,
      blueprintMd: j['blueprintMd'] as String?,
      planJobId: j['planJobId'] as String?,
    );
  }

  // ── derived helpers (mirror record-data.jsx) ──

  /// Comparison dimensions with reassessment shifts applied (you-score capped 100).
  /// Prefers real dims from the session when present, else the seed list.
  List<({String id, String label, int you, int idol, String youNote, String idolNote})>
      liveDims() {
    final base = dimsFromScores(liveComparisonScores) ??
        cmpysComparison.dimensions;
    return base
        .map((d) => (
              id: d.id,
              label: d.label,
              you: (d.you + (dimShift[d.id] ?? 0)).clamp(0, 100),
              idol: d.idol,
              youNote: d.youNote,
              idolNote: d.idolNote,
            ))
        .toList();
  }

  /// Real milestones from the session when present, else the seed list.
  List<CmpysMilestone> liveMilestones() =>
      milestonesFromScores(liveComparisonScores) ??
      cmpysComparison.milestones;

  List<CmpysWin> pendingWins() =>
      achievements.where((a) => !a.assessed).toList();

  /// dim → summed impact of pending wins.
  Map<String, int> assessDeltas() {
    final out = <String, int>{};
    for (final w in pendingWins()) {
      out[w.dim] = (out[w.dim] ?? 0) + w.impact;
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class CmpysStore extends StateNotifier<CmpysState> {
  CmpysStore() : super(CmpysState.initial()) {
    _load();
  }

  int _noteSeq = 0;
  Timer? _persistTimer;

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

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw != null) {
        state = CmpysState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('CMPYS store load failed: $e');
    }
  }

  /// Debounced persist: encoding the whole state (including two full LLM
  /// markdown docs) on every checkbox tap/like/note is needlessly heavy, so
  /// rapid mutations coalesce into one write. Still best-effort; a pending
  /// write is flushed in [dispose].
  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      // Encode before the async gap so the flush-on-dispose path never reads
      // state after the notifier is disposed.
      final encoded = jsonEncode(state.toJson());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storeKey, encoded);
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

  bool isTaskDone(String id) => state.tasks[id] ?? false;

  // ── milestones ──
  void toggleMilestone(String id) {
    final next = Map<String, bool>.from(state.milestones);
    next[id] = !(next[id] ?? false);
    _set(state.copyWith(milestones: next));
  }

  // ── achievements ──
  void addWin({
    required String title,
    required String dim,
    required int age,
    int impact = 2,
    String source = 'manual',
    String note = '',
    bool photo = false,
    String? idolNote,
  }) {
    final win = CmpysWin(
      id: 'w${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      dim: dim,
      age: age,
      impact: impact,
      source: source,
      assessed: false,
      note: note,
      photo: photo,
      idolNote: idolNote ?? idolReaction(dim, title),
    );
    _set(state.copyWith(achievements: [...state.achievements, win]));
  }

  void claimMilestone(String milestoneId, String label,
      {required int age, String note = '', bool photo = false}) {
    final dim = cmpysMilestoneDim[milestoneId] ?? 'clarity';
    final ms = Map<String, bool>.from(state.milestones)..[milestoneId] = true;
    final win = CmpysWin(
      id: 'w${DateTime.now().microsecondsSinceEpoch}',
      title: label,
      dim: dim,
      age: age,
      impact: 3,
      source: 'milestone',
      assessed: false,
      note: note,
      photo: photo,
      idolNote: idolReaction(dim, label),
    );
    _set(state.copyWith(
      milestones: ms,
      achievements: [...state.achievements, win],
    ));
  }

  void deleteWin(String id) {
    _set(state.copyWith(
        achievements: state.achievements.where((w) => w.id != id).toList()));
  }

  /// Commit reassessment: fold deltas into dimShift, mark all wins assessed.
  void reassess(Map<String, int> deltas) {
    final shift = Map<String, int>.from(state.dimShift);
    deltas.forEach((k, v) => shift[k] = (shift[k] ?? 0) + v);
    final assessed = state.achievements
        .map((w) => CmpysWin(
              id: w.id,
              title: w.title,
              dim: w.dim,
              age: w.age,
              impact: w.impact,
              source: w.source,
              assessed: true,
              note: w.note,
              idolNote: w.idolNote,
              photo: w.photo,
            ))
        .toList();
    _set(state.copyWith(dimShift: shift, achievements: assessed));
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
    );
    _set(state.copyWith(notes: [note, ...state.notes]));
  }

  void deleteNote(String id) {
    _set(state.copyWith(notes: state.notes.where((n) => n.id != id).toList()));
  }

  // ── saved ──
  bool isSaved(String id) => state.saved.any((s) => s.id == id);

  /// Returns true if the item is now saved.
  bool toggleSave(
      {required String id, required String kind, required String title, String? sub}) {
    final has = isSaved(id);
    if (has) {
      _set(state.copyWith(saved: state.saved.where((s) => s.id != id).toList()));
      return false;
    }
    _set(state.copyWith(saved: [
      CmpysSavedItem(id: id, kind: kind, title: title, sub: sub),
      ...state.saved,
    ]));
    return true;
  }

  void unsave(String id) {
    _set(state.copyWith(saved: state.saved.where((s) => s.id != id).toList()));
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

  // ── custom plan tasks (from chat) ──
  bool customAdded(String title) => state.custom.any((c) => c.title == title);

  void addCustomTask(String title) {
    if (customAdded(title)) return;
    _set(state.copyWith(custom: [
      ...state.custom,
      CmpysCustomTask(id: 'c${DateTime.now().microsecondsSinceEpoch}', title: title),
    ]));
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

  // ── user / idol ──
  void updateUser({String? name, int? age, List<String>? interests}) {
    final u = CmpysUser(
      name: name ?? state.user.name,
      age: age ?? state.user.age,
      interests: interests ?? state.user.interests,
      goalId: state.user.goalId,
    );
    _set(state.copyWith(user: u));
  }

  void switchMentor(CmpysIdol idol) {
    _set(state.copyWith(idol: idol));
  }

  /// Persist a plan-generation job id discovered outside onboarding (e.g.
  /// the recovery path that re-enqueues generation for a completed session).
  void setPlanJobId(String jobId) {
    if (jobId.isEmpty || state.planJobId == jobId) return;
    _set(state.copyWith(planJobId: jobId));
  }

  /// Clears all persisted local state. Called on logout so the next account
  /// never inherits a previous user's mentor, achievements, or notes.
  Future<void> reset() async {
    _persistTimer?.cancel(); // a pending write must not resurrect old state
    state = CmpysState.initial();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storeKey);
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
    final comparison = session.comparisonOutput;
    final blueprint = session.blueprintOutput;
    final comparisonMd = (comparison != null && comparison.trim().isNotEmpty)
        ? comparison
        : next.comparisonMd;
    final blueprintMd = (blueprint != null && blueprint.trim().isNotEmpty)
        ? blueprint
        : next.blueprintMd;
    final scores = session.comparisonScores ?? next.liveComparisonScores;
    final age = session.userAge > 0 ? session.userAge : next.user.age;
    final interests = session.userInterests.isNotEmpty
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
      blueprintMd: blueprintMd,
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
