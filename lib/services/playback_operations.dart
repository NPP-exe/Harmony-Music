import 'dart:async';

/// Network lookups run independently; only native player mutations are queued.
class PlaybackOperations {
  int _generation = 0;
  int? _recovery;
  Future<void> _tail = Future<void>.value();

  int get current => _generation;
  bool isCurrent(int generation) => generation == _generation;

  int begin() {
    _recovery = null;
    return ++_generation;
  }

  bool beginRecovery(int generation) {
    if (!isCurrent(generation) || _recovery == generation) return false;
    _recovery = generation;
    return true;
  }

  void endRecovery(int generation) {
    if (_recovery == generation) _recovery = null;
  }

  /// A null generation is reserved for one-time player initialization.
  Future<void> run(int? generation, Future<void> Function() action) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    await previous;
    try {
      if (generation == null || isCurrent(generation)) await action();
    } finally {
      completed.complete();
    }
  }
}
