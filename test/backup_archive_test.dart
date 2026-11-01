import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/backup_archive.dart';
import 'package:path/path.dart' as p;

Uint8List zip(Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final content = utf8.encode(entry.value);
    archive.addFile(ArchiveFile.noCompress(entry.key, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harmony-archive-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  List<String> extract(List<int> bytes) {
    final input = File(p.join(directory.path, 'backup.hmb'))
      ..writeAsBytesSync(bytes);
    return BackupArchive.extract(input.path, p.join(directory.path, 'stage'));
  }

  test('accepts backup audio formats including cache downloads saved as MP3',
      () {
    final files = extract(zip({
      'appprefs.hive': 'preferences',
      'libraryplaylists.hive': 'playlists',
      'track.opus': 'opus audio',
      'track.aac': 'aac audio',
      'track.m4a': 'm4a audio',
      'track.mp3': 'mp3 audio',
      'cover.png': 'art',
    }));
    expect(files.length, 7);
    expect(
        File(p.join(directory.path, 'stage', 'Music', 'track.mp3'))
            .readAsStringSync(),
        'mp3 audio');
  });

  test('rejects playlists, traversal and files outside the backup format', () {
    expect(() => extract(utf8.encode('{"songs": []}')), throwsFormatException);
    expect(() => extract(zip({'notes.png': 'notes'})), throwsFormatException);
    expect(
        () => extract(zip({
              'appprefs.hive': 'preferences',
              '../escape.mp3': 'unexpected',
            })),
        throwsFormatException);
  });

  test('detects a corrupt payload before allowing restoration', () {
    final bytes = zip({'appprefs.hive': 'unique-uncompressed-payload'});
    final header = ByteData.sublistView(bytes);
    // A local ZIP header is 30 bytes, followed by the name and extra fields.
    final offset = 30 +
        header.getUint16(26, Endian.little) +
        header.getUint16(28, Endian.little);
    bytes[offset] ^= 1;
    expect(() => extract(bytes), throwsFormatException);
  });
}
