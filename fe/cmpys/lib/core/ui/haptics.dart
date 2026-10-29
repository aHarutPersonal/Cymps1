// The one way the app plays a haptic: it honours the learner's "Sound &
// haptics" setting (You → Settings, [CmpysSettings.haptics]).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/cmpys/state/cmpys_store.dart';

/// The haptics the app plays.
enum AppHaptic {
  /// A light tick for a selection (a tab, a menu pick, a seek).
  selection,

  /// A light tap for a confirmed action (a like).
  light,
}

/// Whether haptics are on for this device. Outside a [ProviderScope] (some
/// widget tests) the setting's default, on, applies.
bool hapticsEnabled(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(cmpysStoreProvider).settings.haptics;
  } catch (_) {
    return true;
  }
}

/// Plays [kind] unless the learner switched "Sound & haptics" off.
void playHaptic(BuildContext context, AppHaptic kind) {
  if (!hapticsEnabled(context)) return;
  switch (kind) {
    case AppHaptic.selection:
      HapticFeedback.selectionClick();
    case AppHaptic.light:
      HapticFeedback.lightImpact();
  }
}
