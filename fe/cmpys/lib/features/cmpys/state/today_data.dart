// Data and pure helpers behind the Today tab (`v3/today.jsx`).
//
// Providers fetch what the tab adds on top of `currentPlanProvider` and
// `todayViewProvider`: the /streak summary, the current mission's tutorials
// and materials, and the continue-reading book. The helpers are pure so the
// greeting, kicker, streak grid and access mapping are unit-testable.

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/v3/surfaces.dart' show AccessType;
import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/state/current_plan_provider.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';

/// GET /streak, once the plan is ready (the streak only means something with
/// habits to keep). Invalidate after a daily toggle.
final todayStreakProvider = FutureProvider<StreakSummary?>((ref) async {
  final ready = ref.watch(
    currentPlanProvider.select((s) => s.status == CurrentPlanStatus.ready),
  );
  if (!ready) return null;
  return ref.watch(planRepositoryProvider).getStreak();
});

/// The book the user last read (GET /content-resources/continue-reading).
/// A failed or stale resume entry hides the card rather than the shelf, as
/// in the reading library.
final todayContinueReadingProvider = FutureProvider<ContentResource?>((
  ref,
) async {
  try {
    final resource = await ref
        .watch(contentResourcesRepositoryProvider)
        .getContinueReading();
    return resource != null && resource.isBook ? resource : null;
  } catch (_) {
    return null;
  }
});

/// The current mission's tutorials and materials (GET
/// /plan-items/{id}/detailed), the source of the NextUp card and the
/// "For this week’s mission" shelf.
final todayMissionDetailProvider = FutureProvider.autoDispose
    .family<PlanItemDetailed, String>((ref, itemId) {
      return ref.watch(planRepositoryProvider).getPlanItemDetailed(itemId);
    });

/// "Good morning," for 5–11, "Good afternoon," for 12–17, else
/// "Good evening," (local hour).
String greetingForHour(int hour) {
  if (hour >= 5 && hour <= 11) return 'Good morning,';
  if (hour >= 12 && hour <= 17) return 'Good afternoon,';
  return 'Good evening,';
}

/// The date kicker, e.g. "SUNDAY · 26 OCTOBER", in [locale] when date
/// symbols for it are loaded, else in English.
String todayKicker(DateTime now, {String? locale}) {
  String format(String pattern) {
    try {
      return DateFormat(pattern, locale).format(now);
    } catch (_) {
      return DateFormat(pattern, 'en_US').format(now);
    }
  }

  return '${format('EEEE')} · ${format('d MMMM')}'.toUpperCase();
}

/// Day [day] of [total] since the plan was created (day 1 is the creation
/// day), or null when the plan has no creation date.
({int day, int total})? planDayOf(BackendPlan plan, DateTime now) {
  final created = plan.createdAt?.toLocal();
  if (created == null) return null;
  final weeks = plan.durationWeeks <= 0 ? 12 : plan.durationWeeks;
  final total = weeks * 7;
  // Calendar days in UTC so a daylight-saving change never loses a day.
  final start = DateTime.utc(created.year, created.month, created.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = today.difference(start).inDays + 1;
  return (day: day.clamp(1, total), total: total);
}

/// A habit's minutes for one session: the server's `session_minutes` (the
/// week's allocation over the rhythm's sessions per week). Servers that
/// predate it send only the week's allocation (`estimated_minutes`, else
/// whole hours); then about a seventh of it, at least one minute.
int habitSessionMinutes(TodayTaskItem item) {
  final session = item.sessionMinutes;
  if (session != null && session > 0) return session;
  return math.max(1, (item.weeklyMinutes / 7).round());
}

/// The Monday-to-Sunday grid for the week containing [today]: true for a day
/// inside the known streak run, false otherwise, and null for today itself
/// (the screen fills it from today's habits).
///
/// /streak has no per-day history, only the current run and the last active
/// day. The run ending on that day is shown as done; earlier days of the week
/// are not known and show as not done.
List<bool?> streakWeek(StreakSummary? streak, DateTime today) {
  final day = DateTime.utc(today.year, today.month, today.day);
  final monday = day.subtract(Duration(days: day.weekday - 1));
  final done = <DateTime>{};
  final last = streak?.lastActive;
  if (streak != null && last != null) {
    final end = DateTime.utc(last.year, last.month, last.day);
    final run = streak.current > 0 ? streak.current : 1;
    for (var i = 0; i < run && i < 7; i++) {
      done.add(end.subtract(Duration(days: i)));
    }
  }
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = monday.add(Duration(days: i));
        if (d == day) return null;
        if (d.isAfter(day)) return false;
        return done.contains(d);
      }(),
  ];
}

/// What CMPYS can show for a mission material (the design's `ACCESS` type):
/// the one mapping Today and the mission screen share. It follows the order
/// in which the mission screen opens a material, so a badge never promises
/// a viewer the CTA does not open:
///
/// - A YouTube link → [AccessType.video] (the in-app player). Any other
///   link, a `video` type included, is never "video".
/// - A book:
///   - with a guide resource ([resolvedGuideId], else `contentResourceId`)
///     → [AccessType.guide] (the CMPYS study guide);
///   - else with its own link → [AccessType.web];
///   - else what the mission screen resolved ([bookAccess]): a verified
///     source → [AccessType.excerpt] or [AccessType.original] by scope, a
///     ruled-out guide with no source → [AccessType.none];
///   - else an unresolved `canonicalKey` → [AccessType.guide] (opening it
///     prepares the guide); with no key → [AccessType.none].
/// - A course, tool or template link (no inline text) → [AccessType.web]:
///   legacy rows may carry a metadata-only resource id the link outranks.
/// - In-app content (inline markdown or idea cards, or a book/article/lesson
///   resource) → [AccessType.guide], opened in the in-app reader.
/// - Any other link → [AccessType.web]; nothing to open → [AccessType.none].
AccessType accessTypeForMaterial(
  PlanMaterialDetail material, {
  String? resolvedGuideId,
  BookReadingAccess? bookAccess,
}) {
  final url = material.directUrl;
  if (material.youtubeVideoId != null) return AccessType.video;
  if (material.type == 'book') {
    final guideId = (resolvedGuideId ?? material.contentResourceId)?.trim();
    if (guideId != null && guideId.isNotEmpty) return AccessType.guide;
    if (url != null) return AccessType.web;
    final source = bookAccess?.source;
    if (source != null) {
      return source.scope == 'excerpt'
          ? AccessType.excerpt
          : AccessType.original;
    }
    if (bookAccess?.unavailable != null) return AccessType.none;
    final key = material.canonicalKey?.trim();
    return key != null && key.isNotEmpty ? AccessType.guide : AccessType.none;
  }
  if (material.prefersExternalLink) return AccessType.web;
  if (material.hasInAppContent) return AccessType.guide;
  if (url != null) return AccessType.web;
  return AccessType.none;
}

/// How many comparison dimensions are like for like, out of how many. Only
/// the evidence-based score versions (2 and 3) count; older scores and
/// pending ones give null.
({int comparable, int total})? comparableDimensions(
  Map<String, dynamic>? scores,
) {
  final version = scores?['version'];
  if (version != 2 && version != 3) return null;
  final raw = scores?['dimensions'];
  if (raw is! List) return null;
  final dims = raw.whereType<Map>().toList();
  if (dims.isEmpty) return null;
  final comparable = dims.where((d) => d['status'] == 'comparable').length;
  return (comparable: comparable, total: dims.length);
}

/// The local-date key reflections are stored under (`yyyy-MM-dd`).
String reflectionDateKey(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-'
      '${two(now.day)}';
}
