import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../../services/permission_service.dart';
import '../../../utils/audio_metadata_reader.dart';
import '../../../utils/helper.dart';
import '../../widgets/snackbar.dart';
import '../Settings/settings_screen_controller.dart';

class LocalSongsController extends GetxController {
  final RxList<MediaItem> localSongsList = RxList();
  final RxList<MediaItem> filteredSongsList = RxList();
  final RxString searchQuery = ''.obs;
  final TextEditingController searchController = TextEditingController();
  final isFetched = false.obs;
  final isScanning = false.obs;

  static const _hiveBox = 'LocalSongs';
  static const _foldersBox = 'LocalFolders';

  static const _supportedAudioExts = {
    '.mp3',
    '.m4a',
    '.flac',
    '.wav',
    '.ogg',
    '.aac',
    '.opus',
    '.wma',
  };

  @override
  void onInit() {
    super.onInit();
    _loadFromHive();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  void onSearch(String query) {
    searchQuery.value = query;
    _applyFilter();
  }

  void clearSearch() {
    searchQuery.value = '';
    searchController.clear();
    _applyFilter();
  }

  void _applyFilter() {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) {
      filteredSongsList.value = List.from(localSongsList);
    } else {
      filteredSongsList.value = localSongsList.where((song) {
        final title = song.title.toLowerCase();
        final artist = (song.artist ?? '').toLowerCase();
        final album = (song.album ?? '').toLowerCase();
        return title.contains(query) ||
            artist.contains(query) ||
            album.contains(query);
      }).toList();
    }
  }

  /// Load previously saved local song metadata from Hive
  Future<void> _loadFromHive() async {
    final box = await Hive.openBox(_hiveBox);
    final items = <MediaItem>[];
    for (final key in box.keys) {
      final json = box.get(key);
      if (json is Map) {
        try {
          items.add(_fromJson(Map<String, dynamic>.from(json)));
        } catch (e) {
          printERROR('LocalSongs: corrupt entry $key: $e');
        }
      }
    }
    localSongsList.value = items;
    _applyFilter();
    isFetched.value = true;

    // Background thumbnail repair for songs that don't have cached thumbnails yet
    _repairMissingThumbnails(items);
  }

  Future<void> _repairMissingThumbnails(List<MediaItem> items) async {
    try {
      final supportDir = Get.find<SettingsScreenController>().supportDirPath;
      final thumbDir = Directory('$supportDir/thumbnails');
      if (!await thumbDir.exists()) {
        await thumbDir.create(recursive: true);
      }

      bool updatedAny = false;
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final thumbFile = File('${thumbDir.path}/${item.id}.png');
        if (!await thumbFile.exists()) {
          final filePath = item.extras?['url'] as String?;
          if (filePath != null && await File(filePath).exists()) {
            final metadata = await AudioMetadataReader.readMetadata(filePath);
            if (metadata.pictureBytes != null &&
                metadata.pictureBytes!.isNotEmpty) {
              await thumbFile.writeAsBytes(metadata.pictureBytes!);
              final updatedItem = item.copyWith(artUri: Uri.file(thumbFile.path));
              items[i] = updatedItem;
              updatedAny = true;
            }
          }
        }
      }
      if (updatedAny) {
        localSongsList.value = List.from(items);
        _applyFilter();
      }
    } catch (e) {
      printERROR('LocalSongs: thumbnail repair error: $e');
    }
  }

  /// Pick an entire directory/folder and recursively import all audio tracks
  Future<void> pickAndAddFolder() async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(
          snackbar(
            Get.context!,
            'Storage permission is required to access local music',
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
      return;
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null || selectedDirectory.isEmpty) return;

    isScanning.value = true;
    try {
      final dir = Directory(selectedDirectory);
      if (!await dir.exists()) {
        isScanning.value = false;
        return;
      }

      // Save scanned folder
      final folderBox = await Hive.openBox(_foldersBox);
      folderBox.put(selectedDirectory, selectedDirectory);

      final box = await Hive.openBox(_hiveBox);
      int added = 0;

      final List<FileSystemEntity> entities = [];
      try {
        await for (final entity in dir
            .list(recursive: true, followLinks: false)
            .handleError((error) {
          printERROR('Error listing entity: $error');
        })) {
          entities.add(entity);
        }
      } catch (e) {
        printERROR('Dir list stream error: $e');
      }

      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_supportedAudioExts.contains(ext)) {
            final path = entity.path;
            if (localSongsList.any((s) => s.extras?['url'] == path)) {
              continue;
            }
            final item = await _buildMediaItem(path);
            if (item != null) {
              await box.put(item.id, _toJson(item));
              localSongsList.add(item);
              added++;
            }
          }
        }
      }

      _applyFilter();
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(
          snackbar(
            Get.context!,
            added > 0
                ? 'Added $added local song(s) from folder'
                : 'No new audio files found in folder',
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
    } catch (e) {
      printERROR('Error scanning folder: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// Pick individual audio files from the device
  Future<void> pickAndAddFiles() async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (Get.context != null) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(
          snackbar(
            Get.context!,
            'Storage permission is required to access local music',
            size: SanckBarSize.MEDIUM,
          ),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final box = await Hive.openBox(_hiveBox);
    int added = 0;
    for (final file in result.files) {
      if (file.path == null) continue;
      final path = file.path!;
      if (localSongsList.any((s) => s.extras?['url'] == path)) continue;

      final item = await _buildMediaItem(path);
      if (item != null) {
        await box.put(item.id, _toJson(item));
        localSongsList.add(item);
        added++;
      }
    }

    _applyFilter();
    if (added > 0 && Get.context != null) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(Get.context!, 'Added $added local song(s)',
            size: SanckBarSize.MEDIUM),
      );
    }
  }

  /// Remove a local song from the list and Hive
  Future<void> removeSong(MediaItem song) async {
    final box = await Hive.openBox(_hiveBox);
    await box.delete(song.id);
    localSongsList.removeWhere((s) => s.id == song.id);
    _applyFilter();

    try {
      final supportDir = Get.find<SettingsScreenController>().supportDirPath;
      final thumbFile = File('$supportDir/thumbnails/${song.id}.png');
      if (await thumbFile.exists()) {
        await thumbFile.delete();
      }
    } catch (e) {
      printERROR('Could not delete thumbnail for ${song.id}: $e');
    }
  }

  /// Build a MediaItem from a local file path, reading ID3 tags and extracting artwork
  Future<MediaItem?> _buildMediaItem(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final songId = 'local_${path.hashCode.abs()}';
      String title = p.basenameWithoutExtension(path);
      String? artist;
      String? album;
      Uri? artUri;

      final supportDir = Get.find<SettingsScreenController>().supportDirPath;
      final thumbDir = Directory('$supportDir/thumbnails');
      final thumbFile = File('${thumbDir.path}/$songId.png');

      if (await thumbFile.exists()) {
        artUri = Uri.file(thumbFile.path);
      }

      final metadata = await AudioMetadataReader.readMetadata(path);
      if (metadata.title != null && metadata.title!.trim().isNotEmpty) {
        title = metadata.title!.trim();
      }
      if (metadata.artist != null && metadata.artist!.trim().isNotEmpty) {
        artist = metadata.artist!.trim();
      }
      if (metadata.album != null && metadata.album!.trim().isNotEmpty) {
        album = metadata.album!.trim();
      }

      if (artUri == null &&
          metadata.pictureBytes != null &&
          metadata.pictureBytes!.isNotEmpty) {
        try {
          if (!await thumbDir.exists()) {
            await thumbDir.create(recursive: true);
          }
          await thumbFile.writeAsBytes(metadata.pictureBytes!);
          artUri = Uri.file(thumbFile.path);
        } catch (e) {
          printERROR('LocalSongs: could not save artwork for $path: $e');
        }
      }

      return MediaItem(
        id: songId,
        title: title,
        artist: artist ?? 'Unknown Artist',
        album: album,
        artUri: artUri,
        extras: {
          'url': path,
          'isLocal': true,
          'resultType': 'song',
        },
      );
    } catch (e) {
      printERROR('LocalSongs: could not build MediaItem for $path: $e');
      return null;
    }
  }

  MediaItem _fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    Uri? artUri;
    try {
      final supportDir = Get.find<SettingsScreenController>().supportDirPath;
      final thumbFile = File('$supportDir/thumbnails/$id.png');
      if (thumbFile.existsSync()) {
        artUri = Uri.file(thumbFile.path);
      }
    } catch (e) {
      printERROR('Error checking thumbnail for $id: $e');
    }

    return MediaItem(
      id: id,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      artUri: artUri,
      playable: true,
      extras: Map<String, dynamic>.from(json['extras'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> _toJson(MediaItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'album': item.album,
      'extras': item.extras,
    };
  }
}
