// The habit screen (`HabitScreen` in `v3/plan.jsx`): one daily habit with its
// focus timer, how-to, reflection and week. `PlanItemDetailScreen` shows it
// for a daily-rhythm item, which Today and the Plan tab both open.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/state/habit_toggle.dart';
import '../../cmpys/state/plan_providers.dart';
import '../../cmpys/state/today_data.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'backend_plan_widgets.dart' show PlanDashedCell;
import 'lesson_practice_screen.dart';

/// The reflection question. The server has no per-habit prompt, so every
/// habit asks the app's standing question.
const habitReflectionPrompt =
    'Which rule did you recall? What did you get wrong, and how will you distinguish it next time?';

/// The timer's glow: oklch(0.55 0.16 42 / .45).
const _emberGlow = Color(0x73BA480D);

const _letters = 'MTWTFSS';
const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A daily habit, built from its loaded [detailed] item.
///
/// - Checking it off goes through [HabitToggleMixin] when the habit is in
///   today's view (the same optimistic mark, toasts and day celebration as
///   Today and Plan), and straight through the daily-toggle API otherwise.
///   Either way [onReload] re-reads the item afterwards.
/// - The reflection saves itself to the server 800 ms after typing stops.
/// - The focus timer counts down against the wall clock ([clock]), so a
///   phone that sleeps mid-session still shows the right time.
class HabitDetailView extends ConsumerStatefulWidget {
  const HabitDetailView({
    super.key,
    required this.detailed,
    required this.onReload,
    this.clock,
  });

  final PlanItemDetailed detailed;
  final Future<void> Function() onReload;
  final DateTime Function()? clock;

  @override
  ConsumerState<HabitDetailView> createState() => _HabitDetailViewState();
}

enum _NoteState { idle, saving, saved, failed }

class _HabitDetailViewState extends ConsumerState<HabitDetailView>
    with HabitToggleMixin<HabitDetailView>, TickerProviderStateMixin {
  late final PlanRepository _repo;

  // Focus timer: seconds left, and the wall-clock end while running.
  late int _total;
  late int _left;
  DateTime? _endsAt;
  Timer? _ticker;

  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  late final TextEditingController _note;
  late _NoteState _noteState;
  late String _savedNote;
  Timer? _noteDebounce;
  bool _noteSaveInFlight = false;

  /// The shown completion of a habit outside today's view.
  bool? _localDone;
  bool _localBusy = false;
  int _burst = 0;

  String get _id => widget.detailed.item.id;
  bool get _running => _endsAt != null;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// One session's minutes, as Today and Plan show them: the server's
  /// `session_minutes`, else a seventh of the week's allocation (never the
  /// whole week's).
  int get _minutes => widget.detailed.sessionMinutesOrWeekShare;
  Map<String, dynamic>? get _review => widget.detailed.habitReview;
  Map<String, dynamic>? get _schedule => widget.detailed.habitSchedule;
  bool get _scheduled => _schedule?['scheduled_today'] != false;

  Future<void> _openReview() async {
    final step = _review?['step_id'] as String?;
    if (step == null || _review?['available'] != true) return;
    if (!_running && _left > 0) _startOrPause();
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => LessonPracticeScreen(
          itemId: _id,
          stepId: step,
          lessonTitle: 'Practice and review',
          lessonContent: '',
          isReview: true,
          reviewSeconds: _left,
        ),
      ),
    );
    if (!mounted) return;
    if (_running) _startOrPause();
    await widget.onReload();
  }

  Future<void> _editSchedule() async {
    final editing = (_schedule?['pending'] as Map?) ?? _schedule;
    final chosen = ((editing?['weekdays'] as List?) ?? [0, 2, 4])
        .cast<int>()
        .toSet();
    final cue = TextEditingController(text: editing?['cue'] as String? ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              24,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your practice schedule',
                  style: AppTypography.display(26),
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose days that fit your week. Your weekly minutes stay the same. Changes start next Monday.',
                  style: AppTypography.sans(14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 0; d < 7; d++)
                      FilterChip(
                        label: Text(_dayNames[d].substring(0, 3)),
                        selected: chosen.contains(d),
                        onSelected: (on) => update(() {
                          if (on) {
                            chosen.add(d);
                          } else {
                            chosen.remove(d);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cue,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'When will you start?',
                    hintText: 'For example, after breakfast',
                  ),
                ),
                const SizedBox(height: 12),
                V3Button(
                  full: true,
                  onPressed: chosen.isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child: const Text('Save schedule'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final cueText = cue.text;
    cue.dispose();
    if (saved != true || !mounted) return;
    try {
      await _repo.savePracticeSchedule(_id, chosen.toList()..sort(), cueText);
      if (!mounted) return;
      showV3Toast(context, 'Schedule saved. Starts next Monday.');
      await widget.onReload();
    } catch (_) {
      if (mounted) {
        showV3Toast(
          context,
          'Couldn’t save the schedule. Please try again.',
          tone: V3ToastTone.warn,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _repo = ref.read(planRepositoryProvider);
    _total = _minutes * 60;
    _left = _total;
    _savedNote = widget.detailed.dailyReflection;
    _note = TextEditingController(text: _savedNote);
    _noteState = _savedNote.isEmpty ? _NoteState.idle : _NoteState.saved;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreathe();
  }

  @override
  void didUpdateWidget(HabitDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detailed != widget.detailed && !_localBusy) {
      _localDone = null;
    }
    if (oldWidget.detailed.sessionMinutesOrWeekShare != _minutes) {
      _stopTicker();
      _total = _minutes * 60;
      _left = _total;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _breathe.dispose();
    // Leaving mid-pause, or after a failed save, still keeps what was typed.
    _noteDebounce?.cancel();
    if (_note.text != _savedNote) {
      unawaited(_persistNote(_note.text).catchError((Object _) {}));
    }
    _note.dispose();
    super.dispose();
  }

  // ── timer ───────────────────────────────────────────────────────────────

  void _syncBreathe() {
    if (_running && MotionConfig.enabled(context)) {
      if (!_breathe.isAnimating) _breathe.repeat();
    } else {
      _breathe
        ..stop()
        ..value = 0;
    }
  }

  void _startOrPause() {
    if (_running) {
      _tick();
      _stopTicker();
    } else {
      if (_left == 0) _left = _total;
      _endsAt = _now().add(Duration(seconds: _left));
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _tick(),
      );
    }
    setState(_syncBreathe);
  }

  void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null || !mounted) return;
    final ms = endsAt.difference(_now()).inMilliseconds;
    final left = ms <= 0 ? 0 : (ms / 1000).ceil().clamp(0, _total);
    if (left == 0) {
      _stopTicker();
      setState(() {
        _left = 0;
        _syncBreathe();
      });
    } else if (left != _left) {
      setState(() => _left = left);
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
  }

  void _reset() {
    setState(() {
      _stopTicker();
      _left = _total;
      _syncBreathe();
    });
  }

  // ── done today ──────────────────────────────────────────────────────────

  TodayTaskItem? _todayItem(TodayView? view) {
    for (final item in view?.items ?? const <TodayTaskItem>[]) {
      if (item.id == _id) return item;
    }
    return null;
  }

  bool _isDone(TodayView? view) {
    final item = _todayItem(view);
    if (item != null) return isHabitDone(item);
    return _localDone ?? widget.detailed.completedToday;
  }

  Future<void> _toggle(TodayView? view) async {
    if (_note.text != _savedNote) {
      await _saveNote();
      if (!mounted || _note.text != _savedNote) return;
    }
    final item = _todayItem(view);
    // A tap the toggle would ignore (one already in flight) changes nothing.
    if (_localBusy || (item != null && isHabitInFlight(item.id))) return;
    final wasDone = _isDone(view);
    setState(() {
      if (!wasDone) _burst++;
      if (_running) {
        _tick();
        _stopTicker();
      }
      _syncBreathe();
    });
    if (view != null && item != null) {
      await toggleHabit(view, item, toastOnUndo: true);
    } else {
      await _toggleOutsideToday(wasDone);
    }
    if (!mounted) return;
    await widget.onReload();
  }

  /// The toggle for a habit that today's view does not list (a stale tab
  /// or a habit from another week): optimistic, with the same toasts.
  Future<void> _toggleOutsideToday(bool wasDone) async {
    setState(() {
      _localBusy = true;
      _localDone = !wasDone;
    });
    if (wasDone) {
      showV3Toast(
        context,
        'Marked not done',
        icon: V3Icons.refresh,
        tone: V3ToastTone.warn,
      );
    } else {
      showV3Toast(context, 'Done for today');
    }
    // Today, the streak and the week refresh even if this screen closes
    // before the server answers.
    final container = ProviderScope.containerOf(context, listen: false);
    final id = _id;
    try {
      final completed = await _repo.toggleDailyTask(id);
      container
        ..invalidate(todayViewProvider)
        ..invalidate(todayStreakProvider)
        ..invalidate(habitDailyStatusProvider(id));
      if (!mounted) return;
      setState(() => _localDone = completed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _localDone = wasDone);
      showV3Toast(
        context,
        'Couldn’t update — try again.',
        icon: V3Icons.alert,
        tone: V3ToastTone.warn,
      );
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  // ── reflection ──────────────────────────────────────────────────────────

  void _onNoteChanged(String text) {
    _noteDebounce?.cancel();
    if (text == _savedNote && !_noteSaveInFlight) {
      setState(
        () => _noteState = text.isEmpty ? _NoteState.idle : _NoteState.saved,
      );
      return;
    }
    setState(() => _noteState = _NoteState.saving);
    _noteDebounce = Timer(const Duration(milliseconds: 800), _saveNote);
  }

  /// Saves the note, one request at a time. A save that returns while the
  /// field holds other text (typed, or undone, meanwhile) is followed by
  /// another, so the server always ends with what the field shows.
  Future<void> _saveNote() async {
    if (_noteSaveInFlight) return;
    final text = _note.text;
    if (text == _savedNote) {
      setState(
        () => _noteState = text.isEmpty ? _NoteState.idle : _NoteState.saved,
      );
      return;
    }
    _noteSaveInFlight = true;
    setState(() => _noteState = _NoteState.saving);
    try {
      await _persistNote(text);
      _savedNote = text;
    } catch (_) {
      _noteSaveInFlight = false;
      if (mounted) setState(() => _noteState = _NoteState.failed);
      return;
    }
    _noteSaveInFlight = false;
    if (!mounted) return;
    if (_note.text != _savedNote) {
      // A pending pause timer saves the newer text; otherwise save it now.
      if (!(_noteDebounce?.isActive ?? false)) unawaited(_saveNote());
      return;
    }
    setState(
      () => _noteState = text.isEmpty ? _NoteState.idle : _NoteState.saved,
    );
  }

  Future<void> _persistNote(String text) {
    final date = _review?['date'] as String?;
    return date == null
        ? _repo.saveDailyReflection(_id, text)
        : _repo.saveReviewReflection(_id, text, date);
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    watchFreshHabits();
    final view = ref.watch(todayViewProvider).valueOrNull;
    final done = _isDone(view);
    final now = _now();
    final week = watchHabitWeek(ref, _id, now);
    final days = [for (final d in week) d ?? done];
    final minutes = _minutes;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: V3FooterScaffold(
        topBar: V3TopBar(
          onBack: () => Navigator.of(context).maybePop(),
          right: V3Tag(
            icon: V3Icons.clock,
            child: Text('$minutes min', style: AppTypography.tnum),
          ),
        ),
        body: (context, bottom) => ListView(
          key: const Key('habit-detail-scroll'),
          padding: EdgeInsets.only(bottom: bottom),
          children: [
            _header(view, done),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: V3Rise(
                delay: const Duration(milliseconds: 160),
                child: _timerCard(done),
              ),
            ),
            V3Rise(
              delay: const Duration(milliseconds: 220),
              child: V3Section(title: 'How to do it', child: _howTo()),
            ),
            if (_review != null)
              V3Section(
                title: 'Your review',
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: v3Card(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _review?['available'] == true
                            ? 'Recall first, then try the supplied case. Check your answer and correct the rule you missed. These are reviews of familiar cases; new applications stay in your lessons.'
                            : (_review?['message'] as String? ??
                                  'Finish a lesson practice to begin your reviews.'),
                        style: AppTypography.sans(14).copyWith(height: 1.5),
                      ),
                      if ((_review?['source_titles'] as List? ?? [])
                          .isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'From: ${(_review!['source_titles'] as List).join(' · ')}',
                          style: AppTypography.sans(12),
                        ),
                      ],
                      if (_review?['available'] == true) ...[
                        const SizedBox(height: 14),
                        V3Button(
                          key: const Key('open-habit-review'),
                          onPressed: _openReview,
                          child: Text(
                            _review?['attempted'] == true
                                ? 'Review saved answers'
                                : 'Open review',
                          ),
                        ),
                      ],
                      if (_review?['attempted'] == true) ...[
                        const SizedBox(height: 10),
                        Text(
                          _review?['needs_correction'] == true
                              ? 'Revise your answer or record the corrected rule below before logging the session.'
                              : 'Your checked attempt is saved. Logging the session records participation, not mastery.',
                          style: AppTypography.sans(
                            13,
                          ).copyWith(color: AppColors.ink2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            V3Rise(
              delay: const Duration(milliseconds: 260),
              child: V3Section(title: 'Reflection', child: _reflection()),
            ),
            V3Rise(
              delay: const Duration(milliseconds: 300),
              child: V3Section(
                title: 'This week',
                child: _week(days, todayIndex: now.weekday - 1),
              ),
            ),
          ],
        ),
        footer: Stack(
          clipBehavior: Clip.none,
          children: [
            done
                ? V3Button(
                    kind: V3ButtonKind.soft,
                    full: true,
                    icon: V3Icons.refresh,
                    onPressed: () => _toggle(view),
                    child: const Text('Mark as not done'),
                  )
                : _review != null && _review?['attempted'] != true
                ? V3Button(
                    full: true,
                    onPressed: _review?['available'] == true
                        ? _openReview
                        : null,
                    child: Text(
                      _review?['available'] == true
                          ? 'Start review'
                          : 'No review ready',
                    ),
                  )
                : V3Button(
                    kind: V3ButtonKind.sage,
                    full: true,
                    icon: V3Icons.check,
                    onPressed:
                        _review?['needs_correction'] == true &&
                            _note.text.trim().length < 10
                        ? null
                        : () => _toggle(view),
                    child: Text(
                      _review == null
                          ? 'Mark done for today'
                          : 'Log practice session',
                    ),
                  ),
            // The design's burst sits in a zero-size box at the button's
            // centre: particles only, no halo the size of the button.
            if (_burst > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: SizedBox.shrink(
                      child: V3Burst(
                        key: ValueKey(_burst),
                        color: AppColors.sage,
                        count: 14,
                        radius: 70,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(TodayView? view, bool done) {
    final item = widget.detailed.item;
    final habits = view?.items ?? const <TodayTaskItem>[];
    final index = habits.indexWhere((h) => h.id == _id);
    final kick = _review != null
        ? 'Practice routine · Week ${item.weekStart}'
        : index < 0
        ? 'Daily habit · Week ${item.weekStart}'
        : 'Daily habit ${index + 1} of ${habits.length} · '
              'Week ${item.weekStart}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V3Rise(child: Text(kick.toUpperCase(), style: AppTypography.kick)),
          const SizedBox(height: 10),
          V3Rise(
            delay: const Duration(milliseconds: 60),
            child: Text(
              item.title,
              style: AppTypography.display(38).copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 14),
          V3Rise(
            delay: const Duration(milliseconds: 110),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                V3Tag(
                  icon: V3Icons.refresh,
                  child: Text(
                    _schedule?['label'] as String? ?? 'Scheduled practice',
                  ),
                ),
                done
                    ? const V3Tag(
                        background: AppColors.sageSoft,
                        color: AppColors.sage2,
                        icon: V3Icons.check,
                        child: Text('Done today'),
                      )
                    : V3Tag(
                        background: AppColors.emberSoft,
                        color: AppColors.ember2,
                        child: Text(_scheduled ? 'Practice day' : 'Rest day'),
                      ),
              ],
            ),
          ),
          if (_schedule != null) ...[
            const SizedBox(height: 10),
            Text(
              _schedule!['cue'] as String? ?? '',
              style: AppTypography.sans(13),
            ),
            TextButton(
              onPressed: _editSchedule,
              child: const Text('Choose days and starting cue'),
            ),
            if (_schedule?['pending'] is Map)
              Text(
                'Updated schedule starts ${_schedule!['pending']['from']}.',
                style: AppTypography.sans(13),
              ),
          ],
        ],
      ),
    );
  }

  Widget _timerCard(bool done) {
    final motion = MotionConfig.enabled(context);
    final mm = _left ~/ 60;
    final ss = (_left % 60).toString().padLeft(2, '0');
    final label = _left == 0
        ? 'Time’s up'
        : _running
        ? 'Focus'
        : 'Focus timer';
    const glow = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // CSS `circle` = farthest-corner on a square box.
          radius: 0.7071,
          colors: [_emberGlow, Color(0x00BA480D)],
          stops: [0, .65],
        ),
      ),
    );
    return ClipRRect(
      borderRadius: AppRadii.brR2,
      child: Container(
        color: AppColors.night,
        padding: const EdgeInsets.all(22),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(child: V3Grain()),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: box.maxWidth / 2 - 150,
                      top: box.maxHeight * .42 - 150,
                      width: 300,
                      height: 300,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _running ? 1 : .5,
                          duration: motion
                              ? const Duration(milliseconds: 500)
                              : Duration.zero,
                          child: AnimatedBuilder(
                            animation: _breathe,
                            builder: (context, child) {
                              if (!_breathe.isAnimating) return child!;
                              // breathe: 0%,100% scale 1 / .55; 50% 1.08 / .9.
                              final t = _breathe.value;
                              final k = Curves.easeInOut.transform(
                                t < .5 ? t * 2 : (1 - t) * 2,
                              );
                              return Opacity(
                                opacity: .55 + .35 * k,
                                child: Transform.scale(
                                  scale: 1 + .08 * k,
                                  child: child,
                                ),
                              );
                            },
                            child: glow,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: V3Ring(
                    value: done ? 1 : 1 - _left / _total,
                    size: 168,
                    strokeWidth: 8,
                    color: done ? AppColors.sage : AppColors.ember,
                    track: const Color(0x1AFFFFFF),
                    child: done
                        ? const V3Pop(
                            child: V3Icon(
                              V3Icons.check,
                              size: 54,
                              strokeWidth: 2.6,
                              color: Colors.white,
                            ),
                          )
                        : Semantics(
                            label: '$label, $mm:$ss',
                            excludeSemantics: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$mm:$ss',
                                  style: AppTypography.display(52)
                                      .merge(AppTypography.tnum)
                                      .copyWith(color: Colors.white, height: 1),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  style: AppTypography.sans(
                                    11.5,
                                  ).copyWith(color: AppColors.nink3),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                if (!done) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      V3Button(
                        size: V3Size.md,
                        kind: _running
                            ? V3ButtonKind.glass
                            : V3ButtonKind.light,
                        icon: _running ? V3Icons.pause : V3Icons.play,
                        onPressed: _startOrPause,
                        child: Text(
                          _running
                              ? 'Pause'
                              : _left < _total && _left > 0
                              ? 'Resume'
                              : 'Start timer',
                        ),
                      ),
                      if (_left < _total)
                        V3Button(
                          size: V3Size.md,
                          kind: V3ButtonKind.glass,
                          icon: V3Icons.refresh,
                          onPressed: _reset,
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(
                    'Session logged. Return on your next scheduled practice day.',
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      14,
                    ).copyWith(color: AppColors.nink2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _howTo() {
    final instructions = widget.detailed.dailyInstructions?.trim() ?? '';
    final body = instructions.isEmpty
        ? widget.detailed.item.description
        : instructions;
    final why = widget.detailed.item.successMetric.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: AppTypography.sans(
              15,
            ).copyWith(color: AppColors.ink, height: 1.55),
          ),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.irisSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: V3Icon(
                      V3Icons.target,
                      size: 17,
                      color: AppColors.iris2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Why it matters this week',
                          style: AppTypography.sans(
                            12,
                            FontWeight.w600,
                          ).copyWith(color: AppColors.iris2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          why,
                          style: AppTypography.sans(
                            13.5,
                          ).copyWith(color: AppColors.ink2, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reflection() {
    final empty = _note.text.isEmpty;
    final Widget status;
    if (_noteState == _NoteState.failed) {
      const message = 'Couldn’t save. Your text is still here; please retry.';
      status = V3Pressable(
        key: const Key('habit-note-retry'),
        onTap: _saveNote,
        semanticLabel: message,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              message,
              style: AppTypography.sans(12).copyWith(color: AppColors.danger),
            ),
          ),
        ),
      );
    } else if (empty) {
      status = Text(
        'Saved with today’s entry',
        style: AppTypography.sans(12).copyWith(color: AppColors.ink3),
      );
    } else if (_noteState == _NoteState.saved) {
      status = Row(
        children: [
          const V3Icon(
            V3Icons.check,
            size: 13,
            strokeWidth: 2.6,
            color: AppColors.sage2,
          ),
          const SizedBox(width: 6),
          Text(
            'Saved for today',
            style: AppTypography.sans(12).copyWith(color: AppColors.sage2),
          ),
        ],
      );
    } else {
      status = Row(
        children: [
          const V3Spinner(size: 12, color: AppColors.ink3, semanticLabel: null),
          const SizedBox(width: 6),
          Text(
            'Saving',
            style: AppTypography.sans(12).copyWith(color: AppColors.ink3),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            habitReflectionPrompt,
            style: AppTypography.read(
              16.5,
            ).copyWith(color: AppColors.ink, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            onChanged: _onNoteChanged,
            minLines: 3,
            maxLines: 6,
            inputFormatters: [LengthLimitingTextInputFormatter(8000)],
            textCapitalization: TextCapitalization.sentences,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            style: AppTypography.sans(
              15,
            ).copyWith(color: AppColors.ink, height: 1.45),
            decoration: InputDecoration(
              hintText: 'Optional, a line is enough',
              hintStyle: AppTypography.sans(
                15,
              ).copyWith(color: AppColors.ink3, height: 1.45),
              filled: true,
              fillColor: AppColors.paper,
              isDense: true,
              contentPadding: const EdgeInsets.all(12),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 16),
            child: status,
          ),
        ],
      ),
    );
  }

  Widget _week(List<bool> days, {required int todayIndex}) {
    final scheduled =
        ((_schedule?['weekdays'] as List?) ?? [0, 1, 2, 3, 4, 5, 6])
            .cast<int>();
    final count = scheduled.where((d) => days[d]).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$count',
                style: AppTypography.display(
                  30,
                ).merge(AppTypography.tnum).copyWith(color: AppColors.ink),
              ),
              const SizedBox(width: 6),
              Text(
                'of ${scheduled.length} practice days logged',
                style: AppTypography.sans(13.5).copyWith(color: AppColors.ink2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rest days do not reset your practice streak.',
            style: AppTypography.sans(12).copyWith(color: AppColors.ink2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var k = 0; k < 7; k++) ...[
                if (k > 0) const SizedBox(width: 5),
                Expanded(child: _day(k, days[k], today: k == todayIndex)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _day(int k, bool done, {required bool today}) {
    final motion = MotionConfig.enabled(context);
    final scheduled = (_schedule?['weekdays'] as List?)?.contains(k) ?? true;
    final Widget cell = today && !done && scheduled
        ? const PlanDashedCell(
            key: ValueKey('habit-day-today'),
            height: 34,
            radius: 10,
            color: AppColors.ember,
          )
        : AnimatedContainer(
            key: ValueKey(done ? 'habit-day-done' : 'habit-day-open'),
            duration: motion
                ? const Duration(milliseconds: 400)
                : Duration.zero,
            height: 34,
            decoration: BoxDecoration(
              color: done ? AppColors.sage : AppColors.paper2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: done
                ? const Center(
                    child: V3Icon(
                      V3Icons.check,
                      size: 14,
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : !scheduled
                ? const Center(child: Text('–'))
                : null,
          );
    return Semantics(
      label:
          '${_dayNames[k]}${today ? ', today' : ''}, '
          '${done
              ? 'done'
              : !scheduled
              ? 'rest day'
              : 'not done'}',
      excludeSemantics: true,
      child: _dayColumn(k, cell, today: today),
    );
  }

  Widget _dayColumn(int k, Widget cell, {required bool today}) {
    return Column(
      children: [
        cell,
        const SizedBox(height: 5),
        Text(
          today ? 'Today' : _letters[k],
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: AppTypography.sans(
            10.5,
            FontWeight.w600,
          ).copyWith(color: today ? AppColors.ember2 : AppColors.ink3),
        ),
      ],
    );
  }
}
