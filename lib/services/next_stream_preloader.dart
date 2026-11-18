import '../models/hm_streaming_data.dart';
import 'utils.dart';

/// Prepares metadata for one track, without creating or starting an audio source.
class NextStreamPreloader {
  NextStreamPreloader({this.waitTimeout = const Duration(seconds: 2)});
  final Duration waitTimeout;
  String? _songId;
  Future<HMStreamingData?>? _result;
  bool _busy = false;

  void prepare(String songId, Future<HMStreamingData> Function() fetch) {
    if (_busy || songId == _songId) return;
    _songId = songId;
    _busy = true;
    _result = Future<HMStreamingData>.sync(fetch)
        .then<HMStreamingData?>((value) => value,
            onError: (Object error, StackTrace stack) => null)
        .whenComplete(() => _busy = false);
  }

  Future<HMStreamingData?> take(String songId, {required int quality}) async {
    if (songId != _songId) return null;
    final result = _result;
    clear();
    // Timing out releases the foreground caller, not the background fetch slot.
    final data = await result?.timeout(waitTimeout, onTimeout: () => null);
    if (data == null || !data.playable) return null;
    data.setQualityIndex(quality);
    final audio = data.audio;
    return audio != null && !isExpired(url: audio.url) ? data : null;
  }

  void clear() {
    _songId = null;
    _result = null;
    // An in-flight fetch still owns the slot until it finishes.
  }
}
