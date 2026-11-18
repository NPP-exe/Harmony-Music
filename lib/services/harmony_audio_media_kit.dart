// ignore_for_file: depend_on_referenced_packages, avoid_dynamic_calls, implementation_imports
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';

/// Sanitizes a file path or file:// URI to a clean, absolute local filesystem path.
/// Handles redundant or malformed scheme prefixes (such as '/file:/...', 'file://file:///...'),
/// URL percent-encoding (spaces, non-ASCII), and ensures proper native platform directory separators.
String cleanLocalFilePath(String pathOrUri) {
  String s = pathOrUri.trim();
  if (s.isEmpty) return s;

  while (s.startsWith('file:') ||
      s.startsWith('/file:') ||
      s.startsWith(r'\file:')) {
    s = s.replaceFirst(RegExp(r'^[/\\]*file:[/\\]*'), '');
  }

  try {
    s = Uri.decodeFull(s);
  } catch (_) {}

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    s = s.replaceAll('/', r'\');
  } else {
    if (!s.startsWith('/')) {
      s = '/$s';
    }
  }
  return s;
}

class HarmonyAudioMediaKit extends JustAudioPlatform {
  static void ensureInitialized() {
    if (JustAudioPlatform.instance is! HarmonyAudioMediaKit) {
      JustAudioPlatform.instance = HarmonyAudioMediaKit();
    }
  }

  final Map<String, HarmonyMediaKitPlayer> _players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    MediaKit.ensureInitialized();

    if (_players.containsKey(request.id)) {
      throw PlatformException(
          code: 'error', message: 'Player ${request.id} already exists!');
    }

    final player = HarmonyMediaKitPlayer(request.id);
    _players[request.id] = player;
    await player.isReady;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await _players.remove(request.id)?.release();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    await Future.wait(_players.values.map((e) => e.release()));
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

class HarmonyMediaKitPlayer extends AudioPlayerPlatform {
  late final Player _player;
  late final List<StreamSubscription> _streamSubscriptions;

  final _readyCompleter = Completer<void>();
  Future<void> get isReady => _readyCompleter.future;

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _bufferedPosition = Duration.zero;
  Duration _position = Duration.zero;
  int _currentIndex = 0;
  bool _loading = false;
  bool _buffering = false;
  bool _failed = false;
  bool _released = false;

  ProcessingStateMessage get _activeState => _failed
      ? ProcessingStateMessage.idle
      : _loading
          ? ProcessingStateMessage.loading
          : _buffering
              ? ProcessingStateMessage.buffering
              : ProcessingStateMessage.ready;

  HarmonyMediaKitPlayer(super.id, {Player? player}) {
    _player = player ??
        Player(
          configuration: PlayerConfiguration(
            protocolWhitelist: const ['http', 'https', 'file'],
            title: 'Harmony Music',
            bufferSize: 32 * 1024 * 1024,
            logLevel: MPVLogLevel.error,
            // Setting osc to true prevents media_kit from attempting to pass osc=no,
            // which fails with "_setProperty(osc, 1)" on audio-only libmpv builds.
            osc: true,
            ready: () async {
              await _applyMpvAudioOptions();
              if (!_readyCompleter.isCompleted) {
                _readyCompleter.complete();
              }
            },
          ),
        );

    _streamSubscriptions = [
      _player.stream.duration.listen((duration) {
        _processingState = _activeState;
        _updatePlaybackEvent(duration: duration);
      }),
      _player.stream.position.listen((position) {
        _position = position;
        _updatePlaybackEvent();
      }),
      _player.stream.buffering.listen((isBuffering) {
        _buffering = isBuffering;
        _processingState = _activeState;
        _updatePlaybackEvent();
      }),
      _player.stream.buffer.listen((buffer) {
        _bufferedPosition = buffer;
        _updatePlaybackEvent();
      }),
      _player.stream.playing.listen((playing) {
        _processingState = _activeState;
        _dataController.add(PlayerDataMessage(playing: playing));
        _updatePlaybackEvent();
      }),
      _player.stream.volume.listen((volume) {
        _dataController.add(PlayerDataMessage(volume: volume / 100.0));
      }),
      _player.stream.completed.listen((completed) {
        _processingState =
            completed ? ProcessingStateMessage.completed : _activeState;
        _updatePlaybackEvent();
      }),
      _player.stream.error.listen((error) {
        final errText = error.toString().toLowerCase();
        // Ignore benign subtitle, cache, and external file errors
        if (errText.contains('external file') ||
            errText.contains('.lrc') ||
            errText.contains('file cache') ||
            errText.contains('osc')) {
          return;
        }
        _processingState = ProcessingStateMessage.idle;
        _failed = true;
        _eventController
            .addError(PlatformException(code: 'media_kit', message: error));
      }),
      _player.stream.playlist.listen((playlist) {
        _currentIndex = playlist.index;
        _updatePlaybackEvent();
      }),
      _player.stream.pitch.listen((pitch) {
        _dataController.add(PlayerDataMessage(pitch: pitch));
      }),
      _player.stream.rate.listen((rate) {
        _dataController.add(PlayerDataMessage(speed: rate));
      }),
      _player.stream.log.listen((event) {
        // Suppress expected/harmless MPV log spam
        final text = event.text.toLowerCase();
        if (text.contains('osc') ||
            text.contains('file cache') ||
            text.contains('.lrc') ||
            event.prefix == 'mkv' ||
            event.prefix == 'lavf') {
          return;
        }
        if (kDebugMode) {
          debugPrint("MPV: [${event.level}] ${event.prefix}: ${event.text}");
        }
      }),
    ];
    if (player != null) _readyCompleter.complete();
  }

  Future<void> _applyMpvAudioOptions() async {
    final platform = _player.platform;
    if (platform != null) {
      try {
        await (platform as dynamic).setProperty('sub-auto', 'no');
        await (platform as dynamic).setProperty('autoload-files', 'no');
        await (platform as dynamic).setProperty('cache-on-disk', 'no');
        await (platform as dynamic).setProperty('msg-level', 'all=no');
      } catch (_) {}
    }
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  void _updatePlaybackEvent(
      {Duration? duration, IcyMetadataMessage? icyMetadata}) {
    if (_eventController.isClosed) return;
    _eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updateTime: DateTime.now(),
      updatePosition: _position,
      bufferedPosition: _bufferedPosition,
      duration: duration,
      icyMetadata: icyMetadata,
      currentIndex: _currentIndex,
      androidAudioSessionId: null,
    ));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _currentIndex = request.initialIndex ?? 0;
    _bufferedPosition = Duration.zero;
    _position = Duration.zero;
    _loading = true;
    _failed = false;
    _buffering = false;
    _processingState = ProcessingStateMessage.loading;
    _updatePlaybackEvent();
    try {
      await _player.pause();
      await _player.open(
        Playlist(_convertSources(request.audioSourceMessage),
            index: _currentIndex),
        play: false,
      );
      if (request.initialPosition != null) {
        await _player.seek(request.initialPosition!);
      }
    } catch (_) {
      _failed = true;
      rethrow;
    } finally {
      _loading = false;
      _processingState = _activeState;
      _updatePlaybackEvent();
    }
    return LoadResponse(duration: _player.state.duration);
  }

  List<Media> _convertSources(AudioSourceMessage source) =>
      source is ConcatenatingAudioSourceMessage
          ? source.children.expand(_convertSources).toList()
          : [_convertAudioSourceIntoMediaKit(source)];

  Media _convertAudioSourceIntoMediaKit(AudioSourceMessage audioSource) {
    if (audioSource is UriAudioSourceMessage) {
      final raw = audioSource.uri;
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        return Media(raw, httpHeaders: audioSource.headers);
      }
      final cleanPath = cleanLocalFilePath(raw);
      return Media(cleanPath, httpHeaders: audioSource.headers);
    } else {
      throw UnsupportedError(
          '${audioSource.runtimeType} is currently not supported');
    }
  }

  @override
  Future<PlayResponse> play(PlayRequest request) {
    return _player.play().then((_) => PlayResponse());
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) {
    return _player.pause().then((_) => PauseResponse());
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    return _player
        .setVolume(request.volume * 100.0)
        .then((value) => SetVolumeResponse());
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    return _player.setRate(request.speed).then((_) => SetSpeedResponse());
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) =>
      _player.setPitch(request.pitch).then((_) => SetPitchResponse());

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) => _player
      .setPlaylistMode(const {
        LoopModeMessage.off: PlaylistMode.none,
        LoopModeMessage.one: PlaylistMode.single,
        LoopModeMessage.all: PlaylistMode.loop,
      }[request.loopMode]!)
      .then((_) => SetLoopModeResponse());

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) =>
      _player
          .setShuffle(request.shuffleMode == ShuffleModeMessage.all)
          .then((_) => SetShuffleModeResponse());

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (request.index != null) {
      await _player.jump(request.index!);
    }

    if (request.position != null) {
      _position = request.position!;
      await _player.seek(request.position!);
    } else {
      _position = Duration.zero;
    }

    _updatePlaybackEvent();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    if (request.children.isEmpty) return ConcatenatingInsertAllResponse();
    await _applyMpvAudioOptions();
    final media = List<Media>.of(_player.state.playlist.medias)
      ..insertAll(request.index, request.children.expand(_convertSources));
    await _player.open(Playlist(media, index: _currentIndex),
        play: _player.state.playing);
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    if (_released) return ConcatenatingRemoveRangeResponse();
    for (var index = request.endIndex - 1;
        index >= request.startIndex;
        index--) {
      if (_released) break;
      await _player.remove(index);
    }

    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
          ConcatenatingMoveRequest request) =>
      _player
          .move(request.currentIndex, request.newIndex)
          .then((_) => ConcatenatingMoveResponse());

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await release();
    return DisposeResponse();
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    for (final StreamSubscription subscription in _streamSubscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _eventController.close();
    await _dataController.close();
  }
}
