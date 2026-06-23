import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/models/session_models.dart';
import '../../session/controllers/session_controller.dart';

/// Derived provider exposing the currently selected idol from the active session.
///
/// Returns null if no session is active or no idol has been selected yet.
final activeIdolProvider = Provider<SelectedIdolInfo?>((ref) {
  final state = ref.watch(sessionControllerProvider);
  if (state is SessionActive) return state.session.selectedIdol;
  if (state is SessionCompleted) return state.session.selectedIdol;
  return null;
});
