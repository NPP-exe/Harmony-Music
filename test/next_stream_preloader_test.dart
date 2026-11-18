import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/hm_streaming_data.dart';
import 'package:harmonymusic/services/next_stream_preloader.dart';
import 'package:harmonymusic/services/stream_service.dart';

HMStreamingData stream({bool expired = false}) {
  Audio audio(int quality) => Audio(
      itag: quality,
      audioCodec: Codec.opus,
      bitrate: 1,
      duration: 100,
      loudnessDb: 0,
      size: 100,
      url:
          'https://example.com/audio?expire=${expired ? 1 : DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}');
  return HMStreamingData(
      playable: true,
      statusMSG: 'OK',
      lowQualityAudio: audio(249),
      highQualityAudio: audio(251));
}

void main() {
  test('transition shares a pending fetch and uses the current quality',
      () async {
    final preloader = NextStreamPreloader();
    final pending = Completer<HMStreamingData>();
    var requests = 0;
    preloader.prepare('next', () {
      requests++;
      return pending.future;
    });
    preloader.prepare('next', () {
      requests++;
      return pending.future;
    });
    preloader.prepare('other', () {
      requests++;
      return pending.future;
    });
    expect(requests, 1);
    final next = preloader.take('next', quality: 0);
    pending.complete(stream());
    expect((await next)!.audio!.itag, 249);
    expect(await preloader.take('next', quality: 1), isNull);
  });

  test('expired or failed preparation lets playback fetch a fresh URL',
      () async {
    final preloader = NextStreamPreloader();
    preloader.prepare('expired', () async => stream(expired: true));
    expect(await preloader.take('expired', quality: 1), isNull);
    preloader.prepare('failed', () async => throw StateError('Network failed'));
    expect(await preloader.take('failed', quality: 1), isNull);
    preloader.prepare('fresh', () async => stream());
    expect((await preloader.take('fresh', quality: 1))!.audio!.itag, 251);
  });

  test('invalidating preparation discards late results and keeps work bounded',
      () async {
    final preloader = NextStreamPreloader();
    final pending = Completer<HMStreamingData>();
    preloader.prepare('old', () => pending.future);
    preloader.clear();
    var started = false;
    preloader.prepare('new', () async {
      started = true;
      return stream();
    });
    expect(started, isFalse);
    pending.complete(stream());
    expect(await preloader.take('old', quality: 1), isNull);
    await Future<void>.delayed(Duration.zero);
    preloader.prepare('new', () async => stream());
    expect(await preloader.take('new', quality: 1), isNotNull);
  });
  test('a timed out preparation keeps its slot and discards its late result',
      () async {
    final preloader = NextStreamPreloader(waitTimeout: Duration.zero);
    final pending = Completer<HMStreamingData>();
    preloader.prepare('old', () => pending.future);
    expect(await preloader.take('old', quality: 1), isNull);
    var requests = 0;
    preloader.prepare('new', () async {
      requests++;
      return stream();
    });
    expect(requests, 0);
    pending.complete(stream());
    await Future<void>.delayed(Duration.zero);
    expect(await preloader.take('old', quality: 1), isNull);
    preloader.prepare('new', () async {
      requests++;
      return stream();
    });
    expect(await preloader.take('new', quality: 1), isNotNull);
    expect(requests, 1);
  });
}
