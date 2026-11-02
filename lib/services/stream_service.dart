import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'invidious_service.dart';
import 'utils.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider({
    required this.playable,
    this.audioFormats,
    this.statusMSG = "",
  });

  static Future<StreamProvider> fetch(String videoId) async {
    if (kIsWeb) {
      return _fetchInvidious(videoId);
    }

    final yt = YoutubeExplode();
    try {
      // Explicitly specify clients in priority order so we don't depend on
      // library defaults. tv works without signature decoding and on restricted
      // videos; ios is reliable for audio-only streams; androidVr is a fallback.
      final res = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.visionos,
          YoutubeApiClient.ios,
          YoutubeApiClient.androidMusic,
          YoutubeApiClient.safari,
        ],
      );
      final audio = res.audioOnly;
      return StreamProvider(
        playable: true,
        statusMSG: "OK",
        audioFormats: audio
            .map(
              (e) => Audio(
                itag: e.tag,
                audioCodec: e.audioCodec.contains('mp')
                    ? Codec.mp4a
                    : Codec.opus,
                bitrate: e.bitrate.bitsPerSecond,
                duration: e.duration ?? 0,
                loudnessDb: e.loudnessDb,
                url: e.url.toString(),
                size: e.size.totalBytes,
              ),
            )
            .toList(),
      );
    } catch (e) {
      if (e is SocketException) {
        return StreamProvider(playable: false, statusMSG: "networkError");
      } else if (e is VideoUnplayableException) {
        return StreamProvider(playable: false, statusMSG: "Song is unplayable");
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song requires purchase",
        );
      } else if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song is unavailable",
        );
      } else if (e is YoutubeExplodeException) {
        return StreamProvider(playable: false, statusMSG: e.message);
      } else {
        return StreamProvider(
          playable: false,
          statusMSG: "Unknown error occurred",
        );
      }
    } finally {
      yt.close();
    }
  }

  static Future<StreamProvider> _fetchInvidious(String videoId) async {
    try {
      final invidious = Get.find<InvidiousService>();
      final candidateRegions = ['US', 'GB', 'IN', 'DE', ''];

      for (final region in candidateRegions) {
        try {
          final video = await invidious.video(
            videoId,
            local: true,
            region: region.isEmpty ? null : region,
          );

          final durationMs =
              ((int.tryParse(video['lengthSeconds']?.toString() ?? '') ?? 0) *
                      1000)
                  .toInt();

          List<Audio> parseFormats(List? rawFormats) {
            return (rawFormats ?? const [])
                .whereType<Map>()
                .where(
                  (format) =>
                      (format['type'] as String? ?? '').startsWith('audio/'),
                )
                .map((format) {
                  final itag = int.tryParse(format['itag']?.toString() ?? '');
                  final url = format['url'] as String?;
                  if (itag == null || url == null || url.isEmpty) return null;

                  if (isExpired(url: url)) return null;

                  final codecDescription =
                      '${format['encoding'] ?? ''} ${format['type'] ?? ''}'
                          .toLowerCase();
                  return Audio(
                    itag: itag,
                    audioCodec: codecDescription.contains('aac') ||
                            codecDescription.contains('mp4a')
                        ? Codec.mp4a
                        : Codec.opus,
                    bitrate:
                        int.tryParse(format['bitrate']?.toString() ?? '') ?? 0,
                    duration: durationMs,
                    loudnessDb:
                        double.tryParse(video['loudness']?.toString() ?? '') ??
                            0,
                    url: url,
                    size: int.tryParse(format['size']?.toString() ?? '') ?? 0,
                  );
                })
                .whereType<Audio>()
                .toList();
          }

          var formats = parseFormats(video['adaptiveFormats'] as List?);
          if (formats.isEmpty) {
            try {
              final directVideo = await invidious.video(
                videoId,
                local: false,
                region: region.isEmpty ? null : region,
              );
              formats = parseFormats(directVideo['adaptiveFormats'] as List?);
            } catch (_) {}
          }

          if (formats.isNotEmpty) {
            return StreamProvider(
              playable: true,
              statusMSG: "OK",
              audioFormats: formats,
            );
          }
        } catch (_) {
          continue;
        }
      }

      return StreamProvider(
        playable: false,
        statusMSG: "Invidious returned no playable audio streams",
      );
    } catch (error) {
      return StreamProvider(
        playable: false,
        statusMSG: "Invidious playback failed: $error",
      );
    }
  }

  bool get _usesAacForNativePlayback =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Audio? get highestQualityAudio => _usesAacForNativePlayback
      ? highestBitrateMp4aAudio
      : audioFormats?.lastWhere(
          (item) => item.itag == 251 || item.itag == 140,
          orElse: () => audioFormats!.first,
        );

  Audio? get highestBitrateMp4aAudio {
    final mp4aFormats = audioFormats
        ?.where((item) => item.audioCodec == Codec.mp4a)
        .toList();
    if (mp4aFormats == null || mp4aFormats.isEmpty) {
      return audioFormats?.first;
    }
    return mp4aFormats.lastWhere(
      (item) => item.itag == 140 || item.itag == 139,
      orElse: () => mp4aFormats.first,
    );
  }

  Audio? get highestBitrateOpusAudio => audioFormats?.lastWhere(
    (item) => item.itag == 251 || item.itag == 250,
    orElse: () => audioFormats!.first,
  );

  Audio? get lowQualityAudio => _usesAacForNativePlayback
      ? highestBitrateMp4aAudio
      : audioFormats?.lastWhere(
          (item) => item.itag == 249 || item.itag == 139,
          orElse: () => audioFormats!.first,
        );

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson(),
      "allAudioFormats": audioFormats?.map((e) => e.toJson()).toList(),
    };
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  Audio({
    required this.itag,
    required this.audioCodec,
    required this.bitrate,
    required this.duration,
    required this.loudnessDb,
    required this.url,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
    "itag": itag,
    "audioCodec": audioCodec.toString(),
    "bitrate": bitrate,
    "loudnessDb": loudnessDb,
    "url": url,
    "approxDurationMs": duration,
    "size": size,
  };

  factory Audio.fromJson(json) => Audio(
    audioCodec: (json["audioCodec"] as String).contains("mp4a")
        ? Codec.mp4a
        : Codec.opus,
    itag: json['itag'],
    duration: json["approxDurationMs"] ?? 0,
    bitrate: json["bitrate"] ?? 0,
    loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
    url: json['url'],
    size: json["size"] ?? 0,
  );
}

enum Codec { mp4a, opus }
