// Hydrates the local CMPYS store from the backend's latest session — the
// source of truth for the chosen mentor and the AI-generated comparison /
// blueprint. Watched once per app run from the Today tab; repairs any drift
// (interrupted onboarding, reinstall, multi-device).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/data/session_repository.dart';
import 'cmpys_store.dart';

final cmpysBackendSyncProvider = FutureProvider<void>((ref) async {
  try {
    final repo = ref.read(sessionRepositoryProvider);
    final session = await repo.getLatestSession();
    if (session != null) {
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
    }
  } catch (_) {
    // Best-effort: offline keeps whatever the store last persisted.
  }
});

/// Structured comparison scores matter only on Compare. Keeping their retry
/// loop scoped there prevents every Plan/detail screen from issuing unrelated
/// `/sessions/latest` requests. Auto-dispose plus the flag below also prevents
/// an invalidated provider's delayed loop from overlapping its replacement.
final cmpysComparisonScoresSyncProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  var disposed = false;
  Timer? retryTimer;
  ref.onDispose(() {
    disposed = true;
    retryTimer?.cancel();
  });
  try {
    await ref.watch(cmpysBackendSyncProvider.future);
    var state = ref.read(cmpysStoreProvider);
    final hasComparison = state.comparisonMd?.trim().isNotEmpty == true;
    final hasScores = state.liveComparisonScores?.isNotEmpty == true;
    if (!hasComparison || hasScores) return;

    final repo = ref.read(sessionRepositoryProvider);
    // One minute total, but only 12 lightweight checks instead of 20. The
    // backend generation itself remains asynchronous and idempotent.
    for (var attempt = 0; attempt < 12; attempt++) {
      final delay = Completer<void>();
      retryTimer = Timer(const Duration(seconds: 5), () => delay.complete());
      await delay.future;
      retryTimer = null;
      if (disposed) return;
      final session = await repo.getLatestSession();
      if (disposed || session == null) return;
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
      state = ref.read(cmpysStoreProvider);
      if (state.liveComparisonScores?.isNotEmpty == true) return;
    }
  } catch (_) {
    // Best-effort: offline keeps whatever the store last persisted.
  }
});
