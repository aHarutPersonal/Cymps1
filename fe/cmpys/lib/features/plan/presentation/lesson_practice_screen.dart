import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/practice_repository.dart';
import '../models/practice_models.dart';

/// A workspace, not a chat: every answer belongs to an explicit exercise.
///
/// `PracticeScreen` from `v3/practice.jsx`: the draft pill, the Guided →
/// Independent stepper, the case and its data, "Your answers", the checking
/// pass and result panel, attempts, the worked solution and the finish.
///
/// Pops `true` only after an explicit "Finish …" on completed practice: the
/// reader then completes the step and, once that succeeds, celebrates with
/// [achievementFor]. Every other exit pops `false` or null.
class LessonPracticeScreen extends ConsumerStatefulWidget {
  const LessonPracticeScreen({
    super.key,
    required this.itemId,
    required this.stepId,
    required this.lessonTitle,
    required this.lessonContent,
    this.artifactJobId,
    this.onArtifactRefreshed,
    this.dark = false,
    this.isTutorial = false,
    this.tutorialNumber,
  });
  final String itemId, stepId, lessonTitle, lessonContent;
  final String? artifactJobId;
  final ValueChanged<String>? onArtifactRefreshed;

  /// The reader's dark theme. Kept for callers: the v3 workbook is drawn on
  /// paper in every reader theme, as in the design.
  final bool dark;
  final bool isTutorial;

  /// The tutorial's number in its mission: the top bar reads "Practice ·
  /// Tutorial n".
  final int? tutorialNumber;

  /// The achievement the finish celebration suggests for [tutorialTitle]
  /// (no server field holds one), at most 200 characters, the record's limit.
  static String achievementFor(String tutorialTitle) {
    final title = tutorialTitle.trim();
    final text = title.isEmpty
        ? 'Completed a tutorial with every case accepted'
        : 'Completed “$title” with every case accepted';
    return text.length <= 200 ? text : '${text.substring(0, 199)}…';
  }

  @override
  ConsumerState<LessonPracticeScreen> createState() =>
      _LessonPracticeScreenState();
}

enum _Phase { edit, checking, result }

enum _Leave { discard, saved, retry }

/// One criterion row of the result panel (one per field, in field order).
class _Verdict {
  const _Verdict({
    required this.label,
    required this.met,
    this.feedback,
    this.rubric = const [],
  });
  final String label;
  final bool met;
  final String? feedback;

  /// A text answer's rubric lines: (met, criterion).
  final List<(bool, String)> rubric;
}

const _danger = AppColors.danger;

class _LessonPracticeScreenState extends ConsumerState<LessonPracticeScreen>
    with WidgetsBindingObserver {
  String get _unit => widget.isTutorial ? 'tutorial' : 'lesson';
  LessonPracticeState? _state;
  late String? _artifactJobId = widget.artifactJobId;
  final _controllers = <String, TextEditingController>{};
  final _scroll = ScrollController();
  Timer? _debounce;
  Timer? _preparationPollTimer;
  Completer<void>? _preparationPollWait;
  Future<bool>? _saveFlight;
  bool _loading = true, _busy = false, _dirty = false, _saving = false;
  bool _preparing = false;
  bool _leaving = false;
  int _editVersion = 0, _index = 0;
  String? _error;

  /// The first workbook opens on the case still to do (the design's
  /// `uS(P.g.passed ? 1 : 0)`); later loads keep the learner's place.
  bool _positioned = false;

  /// "Revise answer" reopened a checked answer for editing.
  bool _revising = false;

  /// The checking pass: the request, then one criterion every 700 ms.
  bool _checking = false;
  int _ticks = 0;
  Timer? _tickTimer;
  bool _showSolution = false;

  /// The field whose hint is being fetched; only its button shows busy.
  String? _hinting;

  /// Completes once a hint request has landed: a hint bumps the revision, so
  /// saves and checks wait for it rather than send a stale one.
  Completer<void>? _hintLanded;

  /// The device's decimal separator, which settles an ambiguous "1,250".
  String _decimal = '.';

  PracticeRepository get _repo => ref.read(practiceRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _decimal = _deviceDecimal();
    unawaited(_load());
  }

  // The app has English strings only, so `Localizations` is always en_US;
  // number habits follow the device, as the Today date kicker does.
  static String _deviceDecimal() => decimalSeparatorFor(
    WidgetsBinding.instance.platformDispatcher.locale.toString(),
  );

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted) setState(() => _decimal = _deviceDecimal());
  }

  /// The learner's live input: an ambiguous "1,250" follows the device.
  String _wire(PracticeField f, String raw) =>
      f.wire(raw, decimalSeparator: _decimal);

  /// A value the server stored or graded, read with the server's grammar
  /// (`float(raw.replace(",", "."))`: a single comma is a decimal), whatever
  /// the device's locale. A legacy "1,250" was graded as 1.25.
  static String _storedWire(PracticeField f, String raw) =>
      f.wire(raw, decimalSeparator: ',');

  /// What the field's text means now: still the stored answer, it reads as
  /// the server reads it; typed by the learner, with the device's locale.
  String _current(String key, PracticeField f) {
    final text = _controllers[key]?.text ?? '';
    return text == _state?.answers[key] ? _storedWire(f, text) : _wire(f, text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _tickTimer?.cancel();
    _cancelPreparationPolling();
    _scroll.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _dirty) unawaited(_save());
  }

  void _accept(LessonPracticeState result, {bool restore = false}) {
    _state = result;
    for (final a in result.activities) {
      for (final f in a.fields) {
        final key = '${a.id}.${f.id}';
        final c = _controllers.putIfAbsent(
          key,
          () => TextEditingController(text: result.answers[key] ?? ''),
        );
        if (restore) c.text = result.answers[key] ?? '';
      }
    }
    if (result.activities.isEmpty) return;
    final firstIncomplete = result.activities.indexWhere(
      (a) => !result.passed.contains(a.id),
    );
    if (!_positioned) {
      _positioned = true;
      _index = firstIncomplete >= 0
          ? firstIncomplete
          : result.activities.length - 1;
    }
    if (_index >= result.activities.length) _index = 0;
    if (firstIncomplete >= 0 && _index > firstIncomplete) {
      _index = firstIncomplete;
    }
  }

  Future<T> _withArtifactRefresh<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ApiError catch (error) {
      final previous = _state;
      if (error.statusCode != 409) rethrow;
      final refreshed = previous == null && !_dirty
          ? await _repo.refreshUnopened(
              widget.itemId,
              widget.stepId,
              _artifactJobId,
              widget.lessonTitle,
              widget.lessonContent,
            )
          : previous == null
          ? null
          : await _repo.refreshUnchanged(
              widget.itemId,
              widget.stepId,
              _artifactJobId,
              previous,
            );
      if (refreshed == null || !mounted) rethrow;
      setState(() {
        _artifactJobId = refreshed.artifact;
        _accept(refreshed.state);
      });
      widget.onArtifactRefreshed?.call(refreshed.artifact);
      return operation(); // One retry, retaining local edits and the revision.
    }
  }

  Future<void> _load({bool discardLocal = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _withArtifactRefresh<LessonPracticeState>(
        () => _repo.load(widget.itemId, widget.stepId, _artifactJobId),
      );
      if (!mounted) return;
      setState(() {
        if (discardLocal) _dirty = false;
        _accept(result, restore: !_dirty);
        _loading = false;
      });
      if (!_busy && !_dirty) {
        if (result.state == 'preparing') {
          await _prepare(pending: result);
        } else if (result.preparedAvailable) {
          await _prepare();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Could not load practice. Your current answers are still on this screen.';
        });
      }
    }
  }

  Future<void> _prepare({LessonPracticeState? pending}) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _preparing = true;
      _error = null;
    });
    try {
      var result =
          pending ??
          await _withArtifactRefresh<LessonPracticeState>(
            () => _repo.prepare(widget.itemId, widget.stepId, _artifactJobId),
          );
      // Another client may already own preparation. Poll without another paid POST.
      // Cover its 120-second lease while allowing the user to leave at any time.
      for (var i = 0; result.state == 'preparing' && i < 24 && mounted; i++) {
        await _waitForPreparationPoll();
        if (!mounted) return;
        result = await _withArtifactRefresh<LessonPracticeState>(
          () => _repo.load(widget.itemId, widget.stepId, _artifactJobId),
        );
      }
      if (mounted) setState(() => _accept(result, restore: true));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Practice could not be prepared. Refresh to check its status before retrying.',
        );
      }
    } finally {
      _cancelPreparationPolling();
      if (mounted) {
        setState(() {
          _busy = false;
          _preparing = false;
        });
      }
    }
  }

  Future<void> _waitForPreparationPoll() {
    final wait = Completer<void>();
    _preparationPollWait = wait;
    _preparationPollTimer = Timer(const Duration(seconds: 5), () {
      _preparationPollTimer = null;
      _preparationPollWait = null;
      wait.complete();
    });
    return wait.future;
  }

  void _cancelPreparationPolling() {
    _preparationPollTimer?.cancel();
    _preparationPollTimer = null;
    final wait = _preparationPollWait;
    _preparationPollWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
  }

  void _changed([String _ = '']) {
    setState(() {
      _dirty = true;
      _editVersion++;
      _error = null;
      // Editing keeps the case in edit, even when the answers come to equal
      // an earlier attempt's.
      _revising = true;
    });
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(_save()),
    );
  }

  void _selectActivity(int index) {
    FocusScope.of(context).unfocus();
    _tickTimer?.cancel();
    setState(() {
      _index = index;
      _revising = false;
      _showSolution = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<bool> _save() {
    if (_saveFlight != null) return _saveFlight!;
    final flight = _saveLoop();
    _saveFlight = flight;
    return flight.whenComplete(() => _saveFlight = null);
  }

  Future<bool> _saveLoop() async {
    _debounce?.cancel();
    if (!_dirty || _state == null) return true;
    setState(() => _saving = true);
    try {
      while (_dirty && mounted) {
        if (_hintLanded case final hint?) {
          await hint.future;
          continue;
        }
        final version = _editVersion;
        final activities = _state!.activities;
        final answers = _answersToSend();
        final result = await _withArtifactRefresh<LessonPracticeState>(
          () => _repo.save(
            widget.itemId,
            widget.stepId,
            _artifactJobId,
            _state!.revision,
            answers,
            activities: activities,
          ),
        );
        if (!mounted) return false;
        setState(() {
          _accept(result);
          if (version == _editVersion) _dirty = false;
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Not saved yet. Check your connection and retry. If this work changed elsewhere, reload the saved version.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Every answer as it goes on the wire: what the learner changed is
  /// normalised (a plain decimal, a canonical selection); an answer whose
  /// meaning is unchanged keeps the server's stored spelling, so a draft
  /// saved by an older build ("4,5") still matches its passed attempt.
  Map<String, String> _answersToSend() {
    final s = _state!;
    final answers = <String, String>{};
    for (final a in s.activities) {
      for (final f in a.fields) {
        final key = '${a.id}.${f.id}';
        final wire = _current(key, f);
        final stored = s.answers[key];
        answers[key] = stored != null && _storedWire(f, stored) == wire
            ? stored
            : wire;
      }
    }
    return answers;
  }

  /// Saves, then runs [action] on the current activity. False when the work
  /// could not be saved or the action failed (the error is on screen).
  Future<bool> _act(String action, {bool solution = false}) async {
    // A hint in flight (its pre-save included) owns the next revision.
    if (_busy || _hinting != null || _state == null) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hintLanded case final hint?) await hint.future;
      if (!await _save() || !mounted) return false;
      final a = _state!.activities[_index];
      final requestId =
          '${DateTime.now().microsecondsSinceEpoch}_${_state!.revision}';
      final result = await _withArtifactRefresh<LessonPracticeState>(
        () => _repo.act(
          widget.itemId,
          widget.stepId,
          _artifactJobId,
          action: action,
          revision: _state!.revision,
          activity: a.id,
          requestId: requestId,
          solution: solution,
        ),
      );
      if (mounted) setState(() => _accept(result));
      return true;
    } catch (_) {
      // Recover a committed response after a transport timeout. The server
      // also deduplicates unchanged answer snapshots before charging again.
      try {
        final result = await _withArtifactRefresh<LessonPracticeState>(
          () => _repo.load(widget.itemId, widget.stepId, _artifactJobId),
        );
        if (mounted) setState(() => _accept(result));
      } catch (_) {
        /* Keep the saved answer visible. */
      }
      if (mounted) {
        setState(
          () => _error =
              'Your answers are saved. Could not finish this check; refresh its status or try again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Submit for checking": the night panel, then (once the server has
  /// graded) the design's ticks, one criterion every 700 ms, and the result
  /// 500 ms after the last. Reduced motion shows the result at once.
  Future<void> _submit() async {
    final s = _state;
    if (_busy || _checking || s == null) return;
    FocusScope.of(context).unfocus();
    final a = s.activities[_index];
    _tickTimer?.cancel();
    setState(() {
      _checking = true;
      _ticks = 0;
      _revising = false;
      _showSolution = false;
    });
    _scrollToTop();
    final ok = await _act('submit');
    if (!mounted) return;
    final graded = ok && _resultAttempt(_state!, a) != null;
    if (!graded || !MotionConfig.enabled(context)) {
      setState(() => _checking = false);
      return;
    }
    final total = a.fields.length;
    _tickTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _ticks++);
      if (_ticks >= total) {
        timer.cancel();
        _tickTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _checking = false);
        });
      }
    });
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    if (MotionConfig.enabled(context)) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: AppMotion.out,
        ),
      );
    } else {
      _scroll.jumpTo(0);
    }
  }

  /// "Hint": the server reveals this field's hint and records it, so the
  /// button reads "Hint used" from then on, across reloads.
  ///
  /// Only the tapped button shows busy: every field stays editable and a
  /// focused one keeps the keyboard. Saves typed meanwhile wait for the
  /// hint, whose response carries the next revision.
  Future<void> _hint(PracticeActivity a, PracticeField f) async {
    final s = _state;
    final key = '${a.id}.${f.id}';
    if (_hinting != null || _busy || _checking || s == null) return;
    if (s.fieldHint(key) != null) return;
    setState(() {
      _hinting = key;
      _error = null;
    });
    Completer<void>? landed;
    try {
      // The hint bumps the revision: save first so it names the latest one.
      if (!await _save() || !mounted) return;
      landed = _hintLanded = Completer<void>();
      final requestId =
          '${DateTime.now().microsecondsSinceEpoch}_${_state!.revision}';
      final result = await _withArtifactRefresh<LessonPracticeState>(
        () => _repo.fieldHint(
          widget.itemId,
          widget.stepId,
          _artifactJobId,
          revision: _state!.revision,
          activity: a.id,
          fieldId: key,
          requestId: requestId,
        ),
      );
      if (mounted) setState(() => _accept(result));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load this hint. Check your connection and try again.',
        );
      }
    } finally {
      _hintLanded = null;
      landed?.complete();
      if (mounted) setState(() => _hinting = null);
    }
  }

  String? _solutionFor(LessonPracticeState s, PracticeActivity a) {
    for (final h in s.hints) {
      if (h['activity_id'] == a.id && h['kind'] == 'solution') {
        return h['content'] as String? ?? '';
      }
    }
    return null;
  }

  Future<void> _toggleSolution(PracticeActivity a) async {
    final s = _state;
    if (s == null) return;
    if (_showSolution || _solutionFor(s, a) != null) {
      setState(() => _showSolution = !_showSolution);
      return;
    }
    if (await _act('hint', solution: true) && mounted) {
      setState(() => _showSolution = true);
    }
  }

  /// "Finish tutorial": back to the reader with `true`. The reader completes
  /// the step and celebrates only once that succeeds.
  Future<void> _finish() async {
    final s = _state;
    if (_leaving || _busy || s == null || !s.complete) return;
    await _leave(completed: true);
  }

  /// Completes with the flush's result when it finishes within [limit], or
  /// null when it is still running.
  Future<bool?> _within(Future<bool> flush, Duration limit) {
    final done = Completer<bool?>();
    final timer = Timer(limit, () {
      if (!done.isCompleted) done.complete(null);
    });
    unawaited(
      flush.then((saved) {
        timer.cancel();
        if (!done.isCompleted) done.complete(saved);
      }),
    );
    return done.future;
  }

  Future<void> _leave({bool completed = false}) async {
    // Preparation cannot change an answer: leaving it is safe. Answer review
    // and pending saves retain their existing protection against lost work.
    if (_leaving || (_busy && !_preparing)) return;
    _leaving = true;
    try {
      var saved = true;
      // A quick flush leaves at once. A slow one asks, and closes its sheet
      // and leaves if it then lands; a failed one offers a retry.
      while (_dirty || _saving) {
        final flush = _save();
        final quick = await _within(flush, const Duration(milliseconds: 600));
        if (!mounted) return;
        if (quick == true) break;
        final choice = await showV3Sheet<_Leave>(
          context,
          title: 'Leave practice?',
          builder: (_) => _LeaveSheet(pending: quick == null ? flush : null),
        );
        if (!mounted || choice == null) return; // Keep editing.
        if (choice == _Leave.retry) continue;
        if (choice == _Leave.discard) {
          saved = false;
          _debounce?.cancel();
          setState(() => _dirty = false);
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
        }
        break;
      }
      Navigator.of(
        context,
      ).pop(saved && completed && (_state?.complete ?? false));
    } finally {
      _leaving = false;
    }
  }

  Future<void> _reloadSaved() async {
    if (_dirty) {
      final replace = await showV3Sheet<bool>(
        context,
        title: 'Reload saved work?',
        builder: (c) => _SheetChoice(
          message:
              'This replaces the unsaved changes on this screen with the latest saved answers.',
          primary: 'Reload',
          onPrimary: () => Navigator.pop(c, true),
          secondary: 'Keep editing',
          onSecondary: () => Navigator.pop(c, false),
        ),
      );
      if (replace != true || !mounted) return;
    }
    _debounce?.cancel();
    await _load(discardLocal: true);
  }

  Future<void> _showLesson() => showV3Sheet<void>(
    context,
    title: widget.isTutorial ? 'Tutorial reference' : 'Lesson reference',
    builder: (_) => CmpysMarkdown(widget.lessonContent),
  );

  // ── derived state ─────────────────────────────────────────────────────────

  String _text(PracticeActivity a, PracticeField f) =>
      _controllers['${a.id}.${f.id}']?.text ?? '';

  /// The latest attempt graded on exactly the current answers, if any.
  Map<String, dynamic>? _resultAttempt(
    LessonPracticeState s,
    PracticeActivity a,
  ) {
    for (final attempt in s.attemptsFor(a.id).reversed) {
      final answers = attempt['answers'];
      // Compared by meaning: a draft saved by an older build ("4,5") is
      // graded and stored as spelled, and still matches "4.5".
      if (answers is Map &&
          a.fields.every((f) {
            final stored = answers[f.id];
            return _storedWire(f, stored is String ? stored : '') ==
                _current('${a.id}.${f.id}', f);
          })) {
        return attempt;
      }
    }
    return null;
  }

  _Phase _phase(
    LessonPracticeState s,
    PracticeActivity a,
    Map<String, dynamic>? attempt,
  ) {
    if (_checking) return _Phase.checking;
    // A passed case is read-only. Otherwise a matching attempt shows its
    // result until the learner revises or types: typing back to an earlier
    // attempt's answers never flips the field to read-only.
    if (s.passed.contains(a.id) || (!_revising && attempt != null)) {
      return _Phase.result;
    }
    return _Phase.edit;
  }

  List<_Verdict> _verdicts(
    PracticeActivity a,
    Map<String, dynamic>? attempt, {
    bool passed = false,
  }) {
    final entries = <String, Map>{
      for (final e
          in (attempt?['feedback'] as List? ?? const []).whereType<Map>())
        if (e['field_id'] is String) e['field_id'] as String: e,
    };
    return [
      for (final f in a.fields) _verdict(f, entries[f.id], attempt, passed),
    ];
  }

  _Verdict _verdict(
    PracticeField f,
    Map? entry,
    Map<String, dynamic>? attempt,
    bool passed,
  ) {
    final met = entry != null
        ? entry['passed'] == true
        : attempt != null
        ? attempt['passed'] == true
        : passed;
    final flags = entry?['criterion_met'];
    final lines = entry?['criteria'];
    final criterion = entry?['criterion'];
    final feedback = entry?['feedback'];
    return _Verdict(
      // Attempts stored before v3 have no criterion: use the field's own.
      label: criterion is String && criterion.trim().isNotEmpty
          ? criterion
          : f.criterion,
      met: met,
      feedback: feedback is String && feedback.trim().isNotEmpty
          ? feedback
          : null,
      rubric: [
        if (flags is List && lines is List)
          for (var i = 0; i < flags.length && i < lines.length; i++)
            (flags[i] == true, '${lines[i]}'),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final ready = s != null && s.activities.isNotEmpty;
    final blocked = _busy || _checking || s?.state == 'reviewing';
    final activity = ready ? s.activities[_index] : null;
    final attempt = activity == null ? null : _resultAttempt(s!, activity);
    final phase = activity == null
        ? _Phase.edit
        : _phase(s!, activity, attempt);
    return PopScope(
      canPop: !_dirty && !_saving && (!_busy || _preparing),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: AppColors.paper,
          body: V3FooterScaffold(
            topBar: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                V3TopBar(
                  solid: true,
                  onBack: () => _leave(),
                  title: widget.isTutorial && widget.tutorialNumber != null
                      ? 'Practice · Tutorial ${widget.tutorialNumber}'
                      : 'Practice',
                  // At most 42% of the bar, so the title keeps its room on a
                  // 320 pt phone or at large text; the pill's label shrinks.
                  right: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .42,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (ready) Flexible(child: _draftPill()),
                        const SizedBox(width: 6),
                        V3IconButton(
                          icon: V3Icons.book,
                          label: 'Refer to $_unit',
                          onPressed: _showLesson,
                        ),
                      ],
                    ),
                  ),
                ),
                if (ready) _stepper(s, blocked),
              ],
            ),
            footer: _loading
                ? const SizedBox.shrink()
                : activity == null
                ? _prepareButton(s)
                : _cta(s!, activity, attempt, phase, blocked),
            body: (context, bottom) => _loading
                ? const Center(child: V3Spinner(color: AppColors.ink3))
                : SingleChildScrollView(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(20, 6, 20, bottom + 24),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (s?.state == 'reviewing') _reviewingNote(),
                            if (_error != null) _errorNote(),
                            if (activity == null)
                              _notReady(s)
                            else
                              KeyedSubtree(
                                key: ValueKey('activity-${activity.id}'),
                                child: V3Rise(
                                  duration: const Duration(milliseconds: 500),
                                  child: _activity(
                                    s!,
                                    activity,
                                    attempt,
                                    phase,
                                    blocked,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────

  /// "Draft saved" / "Saving" / "Unsaved".
  Widget _draftPill() {
    final saved = !_saving && !_dirty;
    final label = _saving
        ? 'Saving'
        : _dirty
        ? 'Unsaved'
        : 'Draft saved';
    final color = saved ? AppColors.sage2 : AppColors.ink3;
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.hair),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving)
                const V3Spinner(
                  size: 11,
                  color: AppColors.ink3,
                  semanticLabel: null,
                )
              else if (_dirty)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const V3Icon(
                  V3Icons.check,
                  size: 12,
                  strokeWidth: 2.6,
                  color: AppColors.sage2,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    12,
                    FontWeight.w600,
                  ).copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Guided → Independent. A case opens once every case before it passed.
  Widget _stepper(LessonPracticeState s, bool blocked) {
    final motion = MotionConfig.enabled(context);
    final activities = s.activities;
    return ColoredBox(
      color: AppColors.paper,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Labels ellipsize only when the design's row cannot fit (large
            // text, a narrow phone, a longer workbook).
            final scaler = MediaQuery.textScalerOf(context);
            var natural = (activities.length - 1) * 32.0; // gaps + a line
            for (final a in activities) {
              final painter = TextPainter(
                text: TextSpan(text: _kindLabel(a), style: _stepLabelStyle),
                textDirection: Directionality.of(context),
                textScaler: scaler,
                maxLines: 1,
              )..layout();
              natural += 34 + painter.width;
              painter.dispose();
            }
            final tight = natural > constraints.maxWidth;
            return Row(
              children: [
                for (var i = 0; i < activities.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: AnimatedContainer(
                          duration: motion
                              ? const Duration(milliseconds: 600)
                              : Duration.zero,
                          height: 2,
                          decoration: BoxDecoration(
                            color: s.passed.contains(activities[i - 1].id)
                                ? AppColors.sage
                                : AppColors.hair,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                  if (tight)
                    Flexible(child: _step(s, i, blocked, tight: true))
                  else
                    _step(s, i, blocked),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static final _stepLabelStyle = AppTypography.sans(
    13,
    FontWeight.w600,
  ).copyWith(color: AppColors.ink);

  Widget _step(
    LessonPracticeState s,
    int i,
    bool blocked, {
    bool tight = false,
  }) {
    final a = s.activities[i];
    final ok = s.passed.contains(a.id);
    final on = i == _index;
    final locked = s.activities.take(i).any((p) => !s.passed.contains(p.id));
    final label = _kindLabel(a);
    return V3Pressable(
      onTap: locked || blocked ? null : () => _selectActivity(i),
      selected: on,
      semanticLabel: locked
          ? '$label, locked until the case before it is accepted'
          : ok
          ? '$label, accepted'
          : label,
      child: Opacity(
        opacity: on ? 1 : .6,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok
                    ? AppColors.sage
                    : on
                    ? AppColors.ink
                    : AppColors.paper2,
              ),
              child: ok
                  ? const V3Icon(
                      V3Icons.check,
                      size: 13,
                      strokeWidth: 3,
                      color: Colors.white,
                    )
                  : locked
                  ? const V3Icon(V3Icons.lock, size: 12, color: AppColors.ink3)
                  : Text(
                      '${i + 1}',
                      style: AppTypography.sans(
                        12,
                        FontWeight.w700,
                      ).copyWith(color: on ? Colors.white : AppColors.ink3),
                    ),
            ),
            const SizedBox(width: 8),
            if (tight)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: _stepLabelStyle,
                ),
              )
            else
              Text(label, style: _stepLabelStyle),
          ],
        ),
      ),
    );
  }

  String _kindLabel(PracticeActivity a) =>
      a.isTransfer ? 'Independent' : 'Guided';

  // ── footer ────────────────────────────────────────────────────────────────

  Widget _prepareButton(LessonPracticeState? s) {
    final waiting = s?.state == 'preparing';
    return V3Button(
      full: true,
      onPressed: _busy || (!waiting && s?.canRetry == false)
          ? null
          : waiting
          ? _load
          : _prepare,
      child: Text(
        _busy
            ? 'Preparing exercises…'
            : waiting
            ? 'Check preparation status'
            : s?.canRetry == false
            ? 'Try again later'
            : 'Prepare practice',
      ),
    );
  }

  /// Submit for checking / Checking / Revise answer / Continue to
  /// independent case / Finish tutorial.
  Widget _cta(
    LessonPracticeState s,
    PracticeActivity a,
    Map<String, dynamic>? attempt,
    _Phase phase,
    bool blocked,
  ) {
    switch (phase) {
      case _Phase.checking:
        return const V3Button(
          full: true,
          kind: V3ButtonKind.dark,
          loading: true,
          semanticLabel: 'Checking',
          onPressed: null,
          child: Text('Checking'),
        );
      case _Phase.edit:
        final filled = a.fields.every(
          (f) => f.isFilled(_text(a, f), decimalSeparator: _decimal),
        );
        return V3Button(
          full: true,
          icon: V3Icons.check,
          // Disabled while a hint is in flight: both would send the same
          // revision, and one would 409.
          onPressed: filled && !blocked && !s.complete && _hinting == null
              ? _submit
              : null,
          child: const Text('Submit for checking'),
        );
      case _Phase.result:
        final verdicts = _verdicts(a, attempt, passed: s.passed.contains(a.id));
        if (!verdicts.every((v) => v.met)) {
          return V3Button(
            full: true,
            kind: V3ButtonKind.dark,
            icon: V3Icons.edit,
            onPressed: blocked || s.complete
                ? null
                : () => setState(() {
                    _revising = true;
                    _showSolution = false;
                  }),
            child: const Text('Revise answer'),
          );
        }
        if (_index < s.activities.length - 1) {
          return V3Button(
            full: true,
            iconRight: V3Icons.arrowR,
            onPressed: blocked ? null : () => _selectActivity(_index + 1),
            child: Text(
              s.activities[_index + 1].isTransfer
                  ? 'Continue to independent case'
                  : 'Continue to the next case',
            ),
          );
        }
        return V3Button(
          full: true,
          kind: V3ButtonKind.sage,
          icon: V3Icons.trophy,
          onPressed: blocked || !s.complete || _dirty ? null : _finish,
          child: Text('Finish $_unit'),
        );
    }
  }

  // ── body ──────────────────────────────────────────────────────────────────

  Widget _reviewingNote() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your saved answer is being checked.',
            style: AppTypography.sans(
              14,
            ).copyWith(color: AppColors.ink2, height: 1.45),
          ),
          const SizedBox(height: 10),
          V3Button(
            size: V3Size.sm,
            kind: V3ButtonKind.line,
            onPressed: _busy ? null : _load,
            child: const Text('Refresh check status'),
          ),
        ],
      ),
    ),
  );

  Widget _errorNote() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: v3Card(
        color: AppColors.dangerSoft,
        borderColor: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: AppTypography.sans(
                13.5,
              ).copyWith(color: AppColors.ink, height: 1.45),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_dirty)
                V3Button(
                  size: V3Size.sm,
                  kind: V3ButtonKind.dark,
                  onPressed: _busy ? null : () => _save(),
                  child: const Text('Retry save'),
                ),
              V3Button(
                size: V3Size.sm,
                kind: V3ButtonKind.line,
                onPressed: _busy || _saving ? null : _reloadSaved,
                child: const Text('Reload saved version'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _notReady(LessonPracticeState? s) {
    final waiting = s?.state == 'preparing';
    final retryMinutes = ((s?.retryAfterSeconds ?? 0) / 60).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          widget.lessonTitle,
          style: AppTypography.sans(13).copyWith(color: AppColors.ink3),
        ),
        const SizedBox(height: 8),
        Text(
          s?.title ?? 'Put the $_unit into practice',
          style: AppTypography.sans(
            24,
            FontWeight.w600,
          ).copyWith(color: AppColors.ink, letterSpacing: -.48),
        ),
        const SizedBox(height: 10),
        Text(
          _preparing
              ? 'You can return to the $_unit while these exercises prepare.'
              : waiting
              ? 'Your exercises are still preparing. Check their status in a moment.'
              : s?.canRetry == false
              ? retryMinutes > 0
                    ? 'Practice is taking longer than expected. Try again in about $retryMinutes ${retryMinutes == 1 ? 'minute' : 'minutes'}.'
                    : 'Practice is not ready yet. Check its status again later.'
              : s?.state == 'failed'
              ? 'This practice needs another preparation attempt.'
              : 'Work through a case, check your reasoning, then try a new problem. Your answers will be saved here.',
          style: AppTypography.sans(
            14.5,
          ).copyWith(color: AppColors.ink2, height: 1.5),
        ),
        if (!_busy && !waiting && s?.canRetry == false) ...[
          const SizedBox(height: 16),
          V3Button(
            size: V3Size.md,
            kind: V3ButtonKind.line,
            onPressed: _load,
            child: const Text('Check availability'),
          ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: V3Spinner(color: AppColors.ink3)),
          ),
      ],
    );
  }

  Widget _activity(
    LessonPracticeState s,
    PracticeActivity a,
    Map<String, dynamic>? attempt,
    _Phase phase,
    bool blocked,
  ) {
    final passed = s.passed.contains(a.id);
    final attempts = s.attemptsFor(a.id);
    final total = a.fields.length;
    final verdicts = _verdicts(a, attempt, passed: passed);
    // While checking, a field shows its verdict once its criterion ticks.
    final shown = switch (phase) {
      _Phase.edit => 0,
      _Phase.checking => _ticks,
      _Phase.result => total,
    };
    final editable = phase == _Phase.edit && !blocked && !s.complete;
    final canSolve = a.isTransfer ? passed : attempts.isNotEmpty;
    final solution = _solutionFor(s, a);
    final guided = !a.isTransfer;
    final legacyHints = [
      for (final h in s.hints)
        if (h['activity_id'] == a.id &&
            h['field_id'] == null &&
            (h['kind'] == null || h['kind'] == 'hint'))
          h['content'] as String? ?? '',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phase != _Phase.edit)
          _ResultPanel(
            criteria: [
              for (var i = 0; i < total; i++)
                (id: a.fields[i].id, verdict: verdicts[i]),
            ],
            ticks: shown,
            checking: phase == _Phase.checking,
          ),
        if (attempts.isNotEmpty && phase != _Phase.checking)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'Attempts',
                    style: AppTypography.sans(
                      12,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink3),
                  ),
                  const SizedBox(width: 8),
                  for (var i = 0; i < attempts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _attemptChip(a, i, attempts[i]),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: V3Tag(
            color: guided ? AppColors.iris2 : AppColors.ember2,
            background: guided ? AppColors.irisSoft : AppColors.emberSoft,
            child: Text(_kindLabel(a)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          a.title,
          style: AppTypography.sans(
            24,
            FontWeight.w600,
          ).copyWith(color: AppColors.ink, letterSpacing: -.48, height: 1.2),
        ),
        const SizedBox(height: 6),
        CmpysMarkdown(a.instructions, fontSize: 14.5, lineHeight: 1.5),
        for (final hint in legacyHints) ...[
          const SizedBox(height: 10),
          _goldPanel(hint),
        ],
        if (a.diagram != null) ...[const SizedBox(height: 14), _diagram(a)],
        if (a.data.isNotEmpty) ...[const SizedBox(height: 14), _dataTable(a)],
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
          child: Text('YOUR ANSWERS', style: AppTypography.kick),
        ),
        AnimatedOpacity(
          opacity: phase == _Phase.checking ? .5 : 1,
          duration: MotionConfig.enabled(context)
              ? const Duration(milliseconds: 300)
              : Duration.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _fieldCard(
                  s,
                  a,
                  a.fields[i],
                  verdict: i < shown ? verdicts[i] : null,
                  phase: phase,
                  editable: editable,
                  blocked: blocked,
                ),
              ],
            ],
          ),
        ),
        if (phase == _Phase.result && canSolve)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                V3Pressable(
                  onTap: blocked ? null : () => _toggleSolution(a),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const V3Icon(
                        V3Icons.eye,
                        size: 16,
                        color: AppColors.iris2,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showSolution
                            ? 'Hide worked solution'
                            : 'Show worked solution',
                        style: AppTypography.sans(
                          14,
                          FontWeight.w600,
                        ).copyWith(color: AppColors.iris2),
                      ),
                    ],
                  ),
                ),
                if (_showSolution && solution != null)
                  V3Rise(
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: v3Card(
                        color: AppColors.irisSoft,
                        borderColor: Colors.transparent,
                      ),
                      child: CmpysMarkdown(
                        solution,
                        fontSize: 15,
                        lineHeight: 1.6,
                        readerTheme: ReaderTheme.light,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (a.isTransfer && !passed)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const V3Icon(V3Icons.lock, size: 14, color: AppColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The worked solution for this case appears only after it is accepted.',
                    style: AppTypography.sans(
                      12.5,
                    ).copyWith(color: AppColors.ink3, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        if (s.complete && !_dirty && _index == s.activities.length - 1)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              s.evidenceStatus == 'transfer_without_hint'
                  ? 'New case passed without an in-app hint. This result can guide future ${_unit}s.'
                  : s.evidenceStatus == 'completed_with_support'
                  ? 'Practice completed with support on the new case. Future ${_unit}s can include another independent check.'
                  : 'Practice completed. You can return to finish the $_unit.',
              style: AppTypography.sans(
                13.5,
              ).copyWith(color: AppColors.ink2, height: 1.45),
            ),
          ),
      ],
    );
  }

  Widget _attemptChip(
    PracticeActivity a,
    int index,
    Map<String, dynamic> attempt,
  ) {
    final total = a.fields.length;
    final score = _verdicts(a, attempt).where((v) => v.met).length;
    final all = score == total;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hair),
      ),
      child: V3Tag(
        background: all ? AppColors.sageSoft : AppColors.card,
        color: all ? AppColors.sage2 : AppColors.ink2,
        child: Text('#${index + 1} · $score/$total', style: AppTypography.tnum),
      ),
    );
  }

  Widget _goldPanel(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: AppTypography.sans(
        13.5,
      ).copyWith(color: AppColors.gold2, height: 1.45),
    ),
  );

  Widget _diagram(PracticeActivity a) {
    final caption = a.diagram!['caption'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: v3Card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: caption,
            image: true,
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: CustomPaint(
                painter: _GeometryPainter(
                  a.diagram!,
                  AppColors.ink,
                  AppTypography.geist,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: AppTypography.sans(13).copyWith(color: AppColors.ink2),
          ),
          Text(
            'Schematic · not to scale',
            style: AppTypography.sans(11).copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  /// The case's figures; a "…" row is a breakdown of the row above it.
  Widget _dataTable(PracticeActivity a) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: v3Card(),
    child: Column(
      children: [
        for (var i = 0; i < a.data.length; i++)
          _dataRow(a.data[i], first: i == 0),
      ],
    ),
  );

  Widget _dataRow(Map<String, dynamic> d, {required bool first}) {
    final label = '${d['label'] ?? ''}';
    final sub = label.startsWith('…') || label.startsWith('...');
    final style = AppTypography.sans(
      14.5,
    ).copyWith(color: sub ? AppColors.ink2 : AppColors.ink);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: sub ? 12 : 0),
              child: Text(label, style: style),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _dataValue(d),
            style: AppTypography.sans(
              14.5,
              FontWeight.w600,
            ).merge(AppTypography.tnum).copyWith(color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  static String _dataValue(Map<String, dynamic> d) {
    final value = d['value'];
    final unit = '${d['unit'] ?? ''}'.trim();
    final text = value is num
        ? (value == value.roundToDouble() && value.abs() < 1e15
              ? value.toInt().toString()
              : value.toString())
        : '${value ?? ''}';
    if (unit.isEmpty) return text;
    return unit.startsWith('%') ? '$text$unit' : '$text $unit';
  }

  // ── answers ───────────────────────────────────────────────────────────────

  Widget _fieldCard(
    LessonPracticeState s,
    PracticeActivity a,
    PracticeField f, {
    required _Verdict? verdict,
    required _Phase phase,
    required bool editable,
    required bool blocked,
  }) {
    final key = '${a.id}.${f.id}';
    final hint = s.fieldHint(key);
    final used = hint != null;
    return AnimatedContainer(
      key: ValueKey('field-card-$key'),
      duration: MotionConfig.enabled(context)
          ? const Duration(milliseconds: 400)
          : Duration.zero,
      padding: const EdgeInsets.all(14),
      decoration: v3Card(
        borderColor: verdict == null
            ? AppColors.hair
            : verdict.met
            ? AppColors.sage
            : _danger,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    f.label,
                    style: AppTypography.sans(
                      14,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink, height: 1.4),
                  ),
                ),
              ),
              if (phase == _Phase.edit) ...[
                const SizedBox(width: 8),
                // A tap here is not "outside" a field: the keyboard stays up.
                TextFieldTapRegion(
                  child: V3Pressable(
                    onTap: used || blocked || _hinting != null
                        ? null
                        : () => _hint(a, f),
                    semanticLabel: used
                        ? 'Hint used'
                        : _hinting == key
                        ? 'Loading hint'
                        : 'Hint for ${f.label}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hinting == key)
                          const V3Spinner(
                            key: ValueKey('hint-loading'),
                            size: 14,
                            color: AppColors.ink3,
                            semanticLabel: null,
                          )
                        else
                          V3Icon(
                            V3Icons.hint,
                            size: 14,
                            color: used ? AppColors.gold2 : AppColors.ink3,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          used ? 'Hint used' : 'Hint',
                          style: AppTypography.sans(12.5, FontWeight.w600)
                              .copyWith(
                                color: used ? AppColors.gold2 : AppColors.ink3,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (used)
            V3Rise(
              duration: const Duration(milliseconds: 400),
              offset: 8,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _goldPanel(hint),
              ),
            ),
          const SizedBox(height: 10),
          if (f.isNumber)
            _numberInput(key, f, editable)
          else if (f.isChoice)
            _choiceGrid(key, f, editable)
          else if (f.isMultiChoice)
            _checkGrid(key, f, editable)
          else
            _textInput(key, f, editable),
        ],
      ),
    );
  }

  Widget _numberInput(String key, PracticeField f, bool editable) {
    final muted = AppTypography.sans(18).copyWith(color: AppColors.ink3);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (f.prefix.isNotEmpty) ...[
            Text(f.prefix, style: muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Semantics(
              label: f.label,
              child: TextField(
                key: ValueKey('answer-$key'),
                controller: _controllers[key],
                enabled: editable,
                onChanged: _changed,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-−\s]')),
                  LengthLimitingTextInputFormatter(80),
                ],
                cursorColor: AppColors.ink,
                style: AppTypography.sans(
                  20,
                  FontWeight.w600,
                ).merge(AppTypography.tnum).copyWith(color: AppColors.ink),
                decoration: InputDecoration.collapsed(
                  hintText: '0',
                  hintStyle: AppTypography.sans(
                    20,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink3.withValues(alpha: .5)),
                ),
              ),
            ),
          ),
          if (f.unit.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              f.unit,
              style: AppTypography.sans(14).copyWith(color: AppColors.ink3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textInput(String key, PracticeField f, bool editable) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Semantics(
      label: f.label,
      child: TextField(
        key: ValueKey('answer-$key'),
        controller: _controllers[key],
        enabled: editable,
        onChanged: _changed,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        keyboardType: TextInputType.multiline,
        minLines: 3,
        maxLines: 10,
        inputFormatters: [LengthLimitingTextInputFormatter(8000)],
        cursorColor: AppColors.ink,
        style: AppTypography.sans(
          15,
        ).copyWith(color: AppColors.ink, height: 1.45),
        decoration: InputDecoration.collapsed(
          hintText: 'Write in your own words',
          hintStyle: AppTypography.sans(
            15,
          ).copyWith(color: AppColors.ink3, height: 1.45),
        ),
      ),
    ),
  );

  /// One choice: 2-column buttons, ink when picked.
  Widget _choiceGrid(String key, PracticeField f, bool editable) {
    final picked = _controllers[key]!.text;
    return _twoColumns([
      for (final c in f.choices)
        _ChoiceTile(
          label: '${c['label']}',
          on: picked == c['id'],
          onTap: editable
              ? () {
                  _controllers[key]!.text = c['id'] as String;
                  _changed();
                }
              : null,
        ),
    ]);
  }

  /// Several choices: a 2-column check grid, sent in canonical order.
  Widget _checkGrid(String key, PracticeField f, bool editable) {
    final selected = f.selectedIds(_controllers[key]!.text);
    return _twoColumns([
      for (final c in f.choices)
        _ChoiceTile(
          label: '${c['label']}',
          on: selected.contains(c['id']),
          multi: true,
          onTap: editable
              ? () {
                  final id = c['id'] as String;
                  final ids = f.selectedIds(_controllers[key]!.text);
                  ids.contains(id) ? ids.remove(id) : ids.add(id);
                  _controllers[key]!.text = f.canonicalMultiChoice(
                    ids.join(','),
                  );
                  _changed();
                }
              : null,
        ),
    ]);
  }

  Widget _twoColumns(List<Widget> tiles) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          // Tiles in a row share the taller one's height (as quick_check).
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < tiles.length
                      ? tiles[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.on,
    required this.onTap,
    this.multi = false,
  });
  final String label;
  final bool on, multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : AppColors.ink;
    final text = Text(
      label,
      textAlign: multi ? TextAlign.start : TextAlign.center,
      style: AppTypography.sans(
        14,
        FontWeight.w600,
      ).copyWith(color: fg, height: 1.3),
    );
    return V3Pressable(
      onTap: onTap,
      selected: multi ? null : on,
      checked: multi ? on : null,
      focusRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: MotionConfig.enabled(context)
            ? const Duration(milliseconds: 250)
            : Duration.zero,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: multi ? Alignment.centerLeft : Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.ink : AppColors.paper,
          borderRadius: BorderRadius.circular(14),
        ),
        child: multi
            ? Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: on
                          ? null
                          : Border.all(color: AppColors.hair2, width: 1.5),
                    ),
                    child: on
                        ? const V3Icon(
                            V3Icons.check,
                            size: 13,
                            strokeWidth: 3,
                            color: AppColors.ink,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: text),
                ],
              )
            : text,
      ),
    );
  }
}

/// `ResultPanel` from `v3/practice.jsx`: night while checking, with the
/// criteria ticking one by one; then the ring, "Accepted" or "n of m
/// criteria met", and each criterion's feedback.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.criteria,
    required this.ticks,
    required this.checking,
  });
  final List<({String id, _Verdict verdict})> criteria;

  /// How many criteria have ticked (all of them once checked).
  final int ticks;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final n = criteria.length;
    final score = criteria.where((c) => c.verdict.met).length;
    final all = score == n;
    final motion = MotionConfig.enabled(context);
    final ink = checking ? Colors.white : AppColors.ink;
    return AnimatedContainer(
      duration: motion ? const Duration(milliseconds: 600) : Duration.zero,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: checking
            ? AppColors.night
            : all
            ? AppColors.sageSoft
            : AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: checking || all ? null : Border.all(color: AppColors.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              V3Ring(
                value: n == 0 ? 0 : (checking ? ticks / n : score / n),
                size: 58,
                strokeWidth: 5,
                color: checking
                    ? AppColors.ember
                    : all
                    ? AppColors.sage2
                    : AppColors.gold,
                track: checking
                    ? const Color(0x1FFFFFFF)
                    : const Color(0x12000000),
                child: checking
                    ? const V3Spinner(size: 18, color: Colors.white)
                    : Text(
                        '$score/$n',
                        style: AppTypography.sans(16, FontWeight.w700)
                            .merge(AppTypography.tnum)
                            .copyWith(color: AppColors.ink),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        checking
                            ? 'Checking against criteria'
                            : all
                            ? 'Accepted'
                            : '$score of $n criteria met',
                        style: AppTypography.sans(
                          17,
                          FontWeight.w600,
                        ).copyWith(color: ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        checking
                            ? 'Your draft is saved while this runs'
                            : all
                            ? 'Saved with your attempt history'
                            : 'Revise and resubmit. This attempt stays in your history.',
                        style: AppTypography.sans(12.5).copyWith(
                          color: checking ? AppColors.nink3 : AppColors.ink2,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (all && !checking)
                const SizedBox(
                  width: 0,
                  height: 0,
                  child: V3Burst(color: AppColors.sage, radius: 40, count: 12),
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < n; i++)
            _CriterionRow(
              id: criteria[i].id,
              verdict: criteria[i].verdict,
              shown: i < ticks,
              current: checking && i == ticks,
              checking: checking,
            ),
        ],
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({
    required this.id,
    required this.verdict,
    required this.shown,
    required this.current,
    required this.checking,
  });
  final String id;
  final _Verdict verdict;
  final bool shown, current, checking;

  @override
  Widget build(BuildContext context) {
    final met = verdict.met;
    final state = !shown
        ? 'pending'
        : met
        ? 'met'
        : 'missed';
    final ink = checking ? Colors.white : AppColors.ink;
    return Container(
      key: ValueKey('criterion-$id-$state'),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: checking ? const Color(0x14FFFFFF) : const Color(0x0F000000),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !shown
                  ? Colors.transparent
                  : met
                  ? AppColors.sage
                  : _danger,
              border: shown
                  ? null
                  : Border.all(
                      width: 1.5,
                      color: checking
                          ? const Color(0x33FFFFFF)
                          : AppColors.hair2,
                    ),
            ),
            child: shown
                ? V3Pop(
                    child: V3Icon(
                      met ? V3Icons.check : V3Icons.x,
                      size: 12,
                      strokeWidth: 3,
                      color: Colors.white,
                      semanticLabel: met ? 'Met' : 'Not met',
                    ),
                  )
                : current
                ? const V3Spinner(size: 11, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: shown || !checking ? 1 : .55,
                  child: Text(
                    verdict.label,
                    style: AppTypography.sans(
                      14,
                      FontWeight.w600,
                    ).copyWith(color: ink, height: 1.35),
                  ),
                ),
                if (shown && !checking && verdict.feedback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      verdict.feedback!,
                      style: AppTypography.sans(
                        13,
                      ).copyWith(color: AppColors.ink2, height: 1.45),
                    ),
                  ),
                if (shown && !checking)
                  for (final (ok, line) in verdict.rubric)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${ok ? '✓' : '○'} $line',
                        style: AppTypography.sans(
                          12,
                        ).copyWith(color: AppColors.ink3, height: 1.45),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Leave practice?" sheet.
///
/// - A save still in flight ([pending]): the design's "Wait a moment" copy.
///   When that save lands the sheet closes itself with [_Leave.saved], but
///   only while it is still the top route, so a save that lands after "Keep
///   editing" or "Leave without saving" never pops anything else.
/// - A save that already failed (no [pending]): "Retry" tries it again.
class _LeaveSheet extends StatefulWidget {
  const _LeaveSheet({this.pending});
  final Future<bool>? pending;

  @override
  State<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends State<_LeaveSheet> {
  @override
  void initState() {
    super.initState();
    widget.pending?.then((saved) {
      if (!saved || !mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.of(context).pop(_Leave.saved);
    });
  }

  @override
  Widget build(BuildContext context) => widget.pending != null
      ? _SheetChoice(
          message:
              'Your last change hasn’t saved yet. Wait a moment, or leave without it.',
          primary: 'Keep editing',
          onPrimary: () => Navigator.of(context).pop(),
          secondary: 'Leave without saving',
          onSecondary: () => Navigator.of(context).pop(_Leave.discard),
        )
      : _SheetChoice(
          message: 'Couldn’t save — try again, or leave without it.',
          primary: 'Retry',
          onPrimary: () => Navigator.of(context).pop(_Leave.retry),
          secondary: 'Leave without saving',
          onSecondary: () => Navigator.of(context).pop(_Leave.discard),
        );
}

/// A sheet body: a message, a dark primary button and a ghost secondary.
class _SheetChoice extends StatelessWidget {
  const _SheetChoice({
    required this.message,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
  });
  final String message, primary, secondary;
  final VoidCallback onPrimary, onSecondary;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        message,
        style: AppTypography.sans(
          14.5,
        ).copyWith(color: AppColors.ink2, height: 1.5),
      ),
      const SizedBox(height: 18),
      V3Button(
        full: true,
        kind: V3ButtonKind.dark,
        onPressed: onPrimary,
        child: Text(primary),
      ),
      const SizedBox(height: 8),
      V3Button(
        full: true,
        kind: V3ButtonKind.ghost,
        onPressed: onSecondary,
        child: Text(secondary),
      ),
    ],
  );
}

class _GeometryPainter extends CustomPainter {
  _GeometryPainter(this.diagram, this.ink, this.fontFamily);
  final Map<String, dynamic> diagram;
  final Color ink;
  final String? fontFamily;
  @override
  void paint(Canvas canvas, Size size) {
    final points = (diagram['points'] as List).cast<Map<String, dynamic>>();
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final point = Offset(
        24 + (p['x'] as num) / 100 * (size.width - 48),
        24 + (p['y'] as num) / 100 * (size.height - 48),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3, Paint()..color = ink);
      final label = TextPainter(
        text: TextSpan(
          text: p['label'] as String,
          style: TextStyle(color: ink, fontSize: 13, fontFamily: fontFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      label.paint(
        canvas,
        Offset(
          (point.dx + 6).clamp(0, size.width - label.width),
          (point.dy - 20).clamp(0, size.height - label.height),
        ),
      );
    }
    if (diagram['closed'] == true) path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GeometryPainter oldDelegate) =>
      oldDelegate.diagram != diagram ||
      oldDelegate.ink != ink ||
      oldDelegate.fontFamily != fontFamily;
}
