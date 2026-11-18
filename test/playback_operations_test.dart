import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/playback_operations.dart';

void main() {
  test('mutations serialize and skip requests superseded while waiting',
      () async {
    final operations = PlaybackOperations();
    final pending = Completer<void>();
    final calls = <String>[];
    final first = operations.begin();
    final running = operations.run(first, () async {
      calls.add('start');
      await pending.future;
      if (operations.isCurrent(first)) calls.add('stale playback');
    });
    await Future<void>.delayed(Duration.zero);
    final skipped =
        operations.run(first, () async => calls.add('stale queued'));
    final latest = operations.begin();
    final replacement = operations.run(latest, () async => calls.add('latest'));
    expect(calls, ['start']);
    pending.complete();
    await Future.wait([running, skipped, replacement]);
    expect(calls, ['start', 'latest']);
  });

  test('a failed mutation does not block the next request', () async {
    final operations = PlaybackOperations();
    final request = operations.begin();
    await expectLater(
        operations.run(request, () async => throw StateError('load')),
        throwsStateError);
    var resumed = false;
    await operations.run(request, () async => resumed = true);
    expect(resumed, isTrue);
  });

  test('recovery is shared and old completion cannot release a newer claim',
      () {
    final operations = PlaybackOperations();
    final first = operations.begin();
    expect(operations.beginRecovery(first), isTrue);
    expect(operations.beginRecovery(first), isFalse);
    final next = operations.begin();
    expect(operations.beginRecovery(first), isFalse);
    expect(operations.beginRecovery(next), isTrue);
    operations.endRecovery(first);
    expect(operations.beginRecovery(next), isFalse);
    operations.endRecovery(next);
    expect(operations.beginRecovery(next), isTrue);
  });
}
