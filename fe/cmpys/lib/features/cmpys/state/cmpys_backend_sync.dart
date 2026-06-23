// Hydrates the local CMPYS store from the backend's latest session — the
// source of truth for the chosen mentor and the AI-generated comparison /
// blueprint. Watched once per app run from the Today tab; repairs any drift
// (interrupted onboarding, reinstall, multi-device).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/data/session_repository.dart';
import 'cmpys_store.dart';

final cmpysBackendSyncProvider = FutureProvider<void>((ref) async {
  try {
    final session =
        await ref.read(sessionRepositoryProvider).getLatestSession();
    if (session != null) {
      ref.read(cmpysStoreProvider.notifier).syncFromSession(session);
    }
  } catch (_) {
    // Best-effort: offline keeps whatever the store last persisted.
  }
});
