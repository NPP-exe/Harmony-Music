import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';

import '/models/album.dart';
import '../models/playlist.dart';
import '/services/equalizer.dart';
import '/services/stream_service.dart';
import '/models/hm_streaming_data.dart';
import '/ui/player/player_controller.dart';
import '../ui/screens/Home/home_screen_controller.dart';
import 'playlist_song_store.dart';
import '/services/background_task.dart';
import '/services/permission_service.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/services/utils.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../ui/screens/Library/library_controller.dart';
import 'harmony_audio_media_kit.dart';
import 'next_stream_preloader.dart';
import 'playback_operations.dart';

Future<AudioHandler> initAudioService() async {
  if (!GetPlatform.isWeb && (GetPlatform.isWindows || GetPlatform.isLinux)) {
    HarmonyAudioMediaKit.ensureInitialized();
  }
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.mycompany.myapp.audio',
      androidNotificationChannelName: 'Harmony Music Notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with GetxServiceMixin {
  // ignore: prefer_typing_uninitialized_variables
  late final _cacheDir;
  late AudioPlayer _player;
  late MediaLibrary _mediaLibrary;
  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;
  String? currentSongUrl;
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = false;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;
  // var networkErrorPause = false;
  bool isSongLoading = true;

  // Watchdog for silent-audio bug: tracks position to detect frozen playback
  Duration _lastWatchdogPosition = Duration.zero;
  DateTime _lastWatchdogCheck = DateTime.now();
  final _operations = PlaybackOperations();
  bool _wantsPlayback = false;
  bool _automaticRetryUsed = false;
  bool _disposed = false;
  bool _nativePlaylistInitialized = false;

  // list of shuffled queue songs ids
  List<String> shuffledQueue = [];

  final _playList = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: false,
  );
  bool _webPlaylistInitialized = false;
  final _nextStream = NextStreamPreloader();

  MyAudioHandler(
      {AudioPlayer? player,
      String? cacheDirectory,
      bool enableWatchdog = true}) {
    if (player == null &&
        !GetPlatform.isWeb &&
        (GetPlatform.isWindows || GetPlatform.isLinux)) {
      HarmonyAudioMediaKit.ensureInitialized();
    }
    _mediaLibrary = MediaLibrary();
    _player = player ??
        AudioPlayer(
          audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
              minBufferDuration: Duration(seconds: 50),
              maxBufferDuration: Duration(seconds: 120),
              bufferForPlaybackDuration: Duration(milliseconds: 50),
              bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
            ),
          ),
        );
    _createCacheDir(cacheDirectory);
    _addEmptyList();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    _listenForSequenceStateChanges();
    final appPrefsBox = Hive.box("AppPrefs");
    _player.setSkipSilenceEnabled(
      appPrefsBox.get("skipSilenceEnabled") ?? false,
    );
    loopModeEnabled = appPrefsBox.get("isLoopModeEnabled") ?? false;
    shuffleModeEnabled = appPrefsBox.get("isShuffleModeEnabled") ?? false;
    queueLoopModeEnabled =
        Hive.box("AppPrefs").get("queueLoopModeEnabled") ?? false;
    loudnessNormalizationEnabled =
        appPrefsBox.get("loudnessNormalizationEnabled") ?? false;
    _listenForDurationChanges();
    if (enableWatchdog) _startSilenceWatchdog();
    if (GetPlatform.isAndroid) {
      _listenSessionIdStream();
    }
  }

  Future<void> _createCacheDir(String? cacheDirectory) async {
    if (GetPlatform.isWeb) {
      _cacheDir = '';
      return;
    }
    _cacheDir = cacheDirectory ?? (await getTemporaryDirectory()).path;
    if (!Directory("$_cacheDir/cachedSongs/").existsSync()) {
      Directory("$_cacheDir/cachedSongs/").createSync(recursive: true);
    }
  }

  /// Periodically checks if audio is silently frozen (playing but position not advancing).
  /// This detects YouTube stream URL expiry and other silent-audio failures.
  void _startSilenceWatchdog() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (_disposed) return false;
      try {
        final pos = _player.position;
        if (_wantsPlayback &&
            _player.playing &&
            !isSongLoading &&
            _player.processingState == ProcessingState.ready &&
            DateTime.now().difference(_lastWatchdogCheck).inMilliseconds > 0 &&
            (pos - _lastWatchdogPosition).inMilliseconds.abs() < 200) {
          await _recoverPlayback(stalled: true);
        }
        if (_wantsPlayback &&
            _player.playing &&
            !isSongLoading &&
            (_player.position - _lastWatchdogPosition).inMilliseconds >= 200) {
          _automaticRetryUsed = false;
        }
        _lastWatchdogPosition = _player.position;
        _lastWatchdogCheck = DateTime.now();
      } catch (error) {
        printERROR('[Watchdog] Error: $error');
      }
      return !_disposed;
    });
  }

  void _addEmptyList() {
    if (GetPlatform.isWeb) return;
    unawaited(_operations.run(null, _initializeNativePlaylist).catchError(
        (Object error) => printERROR('Could not initialize audio: $error')));
  }

  Future<void> _initializeNativePlaylist() async {
    if (_nativePlaylistInitialized) return;
    await _player.setAudioSource(_playList);
    _nativePlaylistInitialized = true;
  }

  Future<void> _initializeWebPlaylist() async {
    if (!GetPlatform.isWeb || _webPlaylistInitialized) return;
    await _player.setAudioSource(_playList);
    _webPlaylistInitialized = true;
  }

  void _listenSessionIdStream() {
    _player.androidAudioSessionIdStream.listen((int? id) {
      if (id != null) {
        EqualizerService.initAudioEffect(id);
      }
    });
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen(
      (PlaybackEvent event) {
        if (_disposed ||
            (!_wantsPlayback &&
                playbackState.value.processingState ==
                    AudioProcessingState.error)) {
          return;
        }
        final playing = _player.playing;
        playbackState.add(
          playbackState.value.copyWith(
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.skipToNext,
            ],
            systemActions: const {MediaAction.seek},
            androidCompactActionIndices: const [0, 1, 2],
            processingState: isSongLoading
                ? AudioProcessingState.loading
                : const {
                    ProcessingState.idle: AudioProcessingState.idle,
                    ProcessingState.loading: AudioProcessingState.loading,
                    ProcessingState.buffering: AudioProcessingState.buffering,
                    ProcessingState.ready: AudioProcessingState.ready,
                    ProcessingState.completed: AudioProcessingState.completed,
                  }[_player.processingState]!,
            repeatMode: const {
              LoopMode.off: AudioServiceRepeatMode.none,
              LoopMode.one: AudioServiceRepeatMode.one,
              LoopMode.all: AudioServiceRepeatMode.all,
            }[_player.loopMode]!,
            shuffleMode: (shuffleModeEnabled)
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
            queueIndex: currentIndex,
          ),
        );

        //print("set ${playbackState.value.queueIndex},${event.currentIndex}");
      },
      onError: (Object e, StackTrace st) async {
        printERROR('An error occurred during playback: $e');
        final errStr = e.toString().toLowerCase();
        // Ignore non-fatal subtitle, cache, or external file errors so playback is never interrupted
        if (errStr.contains('external file') ||
            errStr.contains('.lrc') ||
            errStr.contains('file cache') ||
            errStr.contains('osc')) {
          return;
        }

        await _recoverPlayback();
      },
    );
  }

  bool _isTransitioningSong = false;

  void _listenToPlaybackForNextSong() {
    final playerDurationOffset = GetPlatform.isWindows
        ? 200
        : GetPlatform.isLinux
            ? 700
            : 0;
    _player.positionStream.listen((value) async {
      if (_isTransitioningSong || isSongLoading || !_wantsPlayback) return;
      _prepareNextStream(value);
      if (_player.duration != null && _player.duration?.inSeconds != 0) {
        if (value.inMilliseconds >=
            (_player.duration!.inMilliseconds - playerDurationOffset)) {
          await _triggerNext();
        }
      }
    });
  }

  void _prepareNextStream(Duration position) {
    if (!(GetPlatform.isLinux || GetPlatform.isWindows) ||
        isSongLoading ||
        !_player.playing ||
        loopModeEnabled ||
        position < const Duration(seconds: 5)) {
      return;
    }
    final duration = _player.duration;
    if (duration == null || duration - position > const Duration(seconds: 45)) {
      return;
    }
    final items = queue.value;
    final index = currentIndex;
    if (index is! int || index < 0 || index >= items.length) return;
    int next;
    if (shuffleModeEnabled) {
      // Do not reshuffle or advance the real shuffle cursor to predict a track.
      if (currentShuffleIndex + 1 >= shuffledQueue.length) return;
      final id = shuffledQueue[currentShuffleIndex + 1];
      next = items.indexWhere((item) => item.id == id);
    } else {
      next = index + 1 < items.length
          ? index + 1
          : queueLoopModeEnabled
              ? 0
              : -1;
    }
    if (next < 0 || next == index) return;
    final song = items[next];
    if (song.extras?['isLocal'] == true ||
        song.id.startsWith('local_') ||
        Hive.box('SongDownloads').containsKey(song.id) ||
        (Hive.isBoxOpen('SongsCache') &&
            Hive.box('SongsCache').containsKey(song.id))) {
      return;
    }
    _nextStream.prepare(
        song.id, () => checkNGetUrl(song.id, cacheResult: false));
  }

  Future<HMStreamingData> _streamForPlayback(String songId, bool newUrl) async {
    if (newUrl) {
      _nextStream.clear();
    } else {
      final prepared = await _nextStream.take(songId,
          quality: Hive.box('AppPrefs').get('streamingQuality') ?? 1);
      if (prepared != null) return prepared;
    }
    return checkNGetUrl(songId, generateNewUrl: newUrl, cacheResult: false);
  }

  Future<void> _triggerNext() async {
    if (_disposed || _isTransitioningSong || isSongLoading || !_wantsPlayback) {
      return;
    }
    _isTransitioningSong = true;
    try {
      if (loopModeEnabled) {
        final request = _operations.current;
        await _operations.run(request, () async {
          await _player.seek(Duration.zero);
          if (_operations.isCurrent(request)) _startPlayback(request);
        });
        return;
      }
      await skipToNext();
    } finally {
      Future.delayed(const Duration(milliseconds: 1500), () {
        _isTransitioningSong = false;
      });
    }
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
    });
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (isSongLoading ||
          currentIndex == null ||
          currQueue.isEmpty ||
          duration == null) {
        return;
      }
      final currentSong = queue.value[currentIndex];
      if (currentSong.duration == null || currentIndex == 0) {
        final newMediaItem = currentSong.copyWith(duration: duration);
        mediaItem.add(newMediaItem);
      }
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    // notify system
    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);

    if (shuffleModeEnabled) {
      final mediaItemsIds = mediaItems.toList().map((item) => item.id).toList();
      final notPlayedshuffledQueue = shuffledQueue.isNotEmpty
          ? shuffledQueue.toList().sublist(currentShuffleIndex + 1)
          : shuffledQueue;
      notPlayedshuffledQueue.addAll(mediaItemsIds);
      notPlayedshuffledQueue.shuffle();
      shuffledQueue.replaceRange(
        currentShuffleIndex,
        shuffledQueue.length,
        notPlayedshuffledQueue,
      );
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    this.queue.add(List<MediaItem>.from(queue));
    final currentMediaItem = mediaItem.value;
    if (currentMediaItem != null) {
      final newIdx = queue.indexWhere((item) => item.id == currentMediaItem.id);
      if (newIdx != -1) {
        currentIndex = newIdx;
      }
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (shuffleModeEnabled) {
      shuffledQueue.add(mediaItem.id);
    }

    // notify system
    final newQueue = queue.value..add(mediaItem);
    queue.add(newQueue);
  }

  Future<bool> _setAudioSourceWeb(
    MediaItem mediaItem,
    HMStreamingData streamInfo,
    int request,
  ) async {
    final candidateAudios = <Audio>[
      if (streamInfo.audio != null) streamInfo.audio!,
      if (streamInfo.lowQualityAudio != null &&
          streamInfo.lowQualityAudio != streamInfo.audio)
        streamInfo.lowQualityAudio!,
      if (streamInfo.highQualityAudio != null &&
          streamInfo.highQualityAudio != streamInfo.audio)
        streamInfo.highQualityAudio!,
      if (streamInfo.allAudioFormats != null)
        ...streamInfo.allAudioFormats!.where(
          (a) =>
              a != streamInfo.audio &&
              a != streamInfo.lowQualityAudio &&
              a != streamInfo.highQualityAudio,
        ),
    ];

    Object? lastError;
    for (final candidate in candidateAudios) {
      if (!_operations.isCurrent(request)) return false;
      final url = candidate.url;
      if (url.isEmpty || isExpired(url: url)) {
        continue;
      }
      try {
        final extras = Map<String, dynamic>.from(mediaItem.extras ?? const {});
        extras['url'] = url;
        final updatedMediaItem = mediaItem.copyWith(extras: extras);
        currentSongUrl = url;
        this.mediaItem.add(updatedMediaItem);
        final audioSource =
            AudioSource.uri(Uri.parse(url), tag: updatedMediaItem);
        await _player.setAudioSource(audioSource);
        return _operations.isCurrent(request);
      } catch (e) {
        lastError = e;
        printERROR(
            '[Web playback] Failed to load candidate audio (${candidate.itag}): $e');
      }
    }

    if (!_operations.isCurrent(request)) return false;
    _wantsPlayback = false;
    printERROR(
        '[Web playback] All candidate audio streams failed to load: $lastError');
    isSongLoading = false;
    currentSongUrl = null;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        errorCode: 404,
        errorMessage: 'Playback error: Unable to load audio stream',
      ),
    );
    if (Get.isRegistered<PlayerController>()) {
      Get.find<PlayerController>().notifyPlayError(
        'Playback error: Could not stream this song in your browser. Please try another track.',
      );
    }
    try {
      await _player.stop();
    } catch (_) {}
    return false;
  }

  AudioSource _createLocalAudioSource(String filePath, MediaItem item) {
    final cleanPath = cleanLocalFilePath(filePath);
    return AudioSource.uri(Uri.file(cleanPath), tag: item);
  }

  AudioSource _createAudioSource(MediaItem mediaItem) {
    final url = mediaItem.extras!['url'] as String;
    if (!GetPlatform.isWeb &&
        (url.contains('/cache') ||
            (Get.find<SettingsScreenController>().cacheSongs.isTrue &&
                url.contains("http")))) {
      printINFO("Playing Using LockCaching");
      isPlayingUsingLockCachingSource = true;
      return LockCachingAudioSource(
        Uri.parse(url),
        cacheFile: File("$_cacheDir/cachedSongs/${mediaItem.id}.mp3"),
        tag: mediaItem,
      );
    }

    final cleanPath = cleanLocalFilePath(url);
    if (!GetPlatform.isWeb &&
        (!url.startsWith('http://') && !url.startsWith('https://') ||
            File(cleanPath).existsSync() ||
            url.startsWith('file:') ||
            url.contains('/file:'))) {
      printINFO("Playing Using AudioSource.uri(file)");
      isPlayingUsingLockCachingSource = false;
      return _createLocalAudioSource(cleanPath, mediaItem);
    }

    printINFO("Playing Using AudioSource.uri");
    isPlayingUsingLockCachingSource = false;
    return AudioSource.uri(Uri.tryParse(url)!, tag: mediaItem);
  }

  @override
  // ignore: avoid_renaming_method_parameters
  Future<void> removeQueueItem(MediaItem mediaItem_) async {
    if (shuffleModeEnabled) {
      final id = mediaItem_.id;
      final itemIndex = shuffledQueue.indexOf(id);
      if (currentShuffleIndex > itemIndex) {
        currentShuffleIndex -= 1;
      }
      shuffledQueue.remove(id);
    }

    final currentQueue = queue.value;
    final currentSong = mediaItem.value;
    final itemIndex = currentQueue.indexOf(mediaItem_);
    if (currentIndex > itemIndex) {
      currentIndex -= 1;
    }
    currentQueue.remove(mediaItem_);
    queue.add(currentQueue);
    mediaItem.add(currentSong);
  }

  Future<void> _selectTrack(
    MediaItem song,
    int index, {
    bool localFile = false,
    bool newUrl = false,
    bool restoreSession = false,
    Duration position = Duration.zero,
    int? expectedGeneration,
  }) async {
    if (_disposed ||
        (expectedGeneration != null &&
            !_operations.isCurrent(expectedGeneration))) {
      return;
    }
    final request = _operations.begin();
    if (expectedGeneration == null) _automaticRetryUsed = false;
    _wantsPlayback = !restoreSession;
    currentIndex = index;
    currentSongUrl = null;
    isSongLoading = true;
    mediaItem.add(song);
    playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.loading, queueIndex: index));
    final timing = Stopwatch()..start();
    final local = localFile ||
        song.extras?['isLocal'] == true ||
        song.id.startsWith('local_');
    try {
      await _operations.run(request, () async {
        if (!GetPlatform.isWeb) await _initializeNativePlaylist();
        if (!_operations.isCurrent(request)) return;
        await _player.pause();
        if (!_operations.isCurrent(request)) return;
        if (_playList.children.isNotEmpty) await _playList.clear();
      });
      if (!_operations.isCurrent(request)) return;
      HMStreamingData? stream;
      final String url;
      if (local) {
        url = song.extras!['url'] as String;
      } else {
        stream = await _streamForPlayback(song.id, newUrl);
        if (!_operations.isCurrent(request)) return;
        if (!stream.playable || stream.audio == null) {
          await _failPlayback(request,
              stream.statusMSG.isEmpty ? 'networkError' : stream.statusMSG);
          return;
        }
        url = stream.audio!.url;
        if (url.startsWith('https://') || url.startsWith('http://')) {
          await Hive.box('SongsUrlCache').put(song.id, stream.toJson());
          if (!_operations.isCurrent(request)) return;
        }
      }
      printINFO('[Playback timing] ${song.id}: stream ready '
          '${timing.elapsedMilliseconds} ms including source cleanup');
      await _operations.run(request, () async {
        currentSongUrl = url;
        final selected = song.copyWith(extras: {
          ...?song.extras,
          'url': url,
        });
        final items = queue.value;
        if (currentIndex is int &&
            currentIndex >= 0 &&
            currentIndex < items.length &&
            items[currentIndex].id == song.id) {
          items[currentIndex] = selected;
        }
        mediaItem.add(selected);
        if (GetPlatform.isWeb && stream != null) {
          if (!await _setAudioSourceWeb(selected, stream, request)) return;
        } else {
          if (local) isPlayingUsingLockCachingSource = false;
          await _playList.add(local
              ? _createLocalAudioSource(url, selected)
              : _createAudioSource(selected));
          if (!_operations.isCurrent(request)) return;
          if (local) await _initializeWebPlaylist();
        }
        if (!_operations.isCurrent(request)) return;
        if (loudnessNormalizationEnabled &&
            GetPlatform.isAndroid &&
            stream != null) {
          _normalizeVolume(stream.audio!.loudnessDb);
        }
        if (restoreSession && !GetPlatform.isDesktop) {
          await _player.load();
          if (!_operations.isCurrent(request)) return;
          await _player.seek(position);
          if (!_operations.isCurrent(request)) return;
        }
        isSongLoading = false;
        _lastWatchdogPosition = _player.position;
        _lastWatchdogCheck = DateTime.now();
        printINFO('[Playback timing] ${song.id}: source ready '
            '${timing.elapsedMilliseconds} ms total');
        if (!restoreSession) _startPlayback(request);
      });
    } catch (error) {
      if (!_operations.isCurrent(request)) return;
      printERROR('Could not load ${song.id}: $error');
      // Some backends report an HTTP failure through the load Future itself.
      // Use the same bounded recovery as asynchronous playback errors.
      final url = currentSongUrl;
      if (_wantsPlayback &&
          !_automaticRetryUsed &&
          url != null &&
          (url.startsWith('https://') || url.startsWith('http://'))) {
        isSongLoading = false;
        await _recoverPlayback();
      } else {
        await _failPlayback(
            request, local ? 'Unable to play this file.' : 'networkError');
      }
    }
  }

  Future<void> _failPlayback(int request, String message) async {
    await _operations.run(request, () async {
      try {
        await _player.pause();
      } catch (error) {
        printERROR('Could not pause failed playback: $error');
      }
      if (!_operations.isCurrent(request)) return;
      isSongLoading = false;
      _wantsPlayback = false;
      currentSongUrl = null;
      playbackState.add(playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.error,
          errorCode: 500,
          errorMessage: message));
      if (Get.isRegistered<PlayerController>() && Get.context != null) {
        Get.find<PlayerController>().notifyPlayError(message);
      }
    });
  }

  Future<void> _recoverPlayback({bool stalled = false}) async {
    final request = _operations.current;
    if (_disposed ||
        !_wantsPlayback ||
        isSongLoading ||
        !_operations.beginRecovery(request)) {
      return;
    }
    final index = currentIndex;
    final items = queue.value;
    final url = currentSongUrl;
    final savedPosition = _player.position;
    try {
      if (index is! int || index < 0 || index >= items.length) return;
      if (stalled && !_automaticRetryUsed) {
        await _operations.run(request, _player.pause);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!_operations.isCurrent(request) || !_wantsPlayback) return;
        await _operations.run(request, () async => _startPlayback(request));
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!_operations.isCurrent(request) || !_wantsPlayback) return;
        if ((_player.position - savedPosition).inMilliseconds.abs() >= 200) {
          return;
        }
      }
      if (!_operations.isCurrent(request) || !_wantsPlayback) return;
      final remote = url != null &&
          (url.startsWith('http://') || url.startsWith('https://'));
      if (!remote || _automaticRetryUsed) {
        await _failPlayback(
            request, remote ? 'networkError' : 'Unable to play this file.');
        return;
      }
      _automaticRetryUsed = true;
      _nextStream.clear();
      await Hive.box('SongsUrlCache').delete(items[index].id);
      if (!_operations.isCurrent(request) || !_wantsPlayback) return;
      final reload = _selectTrack(items[index], index,
          newUrl: true, expectedGeneration: request);
      final replacement = _operations.current;
      await reload;
      if (savedPosition.inSeconds <= 2) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!_operations.isCurrent(replacement) ||
          !_wantsPlayback ||
          isSongLoading) {
        return;
      }
      await _operations.run(replacement, () async {
        final duration = _player.duration;
        if (duration != null && savedPosition < duration) {
          await _player.seek(savedPosition);
          if (_operations.isCurrent(replacement)) {
            _lastWatchdogPosition = _player.position;
            _lastWatchdogCheck = DateTime.now();
          }
        }
      });
    } catch (error) {
      if (_operations.isCurrent(request)) {
        await _failPlayback(request, 'networkError');
      }
      printERROR('Playback recovery failed: $error');
    } finally {
      _operations.endRecovery(request);
    }
  }

  @override
  Future<void> play() async {
    if (_disposed || isSongLoading) return;
    if (currentSongUrl == null ||
        (GetPlatform.isDesktop &&
            _player.duration == null &&
            _player.position == Duration.zero)) {
      if (currentIndex != null && queue.value.isNotEmpty) {
        await customAction('playByIndex', {'index': currentIndex});
      }
      return;
    }
    final request = _operations.begin();
    _wantsPlayback = true;
    _automaticRetryUsed = false;
    await _operations.run(request, () async => _startPlayback(request));
  }

  void _startPlayback(int request) {
    if (!_operations.isCurrent(request) || !_wantsPlayback) return;
    // On some backends play() completes only when playback is paused/stopped.
    // Never keep the mutation queue locked for that lifetime.
    unawaited(
        _playPlayer(request).catchError((Object error, StackTrace stack) async {
      if (_operations.isCurrent(request)) await _recoverPlayback();
    }));
  }

  Future<void> _playPlayer(int request) async {
    try {
      await _player.play();
    } catch (error, stackTrace) {
      if (!_operations.isCurrent(request)) return;
      if (!GetPlatform.isWeb) Error.throwWithStackTrace(error, stackTrace);
      await _failPlayback(request,
          'The browser could not start audio. Press Play to try again.');
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    final request = _operations.begin();
    _wantsPlayback = false;
    isSongLoading = false;
    await _operations.run(request, _player.pause);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed || isSongLoading) return;
    final request = _operations.begin();
    await _operations.run(request, () => _player.seek(position));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await customAction('playByIndex', {'index': index});
  }

  int _getNextSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex + 1 >= shuffledQueue.length) {
        shuffledQueue.shuffle();
        currentShuffleIndex = 0;
      } else {
        currentShuffleIndex += 1;
      }
      return queue.value.indexWhere(
        (item) => item.id == shuffledQueue[currentShuffleIndex],
      );
    }

    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else if (queueLoopModeEnabled) {
      return 0;
    } else {
      return currentIndex;
    }
  }

  int _getPrevSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex - 1 < 0) {
        shuffledQueue.shuffle();
        currentShuffleIndex = shuffledQueue.length - 1;
      } else {
        currentShuffleIndex -= 1;
      }
      return queue.value.indexWhere(
        (item) => item.id == shuffledQueue[currentShuffleIndex],
      );
    }

    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
    } else {
      return currentIndex;
    }
  }

  @override
  Future<void> skipToNext() async {
    final index = _getNextSongIndex();
    if (index != currentIndex) {
      await customAction("playByIndex", {'index': index});
    } else {
      await pause();
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inMilliseconds > 5000) {
      await seek(Duration.zero);
      return;
    }
    final index = _getPrevSongIndex();
    if (index != currentIndex) {
      await customAction("playByIndex", {'index': index});
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    if (repeatMode == AudioServiceRepeatMode.none) {
      loopModeEnabled = false;
    } else {
      loopModeEnabled = true;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      shuffleModeEnabled = false;
      shuffledQueue.clear();
    } else {
      _shuffleCmd(currentIndex);
      shuffleModeEnabled = true;
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'dispose':
        if (_disposed) return;
        _disposed = true;
        _wantsPlayback = false;
        _nextStream.clear();
        final request = _operations.begin();
        await _operations.run(request, _player.dispose);
        await super.stop();
        break;

      case 'playByIndex':
        final index = extras!['index'] as int;
        if (index < 0 || index >= queue.value.length) return;
        await _selectTrack(queue.value[index], index,
            newUrl: extras['newUrl'] == true,
            restoreSession: extras['restoreSession'] == true,
            position: Duration(milliseconds: extras['position'] as int? ?? 0));
        break;

      case 'playLocalFile':
        await _selectTrack(extras!['song'] as MediaItem, extras['index'] as int,
            localFile: true);
        break;

      case 'checkWithCacheDb':
        if (isPlayingUsingLockCachingSource) {
          final song = extras!['mediaItem'] as MediaItem;
          final songsCacheBox = Hive.box("SongsCache");
          if (!songsCacheBox.containsKey(song.id) &&
              await File("$_cacheDir/cachedSongs/${song.id}.mp3").exists()) {
            song.extras!['url'] = currentSongUrl;
            song.extras!['date'] = DateTime.now().millisecondsSinceEpoch;
            final dbStreamData = Hive.box("SongsUrlCache").get(song.id);
            final jsonData = MediaItemBuilder.toJson(song);
            jsonData['duration'] = _player.duration!.inSeconds;
            // playbility status and info
            jsonData['streamInfo'] = dbStreamData != null
                ? [
                    true,
                    dbStreamData[
                        Hive.box('AppPrefs').get('streamingQuality') == 0
                            ? 'lowQualityAudio'
                            : "highQualityAudio"],
                  ]
                : null;
            await PlaylistSongStore.put('SongsCache', song.id, jsonData);
            LibrarySongsController librarySongsController =
                Get.find<LibrarySongsController>();
            if (!librarySongsController.isClosed) {
              librarySongsController.librarySongsList.value =
                  librarySongsController.librarySongsList.toList() + [song];
            }
          }
        }
        break;

      case 'setSourceNPlay':
        final song = extras!['mediaItem'] as MediaItem;
        queue.add([song]);
        await _selectTrack(song, 0);
        break;

      case 'toggleSkipSilence':
        final enable = (extras!['enable'] as bool);
        await _player.setSkipSilenceEnabled(enable);
        break;

      case 'toggleLoudnessNormalization':
        loudnessNormalizationEnabled = (extras!['enable'] as bool);
        if (!loudnessNormalizationEnabled) {
          _player.setVolume(1.0);
          return;
        }

        if (loudnessNormalizationEnabled) {
          try {
            final currentSongId = (queue.value[currentIndex]).id;
            if (Hive.box("SongsUrlCache").containsKey(currentSongId)) {
              final songJson = Hive.box("SongsUrlCache").get(currentSongId);
              _normalizeVolume((songJson)["highQualityAudio"]["loudnessDb"]);
              return;
            }

            if (Hive.box("SongDownloads").containsKey(currentSongId)) {
              final streamInfo =
                  (Hive.box("SongDownloads").get(currentSongId))["streamInfo"];

              _normalizeVolume(
                streamInfo == null ? 0 : streamInfo[1]["loudnessDb"],
              );
            }
          } catch (e) {
            printERROR(e);
          }
        }
        break;

      case 'shuffleQueue':
        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        currentQueue.remove(currentItem);
        currentQueue.shuffle();
        currentQueue.insert(0, currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        currentIndex = 0;
        break;

      case 'reorderQueue':
        final oldIndex = extras!['oldIndex'];
        int newIndex = extras['newIndex'];

        if (oldIndex < newIndex) {
          newIndex--;
        }

        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        final item = currentQueue.removeAt(oldIndex);
        currentQueue.insert(newIndex, item);
        currentIndex = currentQueue.indexOf(currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        break;

      case 'addPlayNextItem':
        final song = extras!['mediaItem'] as MediaItem;
        final currentQueue = queue.value;
        currentQueue.insert(currentIndex + 1, song);
        queue.add(currentQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.insert(currentShuffleIndex + 1, song.id);
        }
        break;

      case 'openEqualizer':
        EqualizerService.openEqualizer(_player.androidAudioSessionId!);
        break;

      case 'saveSession':
        await saveSessionData();
        break;

      case 'setVolume':
        _player.setVolume(extras!['value'] / 100);
        break;

      case 'shuffleCmd':
        final songIndex = extras!['index'];
        _shuffleCmd(songIndex);
        break;

      case 'upadateMediaItemInAudioService':
        //added to update media item from player controller
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        final currentSong = queue.value[currentIndex];
        final songWithDuration =
            (_player.duration != null && _player.duration != Duration.zero)
                ? currentSong.copyWith(duration: _player.duration)
                : currentSong;
        mediaItem.add(songWithDuration);
        break;

      case 'toggleQueueLoopMode':
        queueLoopModeEnabled = extras!['enable'];
        break;

      case 'clearQueue':
        customAction("reorderQueue", {'oldIndex': currentIndex, 'newIndex': 0});
        final newQueue = queue.value;
        newQueue.removeRange(1, newQueue.length);
        queue.add(newQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.clear();
          shuffledQueue.add(newQueue[0].id);
          currentShuffleIndex = 0;
        }
        break;
      default:
        break;
    }
  }

  void _shuffleCmd(int index) {
    final queueIds = queue.value.toList().map((item) => item.id).toList();
    final currentSongId = queueIds.removeAt(index);
    queueIds.shuffle();
    queueIds.insert(0, currentSongId);
    shuffledQueue.replaceRange(0, shuffledQueue.length, queueIds);
    currentShuffleIndex = 0;
  }

  void _normalizeVolume(double currentLoudnessDb) {
    double loudnessDifference = -5 - currentLoudnessDb;

    // Converted loudness difference to a volume multiplier
    // We use a factor to convert dB difference to a linear scale
    // 10^(difference / 20) converts dB difference to a linear volume factor
    final volumeAdjustment = pow(10.0, loudnessDifference / 20.0);
    printINFO(
      "loudness:$currentLoudnessDb Normalized volume: $volumeAdjustment",
    );
    _player.setVolume(volumeAdjustment.toDouble().clamp(0, 1.0));
  }

  Future<void> saveSessionData() async {
    if (Get.find<SettingsScreenController>().restorePlaybackSession.isFalse) {
      return;
    }
    final currQueue = queue.value;
    if (currQueue.isNotEmpty) {
      final queueData =
          currQueue.map((e) => MediaItemBuilder.toJson(e)).toList();
      final currIndex = currentIndex ?? 0;
      final position = _player.position.inMilliseconds;
      final prevSessionData = await Hive.openBox("prevSessionData");
      await prevSessionData.clear();
      await prevSessionData.putAll({
        "queue": queueData,
        "position": position,
        "index": currIndex,
      });
      await prevSessionData.close();
      printINFO("Saved session data");
    }
  }

  /// Android Auto
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    return _mediaLibrary.getByRootId(parentMediaId);
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return Stream.fromFuture(
      _mediaLibrary.getByRootId(parentMediaId).then((items) => items),
    ).map((_) => <String, dynamic>{}).shareValue();
  }

  // only for Android Auto
  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    customEvent.add({
      'eventType': 'playFromMediaId',
      'songId': mediaId,
      'libraryId': extras!['libraryId'],
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    final stopForegroundService =
        Get.find<SettingsScreenController>().stopPlyabackOnSwipeAway.value;
    if (stopForegroundService) {
      await Get.find<HomeScreenController>().cachedHomeScreenData();
      await saveSessionData();
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    final request = _operations.begin();
    _wantsPlayback = false;
    isSongLoading = false;
    _nextStream.clear();
    await _operations.run(request, _player.stop);
    if (_operations.isCurrent(request)) await super.stop();
  }

  // Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(
    String songId, {
    bool generateNewUrl = false,
    bool offlineReplacementUrl = false,
    bool cacheResult = true,
  }) async {
    printINFO("Requested id : $songId");

    // Check if songId is a local audio file
    if (!GetPlatform.isWeb && await File(songId).exists()) {
      printINFO("Playing local file: $songId");
      final localAudio = Audio(
        itag: 140,
        audioCodec: Codec.mp4a,
        bitrate: 320000,
        duration: 0,
        loudnessDb: 0,
        url: songId,
        size: await File(songId).length(),
      );
      return HMStreamingData(
        playable: true,
        statusMSG: "OK",
        lowQualityAudio: localAudio,
        highQualityAudio: localAudio,
      );
    }
    final songDownloadsBox = Hive.box("SongDownloads");
    if (!GetPlatform.isWeb &&
        !offlineReplacementUrl &&
        (await Hive.openBox("SongsCache")).containsKey(songId)) {
      printINFO("Got Song from cachedbox ($songId)");
      // if contains stream Info
      final streamInfo = Hive.box("SongsCache").get(songId)["streamInfo"];
      Audio? cacheAudioPlaceholder;
      if (streamInfo != null && streamInfo.isNotEmpty) {
        streamInfo[1]['url'] = "file://$_cacheDir/cachedSongs/$songId.mp3";
        cacheAudioPlaceholder = Audio.fromJson(streamInfo[1]);
      } else {
        cacheAudioPlaceholder = Audio(
          audioCodec: Codec.mp4a,
          bitrate: 0,
          loudnessDb: 0,
          duration: 0,
          size: 0,
          url: "file://$_cacheDir/cachedSongs/$songId.mp3",
          itag: 0,
        );
      }

      return HMStreamingData(
        playable: true,
        statusMSG: "OK",
        lowQualityAudio: cacheAudioPlaceholder,
        highQualityAudio: cacheAudioPlaceholder,
      );
    } else if (!GetPlatform.isWeb &&
        !offlineReplacementUrl &&
        songDownloadsBox.containsKey(songId)) {
      final song = songDownloadsBox.get(songId);
      final streamInfoJson = song["streamInfo"];
      Audio? audio;
      final path = song['url'];
      if (streamInfoJson != null && streamInfoJson.isNotEmpty) {
        audio = Audio.fromJson(streamInfoJson[1]);
      } else {
        audio = Audio(
          itag: 140,
          audioCodec: Codec.mp4a,
          bitrate: 0,
          duration: 0,
          loudnessDb: 0,
          url: path,
          size: 0,
        );
      }

      final streamInfo = HMStreamingData(
        playable: true,
        statusMSG: "OK",
        highQualityAudio: audio,
        lowQualityAudio: audio,
      );

      if (path.contains(
        "${Get.find<SettingsScreenController>().supportDirPath}/Music",
      )) {
        return streamInfo;
      }
      //check file access and if file exist in storage
      final status = await PermissionService.getExtStoragePermission();
      if (status && await File(path).exists()) {
        return streamInfo;
      }
      //in case file doesnot found in storage, song will be played online
      return checkNGetUrl(songId,
          offlineReplacementUrl: true,
          generateNewUrl: generateNewUrl,
          cacheResult: cacheResult);
    } else {
      if (GetPlatform.isWeb) {
        final videoId =
            songId.startsWith('MPED') ? songId.substring(4) : songId;
        final stream = await StreamProvider.fetch(videoId);
        return HMStreamingData.fromJson(stream.hmStreamingData);
      }

      //check if song stream url is cached and allocate url accordingly
      final songsUrlCacheBox = Hive.box("SongsUrlCache");
      final qualityIndex = Hive.box('AppPrefs').get('streamingQuality') ?? 1;
      HMStreamingData? streamInfo;
      if (songsUrlCacheBox.containsKey(songId) && !generateNewUrl) {
        final streamInfoJson = songsUrlCacheBox.get(songId);
        if (streamInfoJson.runtimeType.toString().contains("Map") &&
            !isExpired(url: (streamInfoJson['lowQualityAudio']['url']))) {
          printINFO("Got cached Url ($songId)");
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        }
      }

      if (streamInfo == null) {
        final token = RootIsolateToken.instance;
        final streamInfoJson = await Isolate.run(
          () => getStreamInfo(songId, token),
        );
        streamInfo = HMStreamingData.fromJson(streamInfoJson);
        if (streamInfo.playable && cacheResult) {
          await songsUrlCacheBox.put(songId, streamInfoJson);
        }
      }

      streamInfo.setQualityIndex(qualityIndex as int);
      return streamInfo;
    }
  }
}

class UrlError extends Error {
  String message() => 'Unable to fetch url';
}

// for Android Auto
class MediaLibrary {
  static const albumsRootId = 'albums';
  static const songsRootId = 'songs';
  static const favoritesRootId = "LIBFAV";
  static const playlistsRootId = 'playlists';

  Future<List<MediaItem>> getByRootId(String id) async {
    switch (id) {
      case AudioService.browsableRootId:
        return Future.value(getRoot());
      case songsRootId:
        return getLibSongs("SongDownloads");
      case favoritesRootId:
        return getLibSongs("LIBFAV");
      case albumsRootId:
        return getAlbums();
      case playlistsRootId:
        return getPlaylists();
      case AudioService.recentRootId:
        return getLibSongs("LIBRP");
      default:
        return getLibSongs(id);
    }
  }

  List<MediaItem> getRoot() {
    return [
      MediaItem(id: songsRootId, title: "songs".tr, playable: false),
      MediaItem(id: favoritesRootId, title: "favorites".tr, playable: false),
      MediaItem(id: albumsRootId, title: "albums".tr, playable: false),
      MediaItem(id: playlistsRootId, title: "playlists".tr, playable: false),
    ];
  }

  Future<List<MediaItem>> getAlbums() async {
    final box = await Hive.openBox("LibraryAlbums");
    final albums =
        box.values.map((item) => Album.fromJson(item).toMediaItem()).toList();
    await box.close();
    return albums;
  }

  Future<List<MediaItem>> getPlaylists() async {
    final box = await Hive.openBox("LibraryPlaylists");
    final playlists = [
      ...LibraryPlaylistsController.initPlst.map((e) => e.toMediaItem()),
      ...(box.values
          .map((item) => Playlist.fromJson(item).toMediaItem())
          .toList()),
    ];
    await box.close();
    return playlists;
  }

  Future<List<MediaItem>> getLibSongs(String libId) async {
    Box<dynamic> box;
    try {
      box = await Hive.openBox(libId);
    } catch (e) {
      box = await Hive.openBox(libId);
    }
    final songs = box.values.toList().map((e) {
      final song = MediaItemBuilder.fromJson(e);
      return MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        artUri: song.artUri,
        extras: {"libraryId": libId},
        playable: true,
      );
    }).toList();

    if (!libId.contains("SongDownloads")) {
      await box.close();
    }

    if (libId == "LIBRP") {
      return songs.reversed.toList();
    }

    return songs;
  }
}
