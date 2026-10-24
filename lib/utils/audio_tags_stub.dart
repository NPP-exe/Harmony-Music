import 'dart:typed_data';

import 'audio_tag_data.dart';

Future<AudioTagData?> readAudioTags(String filePath) async => null;

Future<void> writeAudioTags(
  String filePath, {
  String? title,
  String? artist,
  String? album,
  int? year,
  String? genre,
  int? trackNumber,
  int? trackTotal,
  Uint8List? coverBytes,
}) async {}
