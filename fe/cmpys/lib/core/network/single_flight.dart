/// Coalesces concurrent calls so they all await one in-flight operation.
class SingleFlight<T> {
  Future<T>? _inFlight;

  Future<T> run(Future<T> Function() operation) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = Future<T>.sync(operation);
    _inFlight = future;
    void clear() {
      if (identical(_inFlight, future)) _inFlight = null;
    }

    future.then<void>((_) => clear(), onError: (error, stackTrace) => clear());
    return future;
  }
}
