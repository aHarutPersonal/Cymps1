import 'dart:async';

/// Append-only streamed text that publishes an immediate first chunk and then
/// coalesces later updates. This keeps streaming responsive while avoiding a
/// full string allocation, text layout, and scroll operation for every token.
class CoalescedText {
  CoalescedText({
    required this.onUpdate,
    this.interval = const Duration(milliseconds: 60),
  });

  final void Function(String value) onUpdate;
  final Duration interval;

  final StringBuffer _buffer = StringBuffer();
  Timer? _timer;
  String _lastPublished = '';
  bool _closed = false;

  bool get isEmpty => _buffer.isEmpty;

  void add(String chunk) {
    if (_closed || chunk.isEmpty) return;
    _buffer.write(chunk);

    // The first token removes the waiting state without an artificial delay.
    if (_lastPublished.isEmpty) {
      _publish();
      _schedule();
      return;
    }
    _schedule();
  }

  void _schedule() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer(interval, () {
      _timer = null;
      _publish();
    });
  }

  void _publish() {
    if (_lastPublished.length == _buffer.length) return;
    final value = _buffer.toString();
    _lastPublished = value;
    onUpdate(value);
  }

  /// Publishes pending text immediately without closing the accumulator.
  String flush() {
    if (_closed) return _lastPublished;
    _timer?.cancel();
    _timer = null;
    _publish();
    return _lastPublished;
  }

  /// Cancels future updates, optionally publishing the exact final value.
  String close({bool emitPending = true}) {
    if (_closed) return _lastPublished;
    _timer?.cancel();
    _timer = null;
    if (emitPending) {
      _publish();
    } else if (_lastPublished.length != _buffer.length) {
      _lastPublished = _buffer.toString();
    }
    _closed = true;
    return _lastPublished;
  }

  void dispose() => close(emitPending: false);
}
