import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:harmonymusic/services/harmony_audio_media_kit.dart';

class _Streams extends Fake implements PlayerStream {
  final bufferingEvents = StreamController<bool>.broadcast(sync: true);
  final playingEvents = StreamController<bool>.broadcast(sync: true);
  final errorEvents = StreamController<String>.broadcast(sync: true);
  @override
  Stream<bool> get buffering => bufferingEvents.stream;
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<String> get error => errorEvents.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

class _Player extends Fake implements Player {
  @override
  final _Streams stream = _Streams();
  @override
  PlayerState get state => const PlayerState();
  @override
  Null get platform => null;
  final opened = <Playlist>[];
  final autoplay = <bool>[];
  int disposals = 0;
  @override
  Future<void> pause() async {}
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add(playable as Playlist);
    autoplay.add(play);
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await stream.bufferingEvents.close();
    await stream.playingEvents.close();
    await stream.errorEvents.close();
  }
}

void main() {
  late _Player player;
  late HarmonyMediaKitPlayer backend;
  setUp(() {
    player = _Player();
    backend = HarmonyMediaKitPlayer('test', player: player);
  });
  tearDown(() => backend.release());

  LoadRequest source(String name) => LoadRequest(
        audioSourceMessage: ConcatenatingAudioSourceMessage(
          id: 'playlist',
          useLazyPreparation: false,
          shuffleOrder: [0],
          children: [
            ProgressiveAudioSourceMessage(
              id: name,
              uri: 'https://example.com/$name',
            )
          ],
        ),
      );

  test('recovery reloads the requested source without starting old audio',
      () async {
    await backend.load(source('old'));
    await backend.load(source('replacement'));
    expect(player.opened.map((p) => p.medias.single.uri),
        ['https://example.com/old', 'https://example.com/replacement']);
    expect(player.autoplay, [false, false]);
    await backend.release();
    await backend.release();
    expect(player.disposals, 1);
    // A late clear after disposal must not call the native player again.
    await backend.concatenatingRemoveRange(ConcatenatingRemoveRangeRequest(
      id: 'playlist',
      startIndex: 0,
      endIndex: 1,
      shuffleOrder: [],
    ));
  });

  test('playing notifications do not hide buffering or a stream error',
      () async {
    final events = <PlaybackEventMessage>[];
    final errors = <Object>[];
    final subscription = backend.playbackEventMessageStream
        .listen(events.add, onError: (Object error) => errors.add(error));
    player.stream.bufferingEvents.add(true);
    player.stream.playingEvents.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.processingState, ProcessingStateMessage.buffering);
    player.stream.errorEvents.add('Failed to submit audio: connection closed');
    player.stream.playingEvents.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<PlatformException>());
    expect(events.last.processingState, ProcessingStateMessage.idle);
    await subscription.cancel();
  });
}
