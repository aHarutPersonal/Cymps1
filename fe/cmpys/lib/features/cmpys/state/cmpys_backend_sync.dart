// Hydrates the local CMPYS store from the backend's latest session — the
// source of truth for the chosen mentor and the AI-generated comparison /
// blueprint. Watched once per app run from the Today tab; repairs any drift
// (interrupted onboarding, reinstall, multi-device).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/data/session_repository.dart';
import 'cmpys_store.dart';

final cmpysBackendSyncProvider = FutureProvider<void>((ref) async {
  try {
    final repo = ref.read(sessionRepositoryProvider);
    var session = await repo.getLatestSession();
    if (session != null) {
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
    }

    // Fetching a completed session with a prose verdict but no structured
    // scores asks the backend to enqueue its idempotent backfill. Poll briefly
    // so the Compare screen replaces its honest pending state automatically
    // once those generated numbers land.
    for (
      var attempt = 0;
      attempt < 20 &&
          session?.comparisonOutput?.trim().isNotEmpty == true &&
          session?.comparisonScores == null;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(seconds: 3));
      session = await repo.getLatestSession();
      if (session == null) break;
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
    }
  } catch (_) {
    // Best-effort: offline keeps whatever the store last persisted.
  }
});
