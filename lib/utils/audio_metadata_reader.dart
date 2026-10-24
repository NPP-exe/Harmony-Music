import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'audio_tags.dart';
import 'helper.dart';

class AudioMetadataResult {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? pictureBytes;

  const AudioMetadataResult({
    this.title,
    this.artist,
    this.album,
    this.pictureBytes,
  });
}

class AudioMetadataReader {
  /// Read metadata and embedded/folder artwork for an audio file.
  static Future<AudioMetadataResult> readMetadata(String filePath) async {
    String? title;
    String? artist;
    String? album;
    Uint8List? pictureBytes;

    // 1. Try audiotags plugin (handles Android/iOS/Linux if available, catches Windows dll missing)
    try {
      final tag = await readAudioTags(filePath);
      if (tag != null) {
        if (tag.title != null && tag.title!.trim().isNotEmpty) {
          title = tag.title!.trim();
        }
        if (tag.trackArtist != null && tag.trackArtist!.trim().isNotEmpty) {
          artist = tag.trackArtist!.trim();
        }
        if (tag.album != null && tag.album!.trim().isNotEmpty) {
          album = tag.album!.trim();
        }
        if (tag.pictureBytes != null && tag.pictureBytes!.isNotEmpty) {
          pictureBytes = Uint8List.fromList(tag.pictureBytes!);
        }
      }
    } catch (e) {
      printINFO('AudioTags plugin fallback triggered for $filePath: $e');
    }

    // 2. Pure Dart extraction for formats if picture or metadata is still missing
    if (pictureBytes == null || title == null || artist == null) {
      try {
        final ext = p.extension(filePath).toLowerCase();
        final file = File(filePath);
        if (await file.exists()) {
          final fileLen = await file.length();
          // Read up to first 12MB of file to scan metadata/atoms/artwork
          final readLen = min(fileLen, 12 * 1024 * 1024);
          final raf = await file.open(mode: FileMode.read);
          final bytes = await raf.read(readLen);
          await raf.close();

          if (ext == '.mp3') {
            final id3 = _parseId3(bytes);
            title ??= id3.title;
            artist ??= id3.artist;
            album ??= id3.album;
            pictureBytes ??= id3.pictureBytes;
          } else if (ext == '.flac') {
            final flac = _parseFlac(bytes);
            title ??= flac.title;
            artist ??= flac.artist;
            album ??= flac.album;
            pictureBytes ??= flac.pictureBytes;
          } else if (ext == '.m4a' || ext == '.mp4' || ext == '.aac') {
            final mp4 = _parseMp4(bytes);
            title ??= mp4.title;
            artist ??= mp4.artist;
            album ??= mp4.album;
            pictureBytes ??= mp4.pictureBytes;
          }
        }
      } catch (e) {
        printERROR('Pure Dart metadata parsing failed for $filePath: $e');
      }
    }

    // 3. Fallback to folder cover artwork (cover.jpg, folder.jpg, album.jpg, etc.)
    if (pictureBytes == null || pictureBytes.isEmpty) {
      final folderCover = findFolderCoverImage(filePath);
      if (folderCover != null) {
        try {
          pictureBytes = await folderCover.readAsBytes();
        } catch (e) {
          printERROR('Failed to read folder cover file: $e');
        }
      }
    }

    return AudioMetadataResult(
      title: title,
      artist: artist,
      album: album,
      pictureBytes: pictureBytes,
    );
  }

  static AudioMetadataResult _parseId3(Uint8List bytes) {
    if (bytes.length < 10) return const AudioMetadataResult();
    // Must start with 'ID3'
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return const AudioMetadataResult();
    }

    final majorVersion = bytes[3];
    final flags = bytes[5];
    final tagSize =
        ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);

    final totalTagLen = min(tagSize + 10, bytes.length);
    int offset = 10;

    // Check extended header flag
    if ((flags & 0x40) != 0 && offset + 4 <= totalTagLen) {
      final extHeaderSize = (majorVersion == 4)
          ? (((bytes[offset] & 0x7F) << 21) |
                ((bytes[offset + 1] & 0x7F) << 14) |
                ((bytes[offset + 2] & 0x7F) << 7) |
                (bytes[offset + 3] & 0x7F))
          : ((bytes[offset] << 24) |
                (bytes[offset + 1] << 16) |
                (bytes[offset + 2] << 8) |
                bytes[offset + 3]);
      offset += extHeaderSize;
    }

    String? title;
    String? artist;
    String? album;
    Uint8List? pictureBytes;

    while (offset + 10 <= totalTagLen) {
      if (bytes[offset] == 0) break; // Padding reached

      final frameId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      int frameSize;
      if (majorVersion == 4) {
        frameSize =
            ((bytes[offset + 4] & 0x7F) << 21) |
            ((bytes[offset + 5] & 0x7F) << 14) |
            ((bytes[offset + 6] & 0x7F) << 7) |
            (bytes[offset + 7] & 0x7F);
      } else {
        frameSize =
            (bytes[offset + 4] << 24) |
            (bytes[offset + 5] << 16) |
            (bytes[offset + 6] << 8) |
            bytes[offset + 7];
      }

      offset += 10;
      if (frameSize <= 0 || offset + frameSize > totalTagLen) break;

      final frameData = bytes.sublist(offset, offset + frameSize);
      offset += frameSize;

      if (frameId == 'TIT2' && title == null) {
        title = _decodeId3Text(frameData);
      } else if (frameId == 'TPE1' && artist == null) {
        artist = _decodeId3Text(frameData);
      } else if (frameId == 'TALB' && album == null) {
        album = _decodeId3Text(frameData);
      } else if (frameId == 'APIC' && pictureBytes == null) {
        pictureBytes = _parseApicFrame(frameData);
      }
    }

    return AudioMetadataResult(
      title: title,
      artist: artist,
      album: album,
      pictureBytes: pictureBytes,
    );
  }

  static String? _decodeId3Text(Uint8List frameData) {
    if (frameData.isEmpty) return null;
    final encoding = frameData[0];
    final textBytes = frameData.sublist(1);
    final text = _decodeText(textBytes, encoding);
    return text.isEmpty ? null : text;
  }

  static String _decodeText(Uint8List bytes, int encoding) {
    if (bytes.isEmpty) return '';
    try {
      switch (encoding) {
        case 0: // ISO-8859-1 / Latin-1
          return latin1.decode(bytes).replaceAll('\u0000', '').trim();
        case 1: // UTF-16 with BOM
          if (bytes.length < 2) return '';
          final isLE = bytes[0] == 0xFF && bytes[1] == 0xFE;
          final isBE = bytes[0] == 0xFE && bytes[1] == 0xFF;
          final start = (isLE || isBE) ? 2 : 0;
          final littleEndian = isLE || !isBE;
          final sb = StringBuffer();
          for (int i = start; i + 1 < bytes.length; i += 2) {
            final code = littleEndian
                ? (bytes[i] | (bytes[i + 1] << 8))
                : ((bytes[i] << 8) | bytes[i + 1]);
            if (code == 0) break;
            sb.writeCharCode(code);
          }
          return sb.toString().trim();
        case 2: // UTF-16BE without BOM
          final sb = StringBuffer();
          for (int i = 0; i + 1 < bytes.length; i += 2) {
            final code = (bytes[i] << 8) | bytes[i + 1];
            if (code == 0) break;
            sb.writeCharCode(code);
          }
          return sb.toString().trim();
        case 3: // UTF-8
        default:
          return utf8
              .decode(bytes, allowMalformed: true)
              .replaceAll('\u0000', '')
              .trim();
      }
    } catch (e) {
      printERROR('decodeText error: $e');
      return '';
    }
  }

  static Uint8List? _parseApicFrame(Uint8List data) {
    if (data.length < 5) return null;
    final encoding = data[0];
    int pos = 1;

    // MIME type null-terminated
    int mimeEnd = data.indexOf(0, pos);
    if (mimeEnd == -1) return null;
    pos = mimeEnd + 1;
    if (pos >= data.length) return null;

    // Picture type (1 byte)
    pos++;
    if (pos >= data.length) return null;

    // Description null-terminated
    if (encoding == 1 || encoding == 2) {
      // 2 null bytes aligned
      while (pos + 1 < data.length) {
        if (data[pos] == 0 && data[pos + 1] == 0) {
          pos += 2;
          break;
        }
        pos += 2;
      }
    } else {
      // 1 null byte
      int descEnd = data.indexOf(0, pos);
      if (descEnd != -1) {
        pos = descEnd + 1;
      }
    }

    if (pos >= data.length) return null;

    // Scan for known image magic bytes within first 64 bytes of pos
    for (int i = pos; i < min(pos + 64, data.length - 3); i++) {
      // JPEG: FF D8 FF
      if (data[i] == 0xFF && data[i + 1] == 0xD8 && data[i + 2] == 0xFF) {
        return data.sublist(i);
      }
      // PNG: 89 50 4E 47
      if (i + 4 <= data.length &&
          data[i] == 0x89 &&
          data[i + 1] == 0x50 &&
          data[i + 2] == 0x4E &&
          data[i + 3] == 0x47) {
        return data.sublist(i);
      }
    }

    return data.sublist(pos);
  }

  static AudioMetadataResult _parseFlac(Uint8List bytes) {
    if (bytes.length < 8) return const AudioMetadataResult();
    // Must start with 'fLaC'
    if (bytes[0] != 0x66 ||
        bytes[1] != 0x4C ||
        bytes[2] != 0x61 ||
        bytes[3] != 0x43) {
      return const AudioMetadataResult();
    }

    String? title;
    String? artist;
    String? album;
    Uint8List? pictureBytes;

    int offset = 4;
    bool isLast = false;

    while (!isLast && offset + 4 <= bytes.length) {
      final headerByte = bytes[offset];
      isLast = (headerByte & 0x80) != 0;
      final blockType = headerByte & 0x7F;
      final blockLen =
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;
      if (offset + blockLen > bytes.length) break;

      final blockData = bytes.sublist(offset, offset + blockLen);
      offset += blockLen;

      if (blockType == 4) {
        // VORBIS_COMMENT
        try {
          final bd = ByteData.sublistView(blockData);
          int p = 0;
          if (p + 4 <= blockData.length) {
            final vendorLen = bd.getUint32(p, Endian.little);
            p += 4 + vendorLen;
            if (p + 4 <= blockData.length) {
              final userCommentCount = bd.getUint32(p, Endian.little);
              p += 4;
              for (
                int i = 0;
                i < userCommentCount && p + 4 <= blockData.length;
                i++
              ) {
                final commentLen = bd.getUint32(p, Endian.little);
                p += 4;
                if (p + commentLen <= blockData.length) {
                  final comment = utf8.decode(
                    blockData.sublist(p, p + commentLen),
                    allowMalformed: true,
                  );
                  p += commentLen;
                  final eqIdx = comment.indexOf('=');
                  if (eqIdx != -1) {
                    final key = comment.substring(0, eqIdx).toUpperCase();
                    final val = comment.substring(eqIdx + 1).trim();
                    if (key == 'TITLE' && title == null) title = val;
                    if (key == 'ARTIST' && artist == null) artist = val;
                    if (key == 'ALBUM' && album == null) album = val;
                  }
                }
              }
            }
          }
        } catch (e) {
          printERROR('FLAC vorbis comment parse error: $e');
        }
      } else if (blockType == 6) {
        // PICTURE
        try {
          final bd = ByteData.sublistView(blockData);
          int p = 4; // Skip picture type (4 bytes)
          if (p + 4 <= blockData.length) {
            final mimeLen = bd.getUint32(p, Endian.big);
            p += 4 + mimeLen;
            if (p + 4 <= blockData.length) {
              final descLen = bd.getUint32(p, Endian.big);
              p += 4 + descLen;
              // width(4), height(4), depth(4), colors(4) = 16 bytes
              p += 16;
              if (p + 4 <= blockData.length) {
                final picLen = bd.getUint32(p, Endian.big);
                p += 4;
                if (p + picLen <= blockData.length) {
                  pictureBytes = blockData.sublist(p, p + picLen);
                }
              }
            }
          }
        } catch (e) {
          printERROR('FLAC picture block parse error: $e');
        }
      }
    }

    return AudioMetadataResult(
      title: title,
      artist: artist,
      album: album,
      pictureBytes: pictureBytes,
    );
  }

  static AudioMetadataResult _parseMp4(Uint8List bytes) {
    final results = <String, dynamic>{};
    try {
      _searchMp4Boxes(bytes, 0, bytes.length, results);
    } catch (e) {
      printERROR('MP4 atom search error: $e');
    }
    return AudioMetadataResult(
      title: results['title'] as String?,
      artist: results['artist'] as String?,
      album: results['album'] as String?,
      pictureBytes: results['picture'] as Uint8List?,
    );
  }

  static void _searchMp4Boxes(
    Uint8List data,
    int start,
    int end,
    Map<String, dynamic> results,
  ) {
    int p = start;
    while (p + 8 <= end) {
      int boxSize =
          (data[p] << 24) |
          (data[p + 1] << 16) |
          (data[p + 2] << 8) |
          data[p + 3];
      final boxType = String.fromCharCodes(data.sublist(p + 4, p + 8));

      if (boxSize == 1) {
        // 64-bit size
        if (p + 16 > end) break;
        boxSize =
            (data[p + 12] << 24) |
            (data[p + 13] << 16) |
            (data[p + 14] << 8) |
            data[p + 15];
      } else if (boxSize == 0) {
        boxSize = end - p;
      }
      if (boxSize < 8 || p + boxSize > end) break;

      final contentStart = p + 8;
      final contentEnd = p + boxSize;

      if (boxType == 'moov' || boxType == 'udta' || boxType == 'ilst') {
        _searchMp4Boxes(data, contentStart, contentEnd, results);
      } else if (boxType == 'meta') {
        // meta has 4 bytes version/flags before children
        if (contentStart + 4 <= contentEnd) {
          _searchMp4Boxes(data, contentStart + 4, contentEnd, results);
        }
      } else if (boxType == '©nam' ||
          boxType == '©ART' ||
          boxType == '©alb' ||
          boxType == 'covr') {
        _extractMp4DataBox(data, contentStart, contentEnd, boxType, results);
      }

      p += boxSize;
    }
  }

  static void _extractMp4DataBox(
    Uint8List data,
    int start,
    int end,
    String tagType,
    Map<String, dynamic> results,
  ) {
    int p = start;
    while (p + 8 <= end) {
      final size =
          (data[p] << 24) |
          (data[p + 1] << 16) |
          (data[p + 2] << 8) |
          data[p + 3];
      final type = String.fromCharCodes(data.sublist(p + 4, p + 8));
      if (size < 8 || p + size > end) break;

      if (type == 'data') {
        // 4 bytes size, 4 bytes 'data', 4 bytes flags/type, 4 bytes locale
        final payloadStart = p + 16;
        final payloadEnd = p + size;
        if (payloadStart <= payloadEnd && payloadEnd <= end) {
          final payload = data.sublist(payloadStart, payloadEnd);
          if (tagType == '©nam' && results['title'] == null) {
            results['title'] = utf8
                .decode(payload, allowMalformed: true)
                .trim();
          } else if (tagType == '©ART' && results['artist'] == null) {
            results['artist'] = utf8
                .decode(payload, allowMalformed: true)
                .trim();
          } else if (tagType == '©alb' && results['album'] == null) {
            results['album'] = utf8
                .decode(payload, allowMalformed: true)
                .trim();
          } else if (tagType == 'covr' && results['picture'] == null) {
            results['picture'] = payload;
          }
        }
        break;
      }
      p += size;
    }
  }

  static File? findFolderCoverImage(String audioFilePath) {
    try {
      final parentDir = File(audioFilePath).parent;
      if (!parentDir.existsSync()) return null;

      const targetNames = [
        'cover.jpg',
        'cover.jpeg',
        'cover.png',
        'cover.webp',
        'folder.jpg',
        'folder.jpeg',
        'folder.png',
        'folder.webp',
        'album.jpg',
        'album.jpeg',
        'album.png',
        'album.webp',
        'front.jpg',
        'front.jpeg',
        'front.png',
        'front.webp',
        'art.jpg',
        'art.jpeg',
        'art.png',
      ];

      for (final name in targetNames) {
        final f = File(p.join(parentDir.path, name));
        if (f.existsSync()) return f;
      }

      final entities = parentDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          final base = p.basename(entity.path).toLowerCase();
          if (targetNames.contains(base)) {
            return entity;
          }
        }
      }
    } catch (e) {
      printERROR('findFolderCoverImage error: $e');
    }
    return null;
  }
}
