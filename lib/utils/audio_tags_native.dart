import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';

import 'audio_tag_data.dart';

Future<AudioTagData?> readAudioTags(String filePath) async {
  final tag = await AudioTags.read(filePath);
  if (tag == null) return null;
  return AudioTagData(
    title: tag.title,
    trackArtist: tag.trackArtist,
    album: tag.album,
    pictureBytes: tag.pictures.isEmpty ? null : tag.pictures.first.bytes,
  );
}

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
}) async {
  final tag = Tag(
    title: title,
    trackArtist: artist,
    album: album,
    year: year,
    trackNumber: trackNumber,
    trackTotal: trackTotal,
    albumArtist: artist,
    genre: genre,
    pictures: coverBytes == null
        ? []
        : [
            Picture(
              bytes: coverBytes,
              mimeType: MimeType.png,
              pictureType: PictureType.coverFront,
            ),
          ],
  );
  await AudioTags.write(filePath, tag);
}
