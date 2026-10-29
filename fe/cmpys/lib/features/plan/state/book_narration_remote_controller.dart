import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/book_narration.dart';

typedef BookNarrationRemoteAction = Future<void> Function();
typedef BookNarrationRemoteSeek = Future<void> Function(double progress);
typedef BookNarrationRemoteStyleChange =
    Future<void> Function(BookNarrationStyle style);
typedef BookNarrationRemoteSpeedChange = Future<void> Function(double speed);
typedef BookNarrationRemoteSkip = Future<void> Function(Duration delta);

/// The full player's speed button order (design `SP = [1, 1.25, 1.5, 2, .75]`).
const List<double> bookNarrationSpeedCycle = [1, 1.25, 1.5, 2, 0.75];

/// The speed after [speed] in [bookNarrationSpeedCycle]. A speed outside the
/// cycle starts it again at 1×, as `SP.indexOf` → -1 does in the design.
double nextBookNarrationSpeed(double speed) {
  final index = bookNarrationSpeedCycle.indexOf(speed);
  return bookNarrationSpeedCycle[(index + 1) % bookNarrationSpeedCycle.length];
}

/// App-scoped bridge between the active reader and playback controls rendered
/// elsewhere in the navigation tree.
///
/// Every state mutation is guarded by the reader's opaque [ownerToken]. A stale
/// reader can therefore neither overwrite nor release a newer listening session.
class BookNarrationRemoteController extends ChangeNotifier {
  Object? _ownerToken;
  BookNarrationRemoteAction? _onToggle;
  BookNarrationRemoteAction? _onPrevious;
  BookNarrationRemoteAction? _onNext;
  BookNarrationRemoteSeek? _onSeek;
  BookNarrationRemoteStyleChange? _onStyleChanged;
  BookNarrationRemoteSpeedChange? _onSpeedChanged;
  BookNarrationRemoteAction? _onStop;
  BookNarrationRemoteAction? _onReplaced;
  BookNarrationRemoteAction? _onChapters;
  BookNarrationRemoteSkip? _onSkip;
  final Map<Object, Future<void>> _ownerStops = Map.identity();

  bool _active = false;
  bool _playing = false;
  bool _preparing = false;
  double _progress = 0;
  String _semanticText = '';
  BookNarrationStyle _style = BookNarrationStyle.expressive;
  double _speed = 1;
  int? _branchIndex;
  String? _resourceId;
  String _title = '';
  String _author = '';
  int? _chapterIndex;
  String _chapterTitle = '';
  Duration _duration = Duration.zero;

  bool get active => _active;
  bool get playing => _playing;
  bool get preparing => _preparing;
  double get progress => _progress;
  String get semanticText => _semanticText;
  BookNarrationStyle get style => _style;
  double get speed => _speed;
  int? get branchIndex => _branchIndex;
  bool get hasOwner => _ownerToken != null;

  /// The book being narrated, so a Listen elsewhere can tell whether it is
  /// already the one playing.
  String? get resourceId => _resourceId;
  String get title => _title;

  /// Empty when the book has no known author.
  String get author => _author;

  /// Zero-based chapter being narrated, when known.
  int? get chapterIndex => _chapterIndex;
  String get chapterTitle => _chapterTitle;

  /// Listening time of the whole book at 1×. The reader estimates it from the
  /// narration text; zero when unknown.
  Duration get duration => _duration;

  /// [progress] as listening time of the book at 1×.
  Duration get elapsed => _duration * _progress;

  /// [elapsed] at the current [speed]: what a listener has heard so far in
  /// clock time (half of [elapsed] at 2×).
  Duration get listeningElapsed => _atSpeed(elapsed);

  /// [duration] at the current [speed].
  Duration get listeningDuration => _atSpeed(_duration);

  Duration _atSpeed(Duration time) => speed > 0 ? time * (1 / speed) : time;

  /// Whether the session offers a chapter list.
  bool get hasChapters => _onChapters != null;

  /// Whether [resourceId] is the book this session narrates.
  bool narrates(String resourceId) => active && this.resourceId == resourceId;

  /// Claims the remote for [ownerToken], replacing any older session.
  void attach({
    required Object ownerToken,
    required BookNarrationRemoteAction onToggle,
    required BookNarrationRemoteAction onPrevious,
    required BookNarrationRemoteAction onNext,
    required BookNarrationRemoteSeek onSeek,
    required BookNarrationRemoteStyleChange onStyleChanged,
    required BookNarrationRemoteSpeedChange onSpeedChanged,
    required BookNarrationRemoteAction onStop,
    BookNarrationRemoteAction? onReplaced,
    BookNarrationRemoteAction? onChapters,
    BookNarrationRemoteSkip? onSkip,
    bool active = true,
    bool playing = false,
    bool preparing = false,
    double progress = 0,
    String semanticText = '',
    BookNarrationStyle style = BookNarrationStyle.expressive,
    double speed = 1,
    int? branchIndex,
    String? resourceId,
    String title = '',
    String author = '',
    int? chapterIndex,
    String chapterTitle = '',
    Duration duration = Duration.zero,
  }) {
    final previousOwnerToken = _ownerToken;
    final previousStop = _onReplaced ?? _onStop;
    final replacingOwner =
        previousOwnerToken != null &&
        !identical(previousOwnerToken, ownerToken);

    // Publish the new ownership synchronously before invoking the old stop
    // callback. Any late update/release from the retired reader is rejected by
    // the token guard, while its audio teardown starts in this same call stack.
    _ownerToken = ownerToken;
    _onToggle = onToggle;
    _onPrevious = onPrevious;
    _onNext = onNext;
    _onSeek = onSeek;
    _onStyleChanged = onStyleChanged;
    _onSpeedChanged = onSpeedChanged;
    _onStop = onStop;
    _onReplaced = onReplaced;
    _onChapters = onChapters;
    _onSkip = onSkip;
    _active = active;
    _playing = playing;
    _preparing = preparing;
    _progress = _clampProgress(progress);
    _semanticText = semanticText.trim();
    _style = style;
    _speed = speed;
    _branchIndex = branchIndex;
    _resourceId = resourceId;
    _title = title.trim();
    _author = author.trim();
    _chapterIndex = chapterIndex;
    _chapterTitle = chapterTitle.trim();
    _duration = _clampDuration(duration);
    if (replacingOwner && previousStop != null) {
      unawaited(_retireOwner(previousOwnerToken, previousStop));
    }
    notifyListeners();
  }

  /// Updates the current session only when [ownerToken] still owns it.
  bool update({
    required Object ownerToken,
    bool? active,
    bool? playing,
    bool? preparing,
    double? progress,
    String? semanticText,
    BookNarrationStyle? style,
    double? speed,
    int? branchIndex,
    bool clearBranchIndex = false,
    String? title,
    String? author,
    int? chapterIndex,
    String? chapterTitle,
    Duration? duration,
  }) {
    if (!_owns(ownerToken)) return false;

    var changed = false;
    changed =
        _replaceBool(active, _active, (value) => _active = value) || changed;
    changed =
        _replaceBool(playing, _playing, (value) => _playing = value) || changed;
    changed =
        _replaceBool(preparing, _preparing, (value) => _preparing = value) ||
        changed;
    if (progress != null) {
      final nextProgress = _clampProgress(progress);
      if (_progress != nextProgress) {
        _progress = nextProgress;
        changed = true;
      }
    }
    if (semanticText != null) {
      final nextText = semanticText.trim();
      if (_semanticText != nextText) {
        _semanticText = nextText;
        changed = true;
      }
    }
    if (style != null && _style != style) {
      _style = style;
      changed = true;
    }
    if (speed != null && _speed != speed) {
      _speed = speed;
      changed = true;
    }
    final nextBranchIndex = clearBranchIndex ? null : branchIndex;
    if ((clearBranchIndex || branchIndex != null) &&
        _branchIndex != nextBranchIndex) {
      _branchIndex = nextBranchIndex;
      changed = true;
    }
    if (title != null && _title != title.trim()) {
      _title = title.trim();
      changed = true;
    }
    if (author != null && _author != author.trim()) {
      _author = author.trim();
      changed = true;
    }
    if (chapterIndex != null && _chapterIndex != chapterIndex) {
      _chapterIndex = chapterIndex;
      changed = true;
    }
    if (chapterTitle != null && _chapterTitle != chapterTitle.trim()) {
      _chapterTitle = chapterTitle.trim();
      changed = true;
    }
    if (duration != null && _duration != _clampDuration(duration)) {
      _duration = _clampDuration(duration);
      changed = true;
    }
    if (changed) notifyListeners();
    return true;
  }

  /// Releases callbacks and hides the dock if [ownerToken] is still current.
  bool release(Object ownerToken) {
    if (!_owns(ownerToken)) return false;
    _clearSession();
    notifyListeners();
    return true;
  }

  Future<void> toggle() => _invoke(_onToggle);

  Future<void> previous() => _invoke(_onPrevious);

  Future<void> next() => _invoke(_onNext);

  Future<void> seek(double progress) async {
    final callback = _onSeek;
    final ownerToken = _ownerToken;
    if (!_active || callback == null || ownerToken == null) return;
    final nextProgress = _clampProgress(progress);
    await callback(nextProgress);
    if (_owns(ownerToken) && _progress != nextProgress) {
      _progress = nextProgress;
      notifyListeners();
    }
  }

  /// Moves the position by [delta] of the book's time at 1× (the full
  /// player's ±15 s), clamped to the start and end of the book.
  ///
  /// A session that maps time to text itself (the reader's `onSkip`) does
  /// so; otherwise [delta] is converted through [duration], and a session
  /// without a known [duration] ignores it.
  Future<void> skip(Duration delta) async {
    final onSkip = _onSkip;
    if (!_active) return;
    if (onSkip != null) {
      await onSkip(delta);
      return;
    }
    if (_duration <= Duration.zero) return;
    final target = (elapsed + delta).inMicroseconds / _duration.inMicroseconds;
    await seek(target);
  }

  /// Opens the session's chapter list, when it has one.
  Future<void> showChapters() => _invoke(_onChapters);

  /// Steps [speed] through [bookNarrationSpeedCycle].
  Future<void> cycleSpeed() => setSpeed(nextBookNarrationSpeed(_speed));

  Future<void> setStyle(BookNarrationStyle style) async {
    final callback = _onStyleChanged;
    final ownerToken = _ownerToken;
    if (!_active || callback == null || ownerToken == null || _style == style) {
      return;
    }
    await callback(style);
    if (_owns(ownerToken) && _style != style) {
      _style = style;
      notifyListeners();
    }
  }

  Future<void> setSpeed(double speed) async {
    final callback = _onSpeedChanged;
    final ownerToken = _ownerToken;
    if (!_active || callback == null || ownerToken == null || _speed == speed) {
      return;
    }
    await callback(speed);
    if (_owns(ownerToken) && _speed != speed) {
      _speed = speed;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final callback = _onStop;
    final ownerToken = _ownerToken;
    if (!_active || callback == null || ownerToken == null) return;
    await _stopOwner(ownerToken, callback);
    if (_owns(ownerToken) && (_active || _playing || _preparing)) {
      _active = false;
      _playing = false;
      _preparing = false;
      notifyListeners();
    }
  }

  Future<void> _invoke(BookNarrationRemoteAction? callback) async {
    if (!_active || callback == null) return;
    await callback();
  }

  Future<void> _retireOwner(
    Object ownerToken,
    BookNarrationRemoteAction callback,
  ) async {
    try {
      await _stopOwner(ownerToken, callback);
    } catch (_) {
      // A retired reader cannot surface an error through the replacement
      // session. Its own playback implementation remains responsible for any
      // teardown diagnostics.
    }
  }

  Future<void> _stopOwner(
    Object ownerToken,
    BookNarrationRemoteAction callback,
  ) {
    final existing = _ownerStops[ownerToken];
    if (existing != null) return existing;

    final completer = Completer<void>();
    final future = completer.future;
    _ownerStops[ownerToken] = future;
    unawaited(_completeOwnerStop(ownerToken, callback, completer));
    return future;
  }

  Future<void> _completeOwnerStop(
    Object ownerToken,
    BookNarrationRemoteAction callback,
    Completer<void> completer,
  ) async {
    try {
      await callback();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_ownerStops[ownerToken], completer.future)) {
        _ownerStops.remove(ownerToken);
      }
    }
  }

  bool _owns(Object ownerToken) => identical(_ownerToken, ownerToken);

  static double _clampProgress(double progress) {
    if (!progress.isFinite) return 0;
    return progress.clamp(0.0, 1.0).toDouble();
  }

  static Duration _clampDuration(Duration duration) =>
      duration.isNegative ? Duration.zero : duration;

  static bool _replaceBool(
    bool? next,
    bool current,
    ValueChanged<bool> replace,
  ) {
    if (next == null || next == current) return false;
    replace(next);
    return true;
  }

  void _clearSession() {
    _ownerToken = null;
    _onToggle = null;
    _onPrevious = null;
    _onNext = null;
    _onSeek = null;
    _onStyleChanged = null;
    _onSpeedChanged = null;
    _onStop = null;
    _onReplaced = null;
    _onChapters = null;
    _onSkip = null;
    _active = false;
    _playing = false;
    _preparing = false;
    _progress = 0;
    _semanticText = '';
    _branchIndex = null;
    _resourceId = null;
    _title = '';
    _author = '';
    _chapterIndex = null;
    _chapterTitle = '';
    _duration = Duration.zero;
  }

  @override
  void dispose() {
    _clearSession();
    _ownerStops.clear();
    super.dispose();
  }
}

final bookNarrationRemoteControllerProvider =
    ChangeNotifierProvider<BookNarrationRemoteController>(
      (ref) => BookNarrationRemoteController(),
    );
