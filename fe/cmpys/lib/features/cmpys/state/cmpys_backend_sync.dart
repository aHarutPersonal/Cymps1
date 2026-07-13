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
    await ref.read(cmpysStoreProvider.notifier).ready;
    final repo = ref.read(sessionRepositoryProvider);
    final session = await repo.getLatestSession();
    if (session != null) {
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
    }
  } catch (_) {
    // Best-effort: offline keeps whatever the store last persisted.
  }
});

enum ComparisonScoresSyncResult { ready, unavailable, timedOut }

/// Structured comparison scores matter only on Compare. Keeping their retry
/// loop scoped there prevents every Plan/detail screen from issuing unrelated
/// `/sessions/latest` requests. Auto-dispose plus the flag below also prevents
/// an invalidated provider's delayed loop from overlapping its replacement.
final cmpysComparisonScoresSyncProvider =
    FutureProvider.autoDispose<ComparisonScoresSyncResult>((ref) async {
  var disposed = false;
  Timer? retryTimer;
  Completer<void>? retryDelay;
  ref.onDispose(() {
    disposed = true;
    retryTimer?.cancel();
    final delay = retryDelay;
    if (delay != null && !delay.isCompleted) {
      delay.complete();
    }
  });

  await ref.read(cmpysStoreProvider.notifier).ready;
  await ref.watch(cmpysBackendSyncProvider.future);
  var state = ref.read(cmpysStoreProvider);
  if (state.liveDims().isNotEmpty) {
    return ComparisonScoresSyncResult.ready;
  }
  if (state.comparisonMd?.trim().isNotEmpty != true) {
    return ComparisonScoresSyncResult.unavailable;
  }

  final repo = ref.read(sessionRepositoryProvider);
  // Check immediately on entry/retry, then poll for at most one minute. A
  // terminal result lets the UI replace its spinner with an explicit retry.
  for (var attempt = 0; attempt < 12; attempt++) {
    if (attempt > 0) {
      final delay = Completer<void>();
      retryDelay = delay;
      retryTimer = Timer(
        const Duration(seconds: 5),
        () {
          if (!delay.isCompleted) delay.complete();
        },
      );
      await delay.future;
      retryTimer = null;
      retryDelay = null;
      if (disposed) return ComparisonScoresSyncResult.unavailable;
    }

    final session = await repo.getLatestSession();
    if (disposed) return ComparisonScoresSyncResult.unavailable;
    if (session == null) return ComparisonScoresSyncResult.unavailable;
    ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
    state = ref.read(cmpysStoreProvider);
    if (state.liveDims().isNotEmpty) {
      return ComparisonScoresSyncResult.ready;
    }
    if (state.comparisonMd?.trim().isNotEmpty != true) {
      return ComparisonScoresSyncResult.unavailable;
    }
  }

  return ComparisonScoresSyncResult.timedOut;
});
