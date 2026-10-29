import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/v3/win_sheet.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/state/current_plan_provider.dart';
import '../state/cmpys_store.dart';

/// The server's achievement category for each v3 dimension of a reported
/// win (`AchievementCategory`: career, learning, finance, impact, mindset,
/// other).
const reportedWinCategory = <String, String>{
  'knowledge': 'learning',
  'practice': 'impact',
  'capital': 'finance',
  'network': 'career',
  'judgment': 'mindset',
};

/// The v3 dimension for a server achievement category: the inverse of
/// [reportedWinCategory] (learning → knowledge, impact → practice, finance →
/// capital, career → network, mindset → judgment). `other`, an unknown or a
/// missing category has no dimension.
String? recordDimForCategory(String? category) {
  final c = category?.trim().toLowerCase();
  if (c == null || c.isEmpty) return null;
  for (final e in reportedWinCategory.entries) {
    if (e.value == c) return e.key;
  }
  return null;
}

/// Saves a win from the [WinSheet] the way the tutorial achievement is saved:
/// a `manual` achievement with this plan and cycle (no
/// `planItemId`, so it never overwrites a mission's achievement), with the
/// evidence as its notes and link, then the win on the record on this device
/// (unassessed: a reported win isn't a verified achievement).
///
/// The device win is marked `synced` with the server achievement's id
/// (`serverId`), so deleting it from the Record deletes the server copy
/// too, and is added even with no age (0): the Record shows it under
/// "Undated". Returns the record win's id. [source] is the record's
/// source marker: `chat` ("Told to your mentor") from the Mentor tab,
/// `manual` ("Logged by you") from the record.
Future<String> saveReportedWin(
  WidgetRef ref,
  V3Win win, {
  required String source,
}) async {
  final plan = ref.read(currentPlanProvider).plan;
  final serverId = await ref
      .read(planRepositoryProvider)
      .saveAchievement(
        title: win.text,
        category: reportedWinCategory[win.dim] ?? 'other',
        source: 'manual',
        planId: plan?.id,
        cycleNumber: plan?.cycleNumber ?? 1,
        notes: win.note.isEmpty ? null : win.note,
        evidenceLink: win.link.isEmpty ? null : win.link,
      );
  final age = ref.read(cmpysStoreProvider).user.age;
  return ref
      .read(cmpysStoreProvider.notifier)
      .addWin(
        title: win.text,
        dim: win.dim,
        age: age,
        impact: win.size,
        source: source,
        note: win.evidence,
        assessed: false,
        synced: true,
        serverId: serverId,
      );
}
