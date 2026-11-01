import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';
import '../models/playlist.dart';

/// Valid tracks and rejected titles from an export. Parsing never writes data.
class PlaylistImportData {
  PlaylistImportData._(this.title, this.description, this.thumbnailUrl,
      this.songs, this.rejectedSongTitles);

  final String title;
  final String? description;
  final String thumbnailUrl;
  final List<Map<String, dynamic>> songs;

  /// Preserve the original title verbatim; null means no string title was given.
  final List<String?> rejectedSongTitles;

  static Future<PlaylistImportData> readFile(String path) => Isolate.run(
      () => PlaylistImportData.parse(File(path).readAsStringSync()));

  factory PlaylistImportData.parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['playlistInfo'] is! Map<String, dynamic> ||
        data['songs'] is! List) {
      throw const FormatException('Invalid playlist structure');
    }

    final info = data['playlistInfo'] as Map<String, dynamic>;
    _requireText(info['title']);
    _optionalText(info['description']);
    _optionalText(info['thumbnailUrl']);
    _validateThumbnails(info['thumbnails']);

    final thumbnails = info['thumbnails'] as List?;
    final thumbnail = info['thumbnailUrl'] ??
        (thumbnails != null && thumbnails.isNotEmpty
            ? thumbnails.first['url']
            : null);

    final songs = <Map<String, dynamic>>[];
    final rejectedSongTitles = <String?>[];
    for (final song in data['songs'] as List) {
      try {
        _validateSong(song);
        songs.add(Map<String, dynamic>.from(song));
      } on FormatException {
        rejectedSongTitles.add(_originalTitle(song));
      } on TypeError {
        rejectedSongTitles.add(_originalTitle(song));
      } on ArgumentError {
        rejectedSongTitles.add(_originalTitle(song));
      }
    }

    return PlaylistImportData._(
      info['title'],
      info['description'],
      thumbnail == null || (thumbnail as String).isEmpty
          ? Playlist.thumbPlaceholderUrl
          : thumbnail,
      songs,
      rejectedSongTitles,
    );
  }

  static String? _originalTitle(dynamic song) =>
      song is Map && song['title'] is String ? song['title'] as String : null;

  static void _validateSong(dynamic song) {
    if (song is! Map<String, dynamic>) {
      throw const FormatException('Invalid song');
    }
    _requireText(song['videoId']);
    _requireText(song['title']);
    _optionalText(song['url']);
    _optionalText(song['length']);
    if (song['duration'] != null &&
        (song['duration'] is! int || (song['duration'] as int) < 0)) {
      throw const FormatException('Invalid song duration');
    }
    if (song['length'] != null &&
        !RegExp(r'^\d+(?::\d{1,2}){0,2}$').hasMatch(song['length'])) {
      throw const FormatException('Invalid song length');
    }
    _validateThumbnails(song['thumbnails']);
    final artists = song['artists'];
    if (artists != null) {
      if (artists is! List) {
        throw const FormatException('Invalid artists');
      }
      for (final artist in artists) {
        if (artist is! Map) {
          throw const FormatException('Invalid artist');
        }
        _requireText(artist['name']);
      }
    }
    final album = song['album'];
    if (album != null) {
      if (album is! Map) {
        throw const FormatException('Invalid album');
      }
      _optionalText(album['id']);
      _optionalText(album['name']);
    }
    // Validate reader compatibility while retaining all original metadata.
    MediaItemBuilder.fromJson(song);
  }

  static void _requireText(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Missing or invalid text field');
    }
  }

  static void _optionalText(dynamic value) {
    if (value != null && value is! String) {
      throw const FormatException('Invalid text field');
    }
  }

  static void _validateThumbnails(dynamic thumbnails) {
    if (thumbnails == null) return;
    if (thumbnails is! List) {
      throw const FormatException('Invalid thumbnails');
    }
    for (final thumbnail in thumbnails) {
      if (thumbnail is! Map || thumbnail['url'] is! String) {
        throw const FormatException('Invalid thumbnail');
      }
    }
  }
}

class PlaylistImportService {
  Future<Playlist?> importPlaylist(
    PlaylistImportData data, {
    required String importedLabel,
    required String fallbackDescription,
    void Function(double)? onProgress,
  }) async {
    if (data.songs.isEmpty && data.rejectedSongTitles.isNotEmpty) {
      return null;
    }
    final libraryWasOpen = Hive.isBoxOpen('LibraryPlaylists');
    final library = await Hive.openBox('LibraryPlaylists');
    Box? songsBox;
    String? id;
    try {
      var suffix = DateTime.now().microsecondsSinceEpoch;
      do {
        id = 'LIB${suffix++}';
      } while (library.containsKey(id) || await Hive.boxExists(id));

      final playlist = Playlist(
        title: '${data.title} ($importedLabel)',
        playlistId: id,
        thumbnailUrl: data.thumbnailUrl,
        description: data.description ?? fallbackDescription,
        isCloudPlaylist: false,
      );
      songsBox = await Hive.openBox(id);
      for (var i = 0; i < data.songs.length; i++) {
        await songsBox.put(i, data.songs[i]);
        onProgress?.call((i + 1) / data.songs.length);
      }
      await songsBox.flush();
      // Publish only after all tracks have been persisted successfully.
      await library.put(id, playlist.toJson());
      return playlist;
    } catch (_) {
      // Remove only the records belonging to this import, preserving the library.
      if (id != null) {
        try {
          await library.delete(id);
        } finally {
          if (songsBox != null) await songsBox.deleteFromDisk();
        }
      }
      rethrow;
    } finally {
      if (songsBox?.isOpen ?? false) await songsBox!.close();
      if (!libraryWasOpen && library.isOpen) await library.close();
    }
  }
}
