// CMPYS "Your record" (`v3/compare.jsx` RecordScreen): the learner's wins and
// the mentor's documented milestones side by side, by age. "Log a win" (the
// shared WinSheet in record mode), the dimension filter, the on-device
// reassess, the entry sheet and the milestone claim sheet.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/narration_dock_page.dart';
import '../../../core/ui/v3/v3.dart';
import '../../plan/data/plan_repository.dart';
import '../../session/data/session_repository.dart';
import '../../session/models/session_models.dart';
import '../data/cmpys_record_data.dart';
import '../data/cmpys_seed.dart';
import '../data/reported_win.dart';
import '../state/cmpys_store.dart';
import 'onboarding/mentor_image.dart';

export '../data/reported_win.dart' show recordDimForCategory;

// ─────────────────────────────────────────────────────────────────────────────
// Timeline data
// ─────────────────────────────────────────────────────────────────────────────

/// The filter value that shows every entry ("All").
const recordAllFilter = 'all';

/// One card on the dual timeline: a win of yours (left) or one of the
/// mentor's milestones (right).
@immutable
class RecordEntry {
  const RecordEntry({
    required this.id,
    required this.mine,
    required this.title,
    this.age,
    this.dim,
    this.source = '',
    this.note = '',
    this.idolNote,
    this.local = false,
    this.serverId,
    this.milestoneId,
    this.claimed = false,
  });

  final String id;

  /// Yours (a record win) or the mentor's.
  final bool mine;
  final String title;

  /// Null for an entry with no known age, shown under "Undated".
  final int? age;

  /// The v3 dimension id ([recordDimId]); null for the mentor's events,
  /// which carry no dimension.
  final String? dim;

  /// The win's source as the store records it (empty for the mentor).
  final String source;
  final String note;
  final String? idolNote;

  /// A local entry can be deleted here ([recordWinIsLocal]).
  final bool local;

  /// The server achievement id of a synced win: deleting the entry deletes
  /// that achievement first.
  final String? serverId;

  /// "Delete entry" shows: a local entry, or a synced win whose server copy
  /// can be deleted too (older synced wins have no [serverId]).
  bool get deletable => mine && (local || serverId != null);

  /// The comparison milestone id when this is a claimable mentor milestone.
  final String? milestoneId;
  final bool claimed;

  bool get claimable => milestoneId != null && !claimed;
}

const _stopwords = {
  'a',
  'an',
  'and',
  'as',
  'at',
  'be',
  'been',
  'but',
  'by',
  'for',
  'from',
  'had',
  'has',
  'have',
  'he',
  'her',
  'hers',
  'him',
  'his',
  'in',
  'into',
  'is',
  'it',
  'its',
  'of',
  'on',
  'or',
  'she',
  'that',
  'the',
  'their',
  'them',
  'they',
  'this',
  'to',
  'was',
  'were',
  'which',
  'who',
  'with',
};

String _stem(String w) {
  if (w.length > 5 && w.endsWith('ing')) return w.substring(0, w.length - 3);
  if (w.length > 4 && w.endsWith('ed')) return w.substring(0, w.length - 2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

/// The normalised tokens of an event's text: lower case, split on anything
/// but letters and digits, stopwords and one-letter tokens dropped, and a
/// naive stem (`-ing`, `-ed`, `-s`).
Set<String> recordTokens(String text) => {
  for (final w
      in text
          .toLowerCase()
          .replaceAll(RegExp('[’\']s\\b'), '')
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
    if (w.length > 1 && !_stopwords.contains(w)) _stem(w),
};

/// Whether a comparison milestone and a mentor timeline event describe the
/// same thing: the same known age, and a token Jaccard similarity of at
/// least 0.5 ([recordTokens]).
bool recordSameEvent(String a, int? ageA, String b, int? ageB) {
  if (ageA == null || ageB == null || ageA != ageB) return false;
  final x = recordTokens(a);
  final y = recordTokens(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x.intersection(y).length / x.union(y).length >= 0.5;
}

/// The Record's entries for [filter] (a v3 dimension id, or
/// [recordAllFilter]), sorted by age with the undated ones last, and your
/// entries before the mentor's at each age.
///
/// - Your side is every record win. A win stored at age 0 has no age and
///   goes under "Undated"; it is never placed at age 0 or moved to the
///   current age.
/// - The mentor's side:
///   - the session's comparison milestones ([CmpysState.liveMilestones]) at
///     their `hit_by_age`, which can be claimed. They are on the device, so
///     they always show, even while the documented events load.
///   - the documented events, unless [eventsLoading]: [mentorTimeline], the
///     catalog's events (up to your age), each under the dimension of its
///     category ([recordDimForCategory]); when it is empty (none, failed,
///     timed out, or a mentor outside the catalog), the seeded ledger
///     [cmpysIdolLedgers] instead, with no dimension.
///   - A milestone that matches an event ([recordSameEvent]) always stays
///     and the event is dropped; the milestone takes the event's dimension.
List<RecordEntry> recordTimeline(
  CmpysState st, {
  String filter = recordAllFilter,
  List<IdolTimelineEntry> mentorTimeline = const [],
  bool eventsLoading = false,
}) {
  final userAge = st.user.age;
  bool upToYou(int age) => userAge <= 0 || age <= userAge;
  final idol = st.idol;

  // The mentor's documented events: the catalog's, else the seeded ledger.
  final catalog = [
    for (final (i, e) in mentorTimeline.indexed)
      if (upToYou(e.age))
        (
          id: 'timeline-${e.id ?? i}',
          age: e.age > 0 ? e.age : null,
          text: e.text,
          dim: recordDimForCategory(e.category),
        ),
  ];
  final ledger = [
    for (final (i, e)
        in (cmpysIdolLedgers[idol.id] ?? const <LedgerEntry>[]).indexed)
      if (upToYou(e.age))
        (
          id: 'ledger-${idol.id}-$i',
          age: e.age > 0 ? e.age : null,
          text: e.text,
          dim: null as String?,
        ),
  ];
  final events = mentorTimeline.isNotEmpty ? catalog : ledger;
  // Only the documented events wait for the fetch.
  if (eventsLoading) events.clear();
  final milestones = st.liveMilestones();
  final dropped = <int>{};
  final milestoneDim = <String, String?>{};
  for (final m in milestones) {
    for (final (i, e) in events.indexed) {
      if (dropped.contains(i)) continue;
      if (recordSameEvent(m.label, m.age, e.text, e.age)) {
        dropped.add(i);
        milestoneDim[m.id] = e.dim;
        break;
      }
    }
  }

  final all = <RecordEntry>[
    for (final w in st.achievements)
      RecordEntry(
        id: w.id,
        mine: true,
        title: w.source == 'milestone' ? 'Claimed: ${w.title}' : w.title,
        age: w.age > 0 ? w.age : null,
        dim: recordDimId(w.dim),
        source: w.source,
        note: w.note,
        idolNote: w.idolNote,
        local: recordWinIsLocal(w),
        serverId: w.synced ? w.serverId : null,
      ),
    for (final (i, e) in events.indexed)
      if (!dropped.contains(i))
        RecordEntry(
          id: e.id,
          mine: false,
          title: e.text,
          age: e.age,
          dim: e.dim,
        ),
    for (final m in milestones)
      RecordEntry(
        id: 'milestone-${m.id}',
        mine: false,
        title: m.label,
        age: m.age,
        dim: milestoneDim[m.id],
        milestoneId: m.id,
        claimed: st.milestones[m.id] == true,
      ),
  ];
  final shown = [
    for (final (i, e) in all.indexed)
      if (filter == recordAllFilter || e.dim == filter) (i, e),
  ];
  const undated = 1 << 30;
  shown.sort((a, b) {
    final byAge = (a.$2.age ?? undated).compareTo(b.$2.age ?? undated);
    if (byAge != 0) return byAge;
    if (a.$2.mine != b.$2.mine) return a.$2.mine ? -1 : 1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, e) in shown) e];
}

/// The entry sheet's source line, verbatim from the design.
String recordSourceCopy(RecordEntry e) {
  if (!e.mine) return 'Source: documented biography';
  if (e.source == 'auto') return 'Recorded from plan completion';
  // A synced or restored win lives on the account, not only this device.
  if (e.serverId != null) return 'Saved to your record';
  return 'Saved on this device · not verified';
}

/// What a screen reader hears for a timeline card: its side, its age, the
/// title, then its dimension and "Claimed." when they apply.
String recordEntryLabel(RecordEntry e, String mentorShort) {
  final owner = e.mine ? 'Your win' : '$mentorShort’s milestone';
  final when = e.age == null ? 'undated' : 'age ${e.age}';
  final title = e.title.trim();
  final parts = [
    '$owner, $when: ${RegExp(r'[.!?…]$').hasMatch(title) ? title : '$title.'}',
    if (e.dim != null) '${winDimOf(e.dim!).label}.',
    if (e.claimed) 'Claimed.',
  ];
  return parts.join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// Record screen
// ─────────────────────────────────────────────────────────────────────────────

class CmpysRecordScreen extends ConsumerStatefulWidget {
  const CmpysRecordScreen({super.key});

  /// The "n new entries waiting" banner.
  static const bannerKey = ValueKey('record-reassess-banner');

  @override
  ConsumerState<CmpysRecordScreen> createState() => _CmpysRecordScreenState();
}

enum _EntryAction { claim, delete }

class _CmpysRecordScreenState extends ConsumerState<CmpysRecordScreen> {
  String _filter = recordAllFilter;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(cmpysStoreProvider);
    final idol = st.idol;
    // The placeholder mentor (no mentor picked yet) has no catalog timeline.
    final timeline =
        idol.id == cmpysPlaceholderIdol.id || idol.name.trim().isEmpty
        ? null
        : ref.watch(idolTimelineProvider(idol.name));
    // Only the first load waits: a refresh (an invalidate from the Mentor
    // screen's "Try again") keeps the current result until the new one lands.
    final eventsLoading =
        timeline != null && !timeline.hasValue && !timeline.hasError;
    final entries = recordTimeline(
      st,
      filter: _filter,
      // A failed or timed-out fetch falls back to the seeded ledger, like
      // an empty one.
      mentorTimeline: timeline?.valueOrNull ?? const [],
      eventsLoading: eventsLoading,
    );
    final pending = st.pendingWins().length;

    return NarrationDockPage(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: Column(
          children: [
            V3TopBar(
              onBack: () => Navigator.of(context).maybePop(),
              right: V3Button(
                kind: V3ButtonKind.dark,
                size: V3Size.sm,
                icon: V3Icons.plus,
                onPressed: _logWin,
                child: const Text('Log a win'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: AppShell.bottomNavClearance(context, extra: 12),
                ),
                children: [
                  _heading(),
                  _chips(),
                  _legend(st.idol),
                  if (pending > 0) _banner(pending),
                  // While the documented events load, an empty record shows
                  // the loading row rather than "Nothing here yet".
                  if (entries.isEmpty && !eventsLoading)
                    _empty()
                  else
                    _RecordTimeline(
                      entries: entries,
                      userAge: st.user.age,
                      mentorShort: idol.short,
                      eventsLoading: eventsLoading,
                      onOpen: _openEntry,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V3Rise(child: Text('YOUR RECORD', style: AppTypography.kick)),
          const SizedBox(height: 8),
          V3Rise(
            delay: const Duration(milliseconds: 50),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Wins and milestones,\n'),
                  TextSpan(
                    text: 'by age.',
                    style: AppTypography.displayItalic(40),
                  ),
                ],
              ),
              style: AppTypography.display(40).copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    return V3Rise(
      delay: const Duration(milliseconds: 100),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(
          children: [
            V3Chip(
              on: _filter == recordAllFilter,
              onPressed: () => setState(() => _filter = recordAllFilter),
              child: const Text('All'),
            ),
            for (final d in winDims) ...[
              const SizedBox(width: 6),
              V3Chip(
                on: _filter == d.id,
                onPressed: () => setState(() => _filter = d.id),
                child: Text(d.label),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legend(CmpysIdol idol) {
    Widget key(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTypography.sans(
              12,
              FontWeight.w600,
            ).copyWith(color: AppColors.ink2),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          key(AppColors.ember, 'You'),
          key(AppColors.iris, idol.short),
        ],
      ),
    );
  }

  Widget _banner(int pending) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: V3Pressable(
        key: CmpysRecordScreen.bannerKey,
        onTap: _reassess,
        focusRadius: AppRadii.brR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.goldSoft,
            borderRadius: AppRadii.brR,
          ),
          child: Row(
            children: [
              const V3Icon(V3Icons.refresh, size: 17, color: AppColors.gold2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$pending new ${pending == 1 ? 'entry' : 'entries'} '
                  'waiting. Reassess on this device',
                  style: AppTypography.sans(
                    13.5,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.gold2),
                ),
              ),
              const SizedBox(width: 10),
              const V3Icon(V3Icons.right, size: 15, color: AppColors.gold2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: v3Card(),
        child: Column(
          children: [
            const V3Icon(V3Icons.trophy, size: 24, color: AppColors.ink3),
            const SizedBox(height: 10),
            Text(
              'Nothing here yet',
              textAlign: TextAlign.center,
              style: AppTypography.display(24).copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Log a win and it shows here, by age.',
              textAlign: TextAlign.center,
              style: AppTypography.sans(14).copyWith(color: AppColors.ink2),
            ),
          ],
        ),
      ),
    );
  }

  // ── actions ──

  Future<void> _logWin() async {
    final st = ref.read(cmpysStoreProvider);
    final idol = st.idol;
    final win = await showWinSheet(
      context,
      mode: WinSheetMode.record,
      mentorShort: idol.short,
      mentorImage: cmpysIdolImage(idol),
      mentorInitials: idol.initials,
      mentorTint: idol.tint,
      age: st.user.age,
      onSave: (w) async {
        await saveReportedWin(ref, w, source: 'manual');
      },
    );
    if (win == null || !mounted) return;
    showV3Toast(context, 'Added to your record', icon: V3Icons.trophy);
  }

  Future<void> _openEntry(RecordEntry entry) async {
    final idol = ref.read(cmpysStoreProvider).idol;
    final action = await showV3Sheet<_EntryAction>(
      context,
      builder: (sheetContext) => _EntrySheet(entry: entry, idol: idol),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _EntryAction.claim:
        await _openClaim(entry);
      case _EntryAction.delete:
        await _delete(entry);
    }
  }

  /// Deletes a local entry, or a synced win's server achievement and then
  /// the entry. A failed server delete keeps the entry, except a 404 (already
  /// gone), which counts as deleted.
  Future<void> _delete(RecordEntry entry) async {
    if (!entry.deletable) return;
    final store = ref.read(cmpysStoreProvider.notifier);
    final serverId = entry.local ? null : entry.serverId;
    if (serverId != null) {
      try {
        await ref.read(planRepositoryProvider).deleteAchievement(serverId);
      } on ApiError catch (error) {
        // 404: the server copy is already gone, so removing the entry is the
        // outcome the learner asked for.
        if (error.statusCode != 404) {
          _showDeleteFailed();
          return;
        }
      } catch (_) {
        _showDeleteFailed();
        return;
      }
    }
    store.deleteWin(entry.id);
    if (!mounted) return;
    showV3Toast(context, 'Entry removed', icon: V3Icons.trash);
  }

  void _showDeleteFailed() {
    if (!mounted) return;
    showV3Toast(
      context,
      'Couldn’t delete this entry. Try again.',
      icon: V3Icons.alert,
      tone: V3ToastTone.warn,
    );
  }

  Future<void> _openClaim(RecordEntry entry) async {
    final id = entry.milestoneId;
    if (id == null) return;
    final claimed = await showV3Sheet<bool>(
      context,
      title: 'Claim milestone',
      builder: (_) => ClaimSheet(
        milestoneId: id,
        label: entry.title,
        age: entry.age,
        dim: entry.dim,
      ),
    );
    if (claimed != true || !mounted) return;
    showV3Toast(context, 'Milestone claimed', icon: V3Icons.flag);
  }

  /// True while the reassess overlay is open, so a double tap on the
  /// banner can't push a second one.
  bool _reassessing = false;

  Future<void> _reassess() async {
    if (_reassessing) return;
    _reassessing = true;
    final motion = MotionConfig.enabled(context);
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: null,
        transitionDuration: motion
            ? const Duration(milliseconds: 300)
            : Duration.zero,
        reverseTransitionDuration: motion
            ? const Duration(milliseconds: 220)
            : Duration.zero,
        pageBuilder: (_, _, _) => const ReassessOverlay(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    _reassessing = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dual timeline
// ─────────────────────────────────────────────────────────────────────────────

class _RecordTimeline extends StatelessWidget {
  const _RecordTimeline({
    required this.entries,
    required this.userAge,
    required this.mentorShort,
    required this.onOpen,
    this.eventsLoading = false,
  });

  final List<RecordEntry> entries;
  final int userAge;
  final String mentorShort;
  final ValueChanged<RecordEntry> onOpen;

  /// The mentor's documented events are still loading: a skeleton card on
  /// the mentor's side stands in for them.
  final bool eventsLoading;

  static const loadingKey = ValueKey('record-events-loading');

  /// Below this width, or at this text scale and above, the two columns
  /// would leave cards too narrow: the timeline becomes a single column.
  static const singleColumnWidth = 360.0;
  static const singleColumnTextScale = 1.5;

  static Duration _rise(int ms) => Duration(milliseconds: math.min(ms, 700));

  @override
  Widget build(BuildContext context) {
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) >= singleColumnTextScale;
    // Entries arrive sorted, so the groups keep age order, undated last.
    final groups = <int?, List<RecordEntry>>{};
    for (final e in entries) {
      (groups[e.age] ??= []).add(e);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // The screen width less the 20 pt gutters, from the layout itself.
          final single = largeText || width + 40 < singleColumnWidth;
          final cardWidth = math.max(0.0, width / 2 - 14);
          return Stack(
            children: [
              if (!single)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: width / 2 - 1,
                  width: 2,
                  child: const ColoredBox(color: AppColors.hair),
                ),
              Column(
                children: [
                  for (final (ai, group) in groups.entries.indexed)
                    Semantics(
                      key: ValueKey('record-group-${group.key ?? 'undated'}'),
                      container: true,
                      explicitChildNodes: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          children: [
                            V3Rise(
                              delay: _rise(ai * 70),
                              child: Center(child: _agePill(group.key)),
                            ),
                            const SizedBox(height: 10),
                            for (final (k, e) in group.value.indexed)
                              Padding(
                                key: ValueKey('record-row-${e.id}'),
                                // One column: each side keeps a 24 pt
                                // offset, yours from the right and the
                                // mentor's from the left.
                                padding: EdgeInsets.only(
                                  bottom: 8,
                                  left: single && !e.mine ? 24 : 0,
                                  right: single && e.mine ? 24 : 0,
                                ),
                                child: V3Rise(
                                  delay: _rise(ai * 70 + k * 50 + 40),
                                  child: Align(
                                    alignment: e.mine
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                    child: SizedBox(
                                      width: single
                                          ? double.infinity
                                          : cardWidth,
                                      child: _EntryCard(
                                        entry: e,
                                        mentorShort: mentorShort,
                                        showOwner: single,
                                        onTap: () => onOpen(e),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (eventsLoading)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: 14,
                        left: single ? 24 : 0,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: single ? double.infinity : cardWidth,
                          child: _loadingCard(),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// A skeleton card on the mentor's side while the documented events load.
  Widget _loadingCard() {
    return Semantics(
      key: loadingKey,
      label: 'Loading',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: v3Card(radius: 18),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              V3Skel(height: 12),
              SizedBox(height: 8),
              V3Skel(width: 72, height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agePill(int? age) {
    final now = age != null && userAge > 0 && age == userAge;
    final label = age == null
        ? 'Undated'
        : now
        ? 'Age $age, your age now'
        : 'Age $age';
    return Semantics(
      header: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('record-age-${age ?? 'undated'}'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: now ? AppColors.ink : AppColors.paper2,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            age == null ? 'Undated' : 'Age $age',
            style: AppTypography.sans(12, FontWeight.w700)
                .merge(AppTypography.tnum)
                .copyWith(color: now ? Colors.white : AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.mentorShort,
    required this.onTap,
    this.showOwner = false,
  });

  final RecordEntry entry;
  final String mentorShort;
  final VoidCallback onTap;

  /// In the single-column layout the card names its side ("You" or the
  /// mentor) above the title, since left and right no longer say it.
  final bool showOwner;

  static const _radius = BorderRadius.all(Radius.circular(18));

  /// A tag never wraps: in a narrow card or at large text it scales down.
  static Widget _fit(Widget tag) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: tag,
  );

  @override
  Widget build(BuildContext context) {
    final dim = entry.dim == null ? null : winDimOf(entry.dim!);
    return V3Pressable(
      key: ValueKey('record-entry-${entry.id}'),
      onTap: onTap,
      focusRadius: _radius,
      semanticLabel: recordEntryLabel(entry, mentorShort),
      child: ClipRRect(
        borderRadius: _radius,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: _radius,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppColors.hair),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showOwner) ...[
                    Text(
                      entry.mine ? 'You' : mentorShort,
                      key: const ValueKey('record-entry-owner'),
                      style: AppTypography.sans(11, FontWeight.w700).copyWith(
                        color: entry.mine ? AppColors.ember2 : AppColors.iris2,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    entry.title,
                    style: AppTypography.sans(
                      13.5,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink, height: 1.35),
                  ),
                  if (dim != null || entry.claimed) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (dim != null)
                          _fit(
                            V3Tag(
                              height: 20,
                              fontSize: 10.5,
                              color: dim.deep,
                              background: dim.tint,
                              child: Text(dim.label),
                            ),
                          ),
                        if (entry.claimed)
                          _fit(
                            const V3Tag(
                              height: 20,
                              fontSize: 10.5,
                              color: AppColors.sage2,
                              background: AppColors.sageSoft,
                              child: Text('Claimed'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // The design's 3 px top border: ember for you, iris for the
            // mentor, curved by the card's corners.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3,
              child: ColoredBox(
                color: entry.mine ? AppColors.ember : AppColors.iris,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EntrySheet extends StatelessWidget {
  const _EntrySheet({required this.entry, required this.idol});

  final RecordEntry entry;
  final CmpysIdol idol;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final who = e.mine ? 'Your win' : '${idol.short}’s milestone';
    final idolNote = e.idolNote?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A long mentor name or large text scales the tag down rather than
        // overflowing it (a tag never wraps).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: V3Tag(
            color: e.mine ? AppColors.ember2 : AppColors.iris2,
            background: e.mine ? AppColors.emberSoft : AppColors.irisSoft,
            child: Text(e.age == null ? who : '$who · Age ${e.age}'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          e.title,
          style: AppTypography.sans(21, FontWeight.w600).copyWith(
            color: AppColors.ink,
            letterSpacing: -0.015 * 21,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          recordSourceCopy(e),
          style: AppTypography.sans(13).copyWith(color: AppColors.ink3),
        ),
        if (e.note.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            e.note,
            style: AppTypography.sans(
              14.5,
            ).copyWith(color: AppColors.ink, height: 1.5),
          ),
        ],
        if (e.mine && idolNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V3Avatar(
                  image: cmpysIdolImage(idol),
                  initials: idol.initials,
                  name: idol.name,
                  tint: idol.tint,
                  size: 30,
                  gray: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    idolNote,
                    style: AppTypography.read(
                      14.5,
                    ).copyWith(color: AppColors.ink, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (e.claimable) ...[
          const SizedBox(height: 18),
          V3Button(
            kind: V3ButtonKind.dark,
            icon: V3Icons.flag,
            full: true,
            onPressed: () => Navigator.of(context).pop(_EntryAction.claim),
            child: const Text('Claim a similar milestone'),
          ),
        ],
        if (e.deletable) ...[
          const SizedBox(height: 10),
          V3Button(
            kind: V3ButtonKind.ghost,
            full: true,
            semanticLabel: 'Delete entry',
            onPressed: () => Navigator.of(context).pop(_EntryAction.delete),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                V3Icon(V3Icons.trash, size: 18, color: AppColors.danger),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Delete entry',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Claim sheet
// ─────────────────────────────────────────────────────────────────────────────

/// "Claim milestone": a statement of what you did that's comparable to one
/// of the mentor's comparison milestones. "Claim" stays disabled until the
/// trimmed statement has [minLength] characters; the claim is saved with the
/// store's `claimMilestone` at your current age and pops `true`.
class ClaimSheet extends ConsumerStatefulWidget {
  const ClaimSheet({
    super.key,
    required this.milestoneId,
    required this.label,
    this.age,
    this.dim,
  });

  final String milestoneId;
  final String label;

  /// The mentor's age at the milestone; null drops "at N".
  final int? age;

  /// The milestone's own v3 dimension (from its matched timeline event);
  /// null files the claim by the milestone's position.
  final String? dim;

  static const minLength = 10;

  @override
  ConsumerState<ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<ClaimSheet> {
  final _statement = TextEditingController();

  bool get _ready => _statement.text.trim().length >= ClaimSheet.minLength;

  @override
  void dispose() {
    _statement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.age == null ? '' : ' at ${widget.age}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '“${widget.label}”$at. Explain what you did that’s comparable.',
          style: AppTypography.sans(
            14.5,
          ).copyWith(color: AppColors.ink2, height: 1.5),
        ),
        const SizedBox(height: 14),
        V3Field(
          controller: _statement,
          multiline: true,
          rows: 3,
          placeholder: 'Your statement',
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        V3Button(
          full: true,
          disabled: !_ready,
          onPressed: _claim,
          child: const Text('Claim'),
        ),
      ],
    );
  }

  void _claim() {
    if (!_ready) return;
    ref
        .read(cmpysStoreProvider.notifier)
        .claimMilestone(
          widget.milestoneId,
          widget.label,
          age: ref.read(cmpysStoreProvider).user.age,
          note: _statement.text.trim(),
          dim: widget.dim,
        );
    Navigator.of(context).pop(true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reassess overlay
// ─────────────────────────────────────────────────────────────────────────────

/// The on-device reassess: "Reviewing your new entries" for
/// [reviewDuration], then the entries are marked reviewed (the store's
/// `reassess`) and "Entries reviewed" says so. It changes this device's
/// record only, never the comparison scores.
class ReassessOverlay extends ConsumerStatefulWidget {
  const ReassessOverlay({super.key});

  static const reviewDuration = Duration(milliseconds: 2200);

  @override
  ConsumerState<ReassessOverlay> createState() => _ReassessOverlayState();
}

class _ReassessOverlayState extends ConsumerState<ReassessOverlay> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(ReassessOverlay.reviewDuration, _finish);
  }

  void _finish() {
    // Backed out (the route is popping): the review never finished.
    if (!mounted || ModalRoute.of(context)?.isActive == false) return;
    ref.read(cmpysStoreProvider.notifier).reassess();
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = AppTypography.sans(
      17,
      FontWeight.w600,
    ).copyWith(color: AppColors.ink);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: const ColoredBox(color: Color(0xB30E0C14)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: V3Pop(
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppRadii.brR2,
                    ),
                    child: _done
                        ? Semantics(
                            liveRegion: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: const BoxDecoration(
                                    color: AppColors.sageSoft,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const V3Icon(
                                    V3Icons.check,
                                    size: 26,
                                    strokeWidth: 2.6,
                                    color: AppColors.sage2,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Entries reviewed',
                                  textAlign: TextAlign.center,
                                  style: title,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Updated on this device only. This isn’t a '
                                  'new assessment of your comparison scores.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.sans(13.5).copyWith(
                                    color: AppColors.ink2,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                V3Button(
                                  kind: V3ButtonKind.dark,
                                  full: true,
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  child: const Text('Done'),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const V3Spinner(size: 34, color: AppColors.gold2),
                              const SizedBox(height: 14),
                              Text(
                                'Reviewing your new entries',
                                textAlign: TextAlign.center,
                                style: title,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
