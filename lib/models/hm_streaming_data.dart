import 'package:harmonymusic/services/stream_service.dart' show Audio;

class HMStreamingData {
  final bool playable;
  final String statusMSG;
  final Audio? lowQualityAudio;
  final Audio? highQualityAudio;
  final List<Audio>? allAudioFormats;
  int qualityIndex = 1;
  HMStreamingData({
    required this.playable,
    required this.statusMSG,
    this.lowQualityAudio,
    this.highQualityAudio,
    this.allAudioFormats,
  });

  setQualityIndex(int index) {
    qualityIndex = index;
  }

  Audio? get audio => qualityIndex == 0 ? lowQualityAudio : highQualityAudio;

  factory HMStreamingData.fromJson(json) {
    if (!json['playable']) {
      return HMStreamingData(
        playable: false,
        statusMSG: json['statusMSG'],
      );
    }
    final lowQualityAudio = json['lowQualityAudio'] != null
        ? Audio.fromJson(json['lowQualityAudio'])
        : null;
    final highQualityAudio = json['highQualityAudio'] != null
        ? Audio.fromJson(json['highQualityAudio'])
        : null;
    final allAudioFormats = (json['allAudioFormats'] as List?)
        ?.whereType<Map>()
        .map((f) => Audio.fromJson(f))
        .toList();
    return HMStreamingData(
      playable: json['playable'],
      statusMSG: json['statusMSG'],
      lowQualityAudio: lowQualityAudio,
      highQualityAudio: highQualityAudio,
      allAudioFormats: allAudioFormats,
    );
  }

  Map<String, dynamic> toJson() => {
    "playable": playable,
    "statusMSG": statusMSG,
    "lowQualityAudio": lowQualityAudio?.toJson(),
    "highQualityAudio": highQualityAudio?.toJson(),
    "allAudioFormats": allAudioFormats?.map((a) => a.toJson()).toList(),
  };
}
