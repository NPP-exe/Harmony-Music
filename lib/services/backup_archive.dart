import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Extract one entry at a time from disk, retaining no collection of song bytes.
/// Call from a worker isolate; nothing here changes the live application data.
class BackupArchive {
  static List<String> extract(String archivePath, String directory) {
    final input = InputFileStream(archivePath);
    try {
      final zip = ZipDirectory.read(input);
      final files = <String, String>{};
      for (final header in zip.fileHeaders) {
        final name = header.filename;
        final normalized = name.toLowerCase();
        final mode = (header.externalFileAttributes ?? 0) >> 16;
        final fileType = mode & 0xf000;
        if (name.contains('/') ||
            name.contains('\\') ||
            name.contains(':') ||
            name.contains('\u0000') ||
            (header.versionMadeBy >> 8 == 3 &&
                fileType != 0 &&
                fileType != 0x8000) ||
            !RegExp(r'^.+\.(hive|mp3|m4a|opus|aac|png)$')
                .hasMatch(normalized)) {
          throw const FormatException('Invalid backup entry');
        }
        final group = normalized.endsWith('.hive')
            ? 'database'
            : normalized.endsWith('.png')
                ? 'thumbnails'
                : 'Music';
        final relative = p.join(group, group == 'database' ? normalized : name);
        final file = header.file!;
        if (!file.verifyCrc32()) {
          throw const FormatException('Invalid backup checksum');
        }
        final output = File(p.join(directory, relative));
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(file.content, flush: true);
        // ZipFile caches its decompressed data. Release that reference before
        // reading the next song, rather than retaining the entire backup.
        header.file = null;
        // Match the destination filesystem's treatment of repeated basenames.
        files[Platform.isWindows ? relative.toLowerCase() : relative] =
            relative;
      }
      if (!files.containsKey(p.join('database', 'appprefs.hive'))) {
        throw const FormatException('Not a Harmony Music backup');
      }
      return files.values.toList();
    } finally {
      input.closeSync();
    }
  }
}
