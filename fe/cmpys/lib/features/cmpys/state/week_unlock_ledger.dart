import 'package:flutter/foundation.dart';

/// Which "Week unlocked" moments (`showWeekUnlock`) have been shown, per
/// plan. It lives in the per-account CMPYS store ([CmpysState.weekUnlocks]),
/// so it is kept per account and survives restarts; the store's
/// `shouldShowWeekUnlock` / `markWeekUnlockShown` are the API screens use.
///
/// A week shows at most once per plan, and week 1 never does (nothing was
/// unlocked: the plan starts there).
@immutable
class WeekUnlockLedger {
  const WeekUnlockLedger([this._shown = const {}]);

  /// Plan id → week numbers already shown.
  final Map<String, Set<int>> _shown;

  /// Whether [week] of [planId] may still show.
  bool shouldShow(String planId, int week) =>
      planId.trim().isNotEmpty &&
      week > 1 &&
      !(_shown[planId]?.contains(week) ?? false);

  /// This ledger with [week] of [planId] recorded as shown.
  WeekUnlockLedger marked(String planId, int week) {
    if (!shouldShow(planId, week)) return this;
    return WeekUnlockLedger({
      ..._shown,
      planId: {...?_shown[planId], week},
    });
  }

  /// The weeks shown for [planId], ascending.
  List<int> shownFor(String planId) =>
      (_shown[planId]?.toList() ?? <int>[])..sort();

  bool get isEmpty => _shown.isEmpty;

  /// `{planId: [weeks…]}`.
  Map<String, List<int>> toJson() => {
    for (final e in _shown.entries) e.key: (e.value.toList()..sort()),
  };

  /// A stored ledger; anything that isn't `{planId: [int…]}` is skipped.
  static WeekUnlockLedger parse(Object raw) {
    if (raw is! Map) throw const FormatException('not a map');
    final out = <String, Set<int>>{};
    for (final e in raw.entries) {
      final weeks = e.value;
      if (weeks is! List) continue;
      final set = {
        for (final w in weeks)
          if (w is num && w.toInt() > 1) w.toInt(),
      };
      if (set.isNotEmpty) out[e.key.toString()] = set;
    }
    return WeekUnlockLedger(out);
  }

  @override
  bool operator ==(Object other) =>
      other is WeekUnlockLedger &&
      mapEquals(
        toJson().map((k, v) => MapEntry(k, v.join(','))),
        other.toJson().map((k, v) => MapEntry(k, v.join(','))),
      );

  @override
  int get hashCode => Object.hashAllUnordered(
    toJson().entries.map((e) => Object.hash(e.key, e.value.join(','))),
  );
}
