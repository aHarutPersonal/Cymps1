// The Record restore (owner decision 1): on sign-in, and on a cold start
// while signed in, the account's achievements (`GET /achievements`) are
// merged into the Record on this device, so wins saved to the account come
// back after a logout or on a new device. Device-only notes and wins stay as
// they are.

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/controllers/session_controller.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import '../state/cmpys_backend_sync.dart';
import '../state/cmpys_store.dart';
import 'cmpys_record_data.dart';
import 'reported_win.dart' show recordDimForCategory;

/// The Record's [wins] with the server achievements [server] merged in, or
/// null when nothing changes.
///
/// - A win with an achievement's `serverId` is already on the Record: it is
///   left as it is, never duplicated.
/// - A legacy synced win without a `serverId` (an older build didn't keep
///   it) whose title and date match an achievement adopts that achievement's
///   id instead of gaining a duplicate. Its date is when it was saved on this
///   device (its id, `w` + microseconds); the achievement's is when the
///   server saved it, or the date the user gave. Each legacy win adopts one
///   achievement at most.
/// - Any other achievement joins the Record: synced, assessed, filed under
///   its category's dimension (or Practice), at [age] (0 when unknown, so
///   the Record shows it under "Undated"), with its notes and no mentor note.
List<CmpysWin>? mergeServerAchievements(
  List<CmpysWin> wins,
  List<ServerAchievement> server, {
  required int age,
}) {
  final known = {
    for (final w in wins)
      if (w.serverId != null) w.serverId!,
  };
  final next = [...wins];
  var changed = false;
  for (final a in server) {
    if (!known.add(a.id)) continue;
    final legacy = next.indexWhere(
      (w) => w.synced && w.serverId == null && _sameWin(w, a),
    );
    if (legacy >= 0) {
      next[legacy] = next[legacy].copyWith(serverId: a.id);
    } else {
      next.add(
        CmpysWin(
          id: 'srv-${a.id}',
          title: a.title,
          dim: recordDimForCategory(a.category) ?? 'practice',
          age: math.max(0, age),
          impact: 2,
          source: a.source == 'manual' ? 'manual' : 'auto',
          assessed: true,
          note: a.notes?.trim() ?? '',
          synced: true,
          serverId: a.id,
        ),
      );
    }
    changed = true;
  }
  return changed ? next : null;
}

/// Same title (ignoring case and outer spaces) and same calendar day.
bool _sameWin(CmpysWin win, ServerAchievement a) {
  if (win.title.trim().toLowerCase() != a.title.trim().toLowerCase()) {
    return false;
  }
  final saved = _savedOn(win);
  if (saved == null) return false;
  final created = a.createdAt?.toLocal();
  return (created != null && _sameDay(saved, created)) ||
      (a.achievementDate != null && _sameDay(saved, a.achievementDate!));
}

/// When a device win was saved: its id is `w` + microseconds since epoch.
DateTime? _savedOn(CmpysWin win) {
  final match = RegExp(r'^w(\d+)$').firstMatch(win.id);
  final micros = match == null ? null : int.tryParse(match.group(1)!);
  return micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Restores the signed-in account's achievements into the Record, once per
/// sign-in and per cold start (it reruns when the account changes). It
/// waits for the store to load and the session sync to set the learner's
/// age, reads every page of `GET /achievements`, then merges
/// ([mergeServerAchievements]) only while that account's data is still the
/// one open. A failure is silent: the Record stays as it was.
final cmpysRecordRestoreProvider = FutureProvider<void>((ref) async {
  final accountId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (accountId == null) return;
  try {
    final store = ref.read(cmpysStoreProvider.notifier);
    await store.ready;
    await ref.read(cmpysBackendSyncProvider.future);
    final server = await ref.read(planRepositoryProvider).listAchievements();
    store.restoreWins(
      accountId,
      (state) => mergeServerAchievements(
        state.achievements,
        server,
        age: state.user.age,
      ),
    );
  } catch (_) {
    // Best effort: offline, or an older server, keeps the Record as it is.
  }
});
