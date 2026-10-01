import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../data/practice_repository.dart';
import '../models/practice_models.dart';

/// A workspace, not a chat: every answer belongs to an explicit exercise.
class LessonPracticeScreen extends ConsumerStatefulWidget {
  const LessonPracticeScreen({
    super.key,
    required this.itemId,
    required this.stepId,
    required this.lessonTitle,
    required this.lessonContent,
    this.artifactJobId,
    this.dark = false,
  });
  final String itemId, stepId, lessonTitle, lessonContent;
  final String? artifactJobId;
  final bool dark;
  @override
  ConsumerState<LessonPracticeScreen> createState() =>
      _LessonPracticeScreenState();
}

class _LessonPracticeScreenState extends ConsumerState<LessonPracticeScreen>
    with WidgetsBindingObserver {
  LessonPracticeState? _state;
  final _controllers = <String, TextEditingController>{};
  final _scroll = ScrollController();
  Timer? _debounce;
  Timer? _preparationPollTimer;
  Completer<void>? _preparationPollWait;
  Future<bool>? _saveFlight;
  bool _loading = true, _busy = false, _dirty = false, _saving = false;
  bool _preparing = false;
  int _editVersion = 0, _index = 0;
  String? _error;
  PracticeRepository get _repo => ref.read(practiceRepositoryProvider);
  Color get _ink => widget.dark ? const Color(0xFFF2F0EA) : AppColors.ink;
  Color get _muted => widget.dark ? const Color(0xFFB6B6C0) : AppColors.ink3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
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
    if (_index >= result.activities.length) _index = 0;
    final firstIncomplete = result.activities.indexWhere(
      (a) => !result.passed.contains(a.id),
    );
    if (firstIncomplete >= 0 && _index > firstIncomplete) {
      _index = firstIncomplete;
    }
  }

  Future<void> _load({bool discardLocal = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.load(
        widget.itemId,
        widget.stepId,
        widget.artifactJobId,
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
          await _repo.prepare(
            widget.itemId,
            widget.stepId,
            widget.artifactJobId,
          );
      // Another client may already own preparation. Poll without another paid POST.
      // Cover its 120-second lease while allowing the user to leave at any time.
      for (var i = 0; result.state == 'preparing' && i < 24 && mounted; i++) {
        await _waitForPreparationPoll();
        if (!mounted) return;
        result = await _repo.load(
          widget.itemId,
          widget.stepId,
          widget.artifactJobId,
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

  void _changed(String _) {
    setState(() {
      _dirty = true;
      _editVersion++;
      _error = null;
    });
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(_save()),
    );
  }

  void _selectActivity(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _index = index);
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
        final version = _editVersion;
        final answers = {
          for (final e in _controllers.entries) e.key: e.value.text,
        };
        final result = await _repo.save(
          widget.itemId,
          widget.stepId,
          widget.artifactJobId,
          _state!.revision,
          answers,
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

  Future<void> _act(String action, {bool solution = false}) async {
    if (_busy || _state == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _save() || !mounted) return;
      final a = _state!.activities[_index];
      final result = await _repo.act(
        widget.itemId,
        widget.stepId,
        widget.artifactJobId,
        action: action,
        revision: _state!.revision,
        activity: a.id,
        requestId:
            '${DateTime.now().microsecondsSinceEpoch}_${_state!.revision}',
        solution: solution,
      );
      if (mounted) setState(() => _accept(result));
    } catch (_) {
      // Recover a committed response after a transport timeout. The server
      // also deduplicates unchanged answer snapshots before charging again.
      try {
        final result = await _repo.load(
          widget.itemId,
          widget.stepId,
          widget.artifactJobId,
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave({bool completed = false}) async {
    // Preparation cannot change an answer: leaving it is safe. Answer review
    // and pending saves retain their existing protection against lost work.
    if (_busy && !_preparing) return;
    if (!await _save() || !mounted) return;
    Navigator.of(context).pop(completed && (_state?.complete ?? false));
  }

  Future<void> _reloadSaved() async {
    if (_dirty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Reload saved work?'),
          content: const Text(
            'This replaces the unsaved changes on this screen with the latest saved answers.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _debounce?.cancel();
    await _load(discardLocal: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final blocked = _busy || state?.state == 'reviewing';
    final waitingOnServer = state?.state == 'preparing';
    final retryMinutes = ((state?.retryAfterSeconds ?? 0) / 60).ceil();
    return PopScope(
      canPop: !_dirty && !_saving && (!_busy || _preparing),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Theme(
        data: widget.dark
            ? ThemeData.dark().copyWith(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: AppColors.green,
                  brightness: Brightness.dark,
                ),
              )
            : Theme.of(context),
        child: Scaffold(
          backgroundColor: widget.dark
              ? const Color(0xFF1B1C21)
              : const Color(0xFFFAFAF8),
          appBar: AppBar(
            backgroundColor: widget.dark
                ? const Color(0xFF1B1C21)
                : const Color(0xFFFAFAF8),
            foregroundColor: _ink,
            leading: IconButton(
              tooltip: 'Back to lesson',
              onPressed: _busy && !_preparing ? null : () => _leave(),
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text('Practice', style: TextStyle(color: _ink)),
            actions: [
              IconButton(
                tooltip: 'Refer to lesson',
                onPressed: _showLesson,
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.lessonTitle,
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state?.title ?? 'Put the lesson into practice',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (state?.state == 'reviewing') ...[
                            Text(
                              'Your saved answer is being checked.',
                              style: TextStyle(color: _muted),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _load,
                              child: const Text('Refresh check status'),
                            ),
                          ],
                          if (_error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: widget.dark
                                      ? Colors.orangeAccent
                                      : Colors.brown,
                                ),
                              ),
                            ),
                            Wrap(
                              spacing: 12,
                              children: [
                                if (_dirty)
                                  TextButton(
                                    onPressed: _busy ? null : () => _save(),
                                    child: const Text('Retry save'),
                                  ),
                                TextButton(
                                  onPressed: _busy || _saving
                                      ? null
                                      : _reloadSaved,
                                  child: const Text('Reload saved version'),
                                ),
                              ],
                            ),
                          ],
                          if (state == null || state.activities.isEmpty) ...[
                            Text(
                              _preparing
                                  ? 'You can return to the lesson while these exercises prepare.'
                                  : waitingOnServer
                                  ? 'Your exercises are still preparing. Check their status in a moment.'
                                  : state?.canRetry == false
                                  ? retryMinutes > 0
                                        ? 'Practice is taking longer than expected. Try again in about $retryMinutes ${retryMinutes == 1 ? 'minute' : 'minutes'}.'
                                        : 'Practice is not ready yet. Check its status again later.'
                                  : state?.state == 'failed'
                                  ? 'This practice needs another preparation attempt.'
                                  : 'Work through a case, check your reasoning, then try a new problem. Your answers will be saved here.',
                              style: TextStyle(color: _muted, height: 1.5),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed:
                                  _busy ||
                                      (!waitingOnServer &&
                                          state?.canRetry == false)
                                  ? null
                                  : waitingOnServer
                                  ? _load
                                  : _prepare,
                              child: Text(
                                _busy
                                    ? 'Preparing exercises…'
                                    : waitingOnServer
                                    ? 'Check preparation status'
                                    : state?.canRetry == false
                                    ? 'Try again later'
                                    : 'Prepare practice',
                              ),
                            ),
                            if (!_busy &&
                                !waitingOnServer &&
                                state?.canRetry == false)
                              TextButton(
                                onPressed: _load,
                                child: const Text('Check availability'),
                              ),
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ] else ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _saving
                                    ? 'Saving…'
                                    : _dirty
                                    ? 'Unsaved changes'
                                    : 'All answers saved',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (
                                  var i = 0;
                                  i < state.activities.length;
                                  i++
                                )
                                  ChoiceChip(
                                    showCheckmark: false,
                                    label: Text(
                                      '${i + 1}${state.passed.contains(state.activities[i].id) ? ' ✓' : ''}',
                                    ),
                                    selected: _index == i,
                                    onSelected:
                                        blocked ||
                                            state.activities
                                                .take(i)
                                                .any(
                                                  (a) => !state.passed.contains(
                                                    a.id,
                                                  ),
                                                )
                                        ? null
                                        : (_) => _selectActivity(i),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            ..._exercise(
                              state,
                              state.activities[_index],
                              blocked || state.complete,
                            ),
                            if (state.complete && !_dirty) ...[
                              const SizedBox(height: 24),
                              Text(
                                state.evidenceStatus == 'transfer_without_hint'
                                    ? 'New case passed without an in-app hint. This result can guide future lessons.'
                                    : state.evidenceStatus ==
                                          'completed_with_support'
                                    ? 'Practice completed with support on the new case. Future lessons can include another independent check.'
                                    : 'Practice completed. You can return to finish the lesson.',
                                style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: blocked
                                    ? null
                                    : () => _leave(completed: true),
                                icon: const Icon(Icons.check),
                                label: const Text('Finish lesson'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _exercise(
    LessonPracticeState state,
    PracticeActivity a,
    bool blocked,
  ) {
    final attempts = state.attempts
        .where((x) => x['activity_id'] == a.id)
        .toList();
    final attempt = attempts.isEmpty ? null : attempts.last;
    final matches =
        attempt != null &&
        a.fields.every(
          (f) =>
              (attempt['answers'] as Map)[f.id] ==
              _controllers['${a.id}.${f.id}']!.text,
        );
    return [
      Text(
        a.kind == 'transfer'
            ? 'NEW CASE · APPLY IT YOURSELF'
            : 'WORK THROUGH THE CASE',
        style: TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        a.title,
        style: TextStyle(
          color: _ink,
          fontSize: 23,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'About ${a.minutesMin}–${a.minutesMax} minutes · preliminary estimate',
        style: TextStyle(color: _muted, fontSize: 12),
      ),
      const SizedBox(height: 16),
      CmpysMarkdown(a.instructions, onDark: widget.dark),
      if (a.diagram != null) ...[
        const SizedBox(height: 16),
        Semantics(
          label: a.diagram!['caption'] as String,
          image: true,
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: CustomPaint(
              painter: _GeometryPainter(
                a.diagram!,
                _ink,
                Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
            ),
          ),
        ),
        Text(a.diagram!['caption'] as String, style: TextStyle(color: _muted)),
        Text(
          'Schematic · not to scale',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
      if (a.data.isNotEmpty) ...[
        const SizedBox(height: 16),
        for (final d in a.data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    d['label'] as String,
                    style: TextStyle(color: _ink),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    '${d['value']} ${d['unit'] ?? ''}',
                    style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 28),
      ],
      for (final f in a.fields) ...[
        Text(
          f.label,
          style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (f.kind == 'choice')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in f.choices)
                ChoiceChip(
                  label: Text(choice['label'] as String, softWrap: true),
                  selected:
                      _controllers['${a.id}.${f.id}']!.text == choice['id'],
                  onSelected: blocked
                      ? null
                      : (_) {
                          _controllers['${a.id}.${f.id}']!.text =
                              choice['id'] as String;
                          _changed('');
                        },
                ),
            ],
          )
        else
          Semantics(
            label: f.label,
            child: TextField(
              key: ValueKey('answer-${a.id}.${f.id}'),
              controller: _controllers['${a.id}.${f.id}'],
              enabled: !blocked,
              onChanged: _changed,
              keyboardType: f.kind == 'number'
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.multiline,
              minLines: f.kind == 'text' ? 4 : 1,
              maxLines: f.kind == 'text' ? 10 : 1,
              maxLength: f.kind == 'text' ? 8000 : 80,
              style: TextStyle(color: _ink),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixText: f.unit.isEmpty ? null : f.unit,
                counterText: '',
                hintText: f.kind == 'text'
                    ? 'Explain your reasoning…'
                    : 'Your answer',
              ),
            ),
          ),
        const SizedBox(height: 20),
      ],
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed:
                blocked ||
                    a.fields.any(
                      (f) =>
                          _controllers['${a.id}.${f.id}']!.text.trim().isEmpty,
                    )
                ? null
                : () => _act('submit'),
            child: Text(_busy ? 'Checking…' : 'Check my work'),
          ),
          TextButton(
            onPressed: blocked ? null : () => _act('hint'),
            child: const Text('Get a hint'),
          ),
          if (attempts.isNotEmpty)
            TextButton(
              onPressed: blocked ? null : () => _act('hint', solution: true),
              child: const Text('Worked solution'),
            ),
        ],
      ),
      for (final hint in state.hints.where(
        (h) => h['activity_id'] == a.id,
      )) ...[
        const SizedBox(height: 16),
        CmpysMarkdown(hint['content'] as String, onDark: widget.dark),
      ],
      if (attempt != null) ...[
        const Divider(height: 32),
        Text(
          matches
              ? attempt['passed'] == true
                    ? 'This attempt meets the criteria'
                    : 'Revise and try again'
              : 'Feedback on your previous answer',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
        if (attempt['assisted'] == true)
          Text(
            'Completed with help · the next case checks transfer',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        for (final f
            in (attempt['feedback'] as List).cast<Map<String, dynamic>>())
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  f['passed'] == true
                      ? Icons.check_circle_outline
                      : Icons.edit_outlined,
                  size: 18,
                  color: _muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (f['score'] is num && f['max_score'] is num)
                        Text(
                          '${a.fields.firstWhere((field) => field.id == f['field_id']).label}: ${f['score']}/${f['max_score']}',
                          style: TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        f['feedback'] as String,
                        style: TextStyle(color: _ink, height: 1.5),
                      ),
                      if (f['criterion_met'] is List)
                        for (
                          var i = 0;
                          i < (f['criterion_met'] as List).length &&
                              i < (f['criteria'] as List? ?? const []).length;
                          i++
                        )
                          Text(
                            '${(f['criterion_met'] as List)[i] == true ? '✓' : '○'} ${(f['criteria'] as List)[i]}',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (attempts.length > 1)
          ExpansionTile(
            title: Text('${attempts.length} saved attempts'),
            children: [
              for (final old in attempts.reversed)
                ListTile(
                  title: Text(
                    old['passed'] == true ? 'Criteria met' : 'Needs revision',
                  ),
                  subtitle: Text((old['answers'] as Map).values.join('\n')),
                ),
            ],
          ),
      ],
      if (state.passed.contains(a.id) &&
          !_dirty &&
          _index < state.activities.length - 1)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: OutlinedButton(
            onPressed: blocked ? null : () => _selectActivity(_index + 1),
            child: const Text('Continue to the next case'),
          ),
        ),
    ];
  }

  Future<void> _showLesson() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: widget.dark
        ? const Color(0xFF1B1C21)
        : const Color(0xFFFAFAF8),
    builder: (c) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * .8,
        child: Column(
          children: [
            ListTile(
              title: Text('Lesson reference', style: TextStyle(color: _ink)),
              trailing: IconButton(
                tooltip: 'Close reference',
                onPressed: () => Navigator.pop(c),
                icon: Icon(Icons.close, color: _ink),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: CmpysMarkdown(widget.lessonContent, onDark: widget.dark),
              ),
            ),
          ],
        ),
      ),
    ),
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
