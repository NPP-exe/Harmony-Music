import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:harmonymusic/models/hm_streaming_data.dart';
import 'package:harmonymusic/services/audio_handler.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';

class _Settings extends SettingsScreenController {
  @override
  // Tests need the cache preference without initializing plugins or the UI.
  // ignore: must_call_super
  void onInit() {}
}

class _Player extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final started = <String?>[];
  late MyAudioHandler handler;
  Completer<void>? _playing;
  @override
  bool get playing => _playing != null;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  double get speed => 1;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Future<Duration?> setAudioSource(AudioSource source,
          {bool preload = true,
          int? initialIndex,
          Duration? initialPosition}) async =>
      duration;
  @override
  Future<void> setSkipSilenceEnabled(bool enabled) async {}
  @override
  Future<void> play() {
    started.add(handler.currentSongUrl);
    return (_playing ??= Completer<void>()).future;
  }

  @override
  Future<void> pause() async {
    _playing?.complete();
    _playing = null;
  }

  @override
  Future<void> stop() => pause();
  @override
  Future<void> dispose() async {
    await pause();
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

class _Handler extends MyAudioHandler {
  _Handler(_Player player, String directory)
      : super(player: player, cacheDirectory: directory, enableWatchdog: false);

  final requests =
      <({String id, bool fresh, Completer<HMStreamingData> result})>[];
  @override
  Future<HMStreamingData> checkNGetUrl(String songId,
      {bool generateNewUrl = false,
      bool offlineReplacementUrl = false,
      bool cacheResult = true}) {
    final pending = Completer<HMStreamingData>();
    requests.add((id: songId, fresh: generateNewUrl, result: pending));
    return pending.future;
  }
}

HMStreamingData _stream(String name) {
  final audio = Audio(
      itag: 251,
      audioCodec: Codec.opus,
      bitrate: 1,
      duration: 180,
      loudnessDb: 0,
      size: 1,
      url: 'https://example.com/$name');
  return HMStreamingData(
      playable: true,
      statusMSG: 'OK',
      highQualityAudio: audio,
      lowQualityAudio: audio);
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Expected playback operation did not complete');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Player player;
  late _Handler handler;
  setUp(() async {
    Get.testMode = true;
    directory = await Directory.systemTemp.createTemp('harmony-playback-test-');
    Hive.init(directory.path);
    for (final name in [
      'AppPrefs',
      'SongsUrlCache',
      'SongDownloads',
      'SongsCache'
    ]) {
      await Hive.openBox(name);
    }
    Get.put<SettingsScreenController>(_Settings());
    player = _Player();
    handler = _Handler(player, directory.path);
    player.handler = handler;
    await handler.updateQueue([
      const MediaItem(id: 'A', title: 'A'),
      const MediaItem(id: 'B', title: 'B'),
    ]);
  });
  tearDown(() async {
    await handler.customAction('dispose');
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('A to B to A discards both late results and their cache writes',
      () async {
    final oldA = handler.skipToQueueItem(0);
    await _until(() => handler.requests.length == 1);
    final b = handler.skipToQueueItem(1);
    await _until(() => handler.requests.length == 2);
    final latestA = handler.skipToQueueItem(0);
    await _until(() => handler.requests.length == 3);
    handler.requests[2].result.complete(_stream('latest-A'));
    await latestA;
    handler.requests[0].result.complete(_stream('old-A'));
    handler.requests[1].result.complete(_stream('old-B'));
    await Future.wait([oldA, b]);
    expect(player.started, ['https://example.com/latest-A']);
    expect(handler.mediaItem.value!.id, 'A');
    expect(handler.queue.value.first.extras!['url'],
        'https://example.com/latest-A');
    expect(Hive.box('SongsUrlCache').get('A')['highQualityAudio']['url'],
        'https://example.com/latest-A');
    expect(Hive.box('SongsUrlCache').containsKey('B'), isFalse);
    // A lifetime play Future must not prevent pausing the player.
    await handler.pause().timeout(const Duration(seconds: 1));
    expect(player.playing, isFalse);
  });

  test('pause and stop cancel pending loads without restarting audio',
      () async {
    final paused = handler.skipToQueueItem(0);
    await _until(() => handler.requests.length == 1);
    await handler.pause();
    handler.requests[0].result.complete(_stream('paused'));
    await paused;
    final stopped = handler.skipToQueueItem(1);
    await _until(() => handler.requests.length == 2);
    await handler.stop();
    handler.requests[1].result.complete(_stream('stopped'));
    await stopped;
    expect(player.started, isEmpty);
    expect(handler.isSongLoading, isFalse);
    expect(Hive.box('SongsUrlCache').isEmpty, isTrue);
  });

  test('simultaneous errors refresh once and a manual skip cancels recovery',
      () async {
    final initial = handler.skipToQueueItem(0);
    await _until(() => handler.requests.length == 1);
    handler.requests[0].result.complete(_stream('expired-IP'));
    await initial;
    player.events.addError(StateError('403'));
    player.events.addError(StateError('403'));
    await _until(() => handler.requests.length == 2);
    expect(handler.requests[1].fresh, isTrue);
    final selected = handler.skipToQueueItem(1);
    await _until(() => handler.requests.length == 3);
    handler.requests[2].result.complete(_stream('new-song'));
    await selected;
    handler.requests[1].result.complete(_stream('stale-recovery'));
    await Future<void>.delayed(Duration.zero);
    expect(player.started, [
      'https://example.com/expired-IP',
      'https://example.com/new-song',
    ]);
    expect(handler.mediaItem.value!.id, 'B');
    expect(Hive.box('SongsUrlCache').containsKey('A'), isFalse);
  });

  test('a failing replacement stops retrying and keeps the error visible',
      () async {
    final initial = handler.skipToQueueItem(0);
    await _until(() => handler.requests.length == 1);
    handler.requests[0].result.complete(_stream('old'));
    await initial;
    player.events.addError(StateError('403'));
    await _until(() => handler.requests.length == 2);
    handler.requests[1].result.complete(_stream('replacement'));
    await _until(() => player.started.length == 2);
    player.events.addError(StateError('403 again'));
    await _until(() =>
        handler.playbackState.value.processingState ==
        AudioProcessingState.error);
    player.events.add(PlaybackEvent());
    await Future<void>.delayed(Duration.zero);
    expect(handler.requests.length, 2);
    expect(player.playing, isFalse);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.error);
  });
}
