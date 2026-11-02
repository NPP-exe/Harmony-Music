import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/thumbnail.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../../../base_class/playlist_album_screen_con_base.dart';
import '../../../mixins/additional_opeartion_mixin.dart';
import '../../../models/album.dart' show Album;
import '../../../models/media_Item_builder.dart';
import '../../../models/playlist.dart';
import '../../../services/music_service.dart';
import '../../../services/piped_service.dart';
import '../../../services/playlist_song_store.dart';
import '../../widgets/sort_widget.dart';
import '../Home/home_screen_controller.dart';
import '../Library/library_controller.dart';

///PlaylistScreenController handles playlist screen
///
///Playlist title,image,songs
class PlaylistScreenController extends PlaylistAlbumScreenControllerBase
    with AdditionalOpeartionMixin, GetSingleTickerProviderStateMixin {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final playlist = Playlist(
    title: "",
    playlistId: "",
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
  ).obs;
  final isDefaultPlaylist = false.obs;
  late final playlistSortController = SortWidgetController(
      initialSortType: SortType.Custom,
      isTemporaryPreference: () =>
          playlist.value.isCloudPlaylist &&
          !isDefaultPlaylist.value &&
          !isAddedToLibrary.value &&
          !(Get.isRegistered<LibraryPlaylistsController>() &&
              Get.find<LibraryPlaylistsController>()
                  .containsPlaylist(playlist.value.playlistId)));
  List<PlaylistSongRecord> _records = [];
  List<PlaylistSongRecord> _orderedRecords = [];
  Map<MediaItem, dynamic> _arrangementKeys = Map.identity();
  Map<dynamic, int?> _arrangementAdditions = {};
  StreamSubscription<PlaylistSongChange>? _songChanges;
  Future<void>? _remoteRefresh;
  bool _disposed = false;
  String _searchQuery = '';
  bool get hasUnknownAdditionOrder =>
      _records.any((entry) => entry.additionOrder == null);

  /// Restore the preference before loading songs, so the controls and list agree.
  void loadSortPreference(String playlistId) {
    playlistSortController.loadPreference('playlistSort:$playlistId',
        defaultSortType:
            playlistId == 'LIBFAV' ? SortType.AddedOrder : SortType.Custom);
  }

  @override
  void onSort(SortType sortType, bool isAscending) {
    playlistSortController.setSort(sortType, isAscending);
    _applySort();
  }

  void _setSongs(List<PlaylistSongRecord> songs) {
    if (_disposed) return;
    _records = songs;
    _applySort();
  }

  int _compareRecords(PlaylistSongRecord a, PlaylistSongRecord b) {
    int result;
    switch (playlistSortController.sortType.value) {
      case SortType.AddedOrder:
        final left = a.additionOrder;
        final right = b.additionOrder;
        result = left == null
            ? (right == null ? 0 : -1)
            : (right == null ? 1 : left.compareTo(right));
        break;
      case SortType.Name:
        result =
            a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
        break;
      case SortType.Duration:
        result = (a.song.duration ?? Duration.zero)
            .compareTo(b.song.duration ?? Duration.zero);
        break;
      default:
        result = 0;
    }
    if (result == 0) result = a.position.compareTo(b.position);
    if (playlist.value.playlistId == 'LIBRP' &&
        playlistSortController.sortType.value == SortType.Custom) {
      result = -result;
    }
    return playlistSortController.isAscending.value ? result : -result;
  }

  void _applySort() {
    _orderedRecords = _records.toList()..sort(_compareRecords);
    _publishSongs();
  }

  void _publishSongs() {
    final songs = _orderedRecords.map((entry) => entry.song).toList();
    if (isSearchingOn.value) {
      tempListContainer = songs;
      songList.value = songs
          .where((song) => song.title.toLowerCase().contains(_searchQuery))
          .toList();
    } else {
      songList.value = songs;
    }
  }

  void _listenForChanges() {
    _songChanges ??= PlaylistSongStore.changes.listen((change) {
      if (_disposed || change.playlistId != playlist.value.playlistId) return;
      if (change.remote) {
        // One refresh per burst; errors are isolated from the successful write.
        _remoteRefresh ??=
            _refreshRemote().whenComplete(() => _remoteRefresh = null);
        return;
      }
      try {
        final removed = change.removedKeys.toSet();
        if (change.upserts.length > 1) {
          final byKey = {for (final entry in _records) entry.key: entry};
          byKey.removeWhere((key, _) => removed.contains(key));
          for (final entry in change.upserts) {
            byKey[entry.key] = entry;
          }
          _records = byKey.values.toList();
          _applySort();
          unawaited(_updatePlaylistThumbSongBased());
          return;
        }
        _records.removeWhere((entry) => removed.contains(entry.key));
        _orderedRecords.removeWhere((entry) => removed.contains(entry.key));
        for (final entry in change.upserts) {
          _records.removeWhere((old) => old.key == entry.key);
          _orderedRecords.removeWhere((old) => old.key == entry.key);
          _records.add(entry);
          // Binary insertion avoids rereading the box or sorting the full list
          // for each completed download or cache write.
          var low = 0;
          var high = _orderedRecords.length;
          while (low < high) {
            final middle = (low + high) ~/ 2;
            if (_compareRecords(_orderedRecords[middle], entry) <= 0) {
              low = middle + 1;
            } else {
              high = middle;
            }
          }
          _orderedRecords.insert(low, entry);
        }
        _publishSongs();
        unawaited(_updatePlaylistThumbSongBased());
      } catch (error) {
        printERROR('Could not update the playlist view: $error');
      }
    });
  }

  Future<void> _refreshRemote() async {
    try {
      await _fetchSongOnline(
          playlist.value.playlistId, false, playlist.value.isPipedPlaylist);
    } catch (error) {
      printERROR('Could not refresh the playlist view: $error');
    } finally {
      if (!_disposed) isContentFetched.value = true;
    }
  }

  Future<void> stopSongUpdates() async {
    _disposed = true;
    await _songChanges?.cancel();
    _songChanges = null;
  }

  @override
  Future<void> fetchSongsfromDatabase(String id) async {
    _listenForChanges();
    _setSongs(await PlaylistSongStore.read(id));
    if (_disposed) return;
    checkDownloadStatus();
  }

  @override
  void onSearchStart(String? tag) {
    super.onSearchStart(tag);
    _searchQuery = '';
  }

  @override
  void startAdditionalOperation(
      SortWidgetController sortWidgetController_, OperationMode mode) {
    super.startAdditionalOperation(sortWidgetController_, mode);
    _arrangementKeys = Map.identity();
    _arrangementAdditions = {};
    for (final entry in _orderedRecords) {
      _arrangementKeys[entry.song] = entry.key;
      _arrangementAdditions[entry.key] = entry.additionOrder;
    }
  }

  @override
  void onSearch(String value, String? tag) {
    _searchQuery = value.toLowerCase();
    super.onSearch(value, tag);
  }

  @override
  void onSearchClose(String? tag) {
    _searchQuery = '';
    super.onSearchClose(tag);
  }

  @override
  Future<void> performAdditionalOperation() async {
    if (additionalOperationMode.value != OperationMode.arrange) {
      super.performAdditionalOperation();
      return;
    }
    final keys = additionalOperationTempList
        .where(_arrangementKeys.containsKey)
        .map((song) => _arrangementKeys[song])
        .toList();
    _setSongs(await PlaylistSongStore.reorder(playlist.value.playlistId, keys,
        originalAdditions: _arrangementAdditions));
    onSort(SortType.Custom, true);
    sortWidgetController?.setActiveMode(OperationMode.none);
    cancelAdditionalOperation();
  }

  // Add this RxBool to track export progress
  final isExporting = false.obs;
  final exportProgress = 0.0.obs;

  String generatedYtmPlaylistUrl = '';

  // Searching changes songList for display only. Exports must use the full list.
  List<MediaItem> get songsToExport =>
      List.of(isSearchingOn.value ? tempListContainer : songList);

  // Title animation

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _heightAnimation;

  AnimationController get animationController => _animationController;
  Animation<double> get scaleAnimation => _scaleAnimation;
  Animation<double> get heightAnimation => _heightAnimation;
  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation =
        Tween<double>(begin: 0, end: 1.0).animate(animationController);

    _heightAnimation =
        Tween<double>(begin: 10.0, end: 75.0).animate(CurvedAnimation(parent: animationController, curve: Curves.easeOutBack));

    final args = Get.arguments as List;
    final Playlist? playlist = args[0];
    final playlistId = args[1];
    fetchPlaylistDetails(playlist, playlistId);
    Future.delayed(const Duration(milliseconds: 200),
        () => Get.find<HomeScreenController>().whenHomeScreenOnTop());
  }

  ///Fetches playlist details from the service
  @override
  void fetchPlaylistDetails(Playlist? playlist_, String playlistId) async {
    _listenForChanges();
    loadSortPreference(playlistId);
    final isIdOnly = playlist_ == null;
    final isPipedPlaylist = playlist_?.isPipedPlaylist ?? false;
    isDefaultPlaylist.value = (playlistId == "SongDownloads" ||
        playlistId == "SongsCache" ||
        playlistId == "LIBRP" ||
        playlistId == "LIBFAV");

    if (!isIdOnly && !playlist_.isCloudPlaylist) {
      playlist.value = playlist_;
      _animationController.forward();
      await fetchSongsfromDatabase(playlistId);
      isContentFetched.value = true;

      Future.delayed(
          const Duration(seconds: 1), () => _updatePlaylistThumbSongBased());

      return;
    }

    if (!isIdOnly) {
      playlist.value = playlist_;
      _animationController.forward();
    }

    try {
      // Check if the playlist is offline
      if (await checkIfAddedToLibrary(playlistId)) {
        final songsBox = await Hive.openBox(playlistId);
        if (songsBox.values.isEmpty) {
          await _fetchSongOnline(playlistId, isIdOnly, isPipedPlaylist);
          await updateSongsIntoDb();
        } else {
          // If the playlist is offline, fetch the songs from the local database
          // Playlist details are already fetched in _checkIfAddedToLibrary method
          await fetchSongsfromDatabase(playlistId);
        }
      } else {
        await _fetchSongOnline(playlistId, isIdOnly, isPipedPlaylist);
      }
      isContentFetched.value = true;
    } catch (e) {
      // Handle any errors that occur during the fetch
      printERROR("Error fetching playlist details: $e");
    }
  }

  Future<void> _fetchSongOnline(
      String id, bool isIdOnly, bool isPipedPlaylist) async {
    if (_disposed) return;
    isContentFetched.value = false;

    if (isPipedPlaylist) {
      final songs = await Get.find<PipedServices>().getPlaylistSongs(id);
      if (_disposed) return;
      _setOnlineSongs(songs);
      isContentFetched.value = true;
      checkDownloadStatus();
      return;
    }

    final content =
        await _musicServices.getPlaylistOrAlbumSongs(playlistId: id);
    if (_disposed) return;

    if (isIdOnly) {
      content['playlistId'] = id;
      playlist.value = Playlist.fromJson(content);
      _animationController.forward();
    }
    _setOnlineSongs(List<MediaItem>.from(content['tracks']));
    checkDownloadStatus();
  }

  void _setOnlineSongs(List<MediaItem> songs) {
    // Online services expose the playlist sequence, not addition timestamps.
    // Use that sequence as the addition order for the fetched snapshot.
    _setSongs([
      for (int i = 0; i < songs.length; i++)
        PlaylistSongRecord(i, {
          ...MediaItemBuilder.toJson(songs[i]),
          'playlistAdditionOrder': i,
          'playlistPosition': i,
        }),
    ]);
  }

  @override
  Future<void> syncPlaylistSongs() async {
    await _fetchSongOnline(
        playlist.value.playlistId, false, playlist.value.isPipedPlaylist);
    await updateSongsIntoDb();
    isContentFetched.value = true;
  }

  @override
  Future<bool> checkIfAddedToLibrary(String id) async {
    final box = await Hive.openBox("LibraryPlaylists");
    isAddedToLibrary.value = box.containsKey(id);
    if (isAddedToLibrary.value) playlist.value = Playlist.fromJson(box.get(id));
    await box.close();
    return isAddedToLibrary.value;
  }

  @override
  Future<bool> addNremoveFromLibrary(dynamic content, {bool add = true}) async {
    try {
      if (content.isPipedPlaylist && !add) {
        //remove piped playlist from lib
        final res =
            await Get.find<PipedServices>().deletePlaylist(content.playlistId);
        if (res.code == 1) {
          await SortWidgetController.removePlaylistPreference(
              content.playlistId);
          isAddedToLibrary.value = false;
        }
        Get.find<LibraryPlaylistsController>().syncPipedPlaylist();
        return (res.code == 1);
      } else {
        final box = await Hive.openBox("LibraryPlaylists");
        final id = content.playlistId;
        if (add) {
          await box.put(id, content.toJson());
          await updateSongsIntoDb();
        } else {
          await box.delete(id);
          await PlaylistSongStore.delete(id);
        }
        isAddedToLibrary.value = add;
      }
      //Update frontend
      Get.find<LibraryPlaylistsController>().refreshLib();
      if (!add) {
        await SortWidgetController.removePlaylistPreference(content.playlistId);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateSongsIntoDb() async {
    await PlaylistSongStore.saveSnapshot(
        playlist.value.playlistId, _records.toList());

    // Update the playlist thumbnail based on the first song's thumbnail
    _updatePlaylistThumbSongBased();
  }

  @override
  Future<void> deleteMultipleSongs(List<MediaItem> songs) async {
    final id = playlist.value.playlistId;
    final isoffline = id == "SongsCache" || id == "SongDownloads";

    final keys = songs
        .where(_arrangementKeys.containsKey)
        .map((song) => _arrangementKeys[song])
        .toList();
    await PlaylistSongStore.remove(id, keys);
    for (MediaItem element in songs) {
      if (isoffline) {
        await Get.find<LibrarySongsController>()
            .removeSong(element, id == "SongDownloads");
      }
    }
    _records.removeWhere((entry) => keys.contains(entry.key));
    _applySort();
    // Update the playlist thumbnail based on the first song's thumbnail
    _updatePlaylistThumbSongBased();
  }

  @override
  void fetchAlbumDetails(Album? album_,String albumId) {} // Not used in this class

  /// This function updates the local playlist thumbnail based on the first song's thumbnail
  Future<void> _updatePlaylistThumbSongBased() async {
    final currentPlaylist = playlist.value;

    if (_disposed ||
        isDefaultPlaylist.isTrue ||
        currentPlaylist.isCloudPlaylist) {
      return;
    }

    Playlist updatedplaylist;
    if (_orderedRecords.isNotEmpty) {
      updatedplaylist = currentPlaylist.copyWith(
          thumbnailUrl: _orderedRecords.first.song.artUri?.toString() ??
              Playlist.thumbPlaceholderUrl);
    } else {
      updatedplaylist =
          currentPlaylist.copyWith(thumbnailUrl: Playlist.thumbPlaceholderUrl);
    }

    // Check if the thumbnail URL is the same as the current one
    // If it is, no need to update the playlist
    if (Thumbnail(currentPlaylist.thumbnailUrl).extraHigh ==
        Thumbnail(updatedplaylist.thumbnailUrl).extraHigh) {
      return;
    }

    // Update the playlist thumbnail URL
    playlist.value = updatedplaylist;
    try {
      await Get.find<LibraryPlaylistsController>()
          .updatePlaylistIntoDb(updatedplaylist);
    } catch (error) {
      printERROR('Could not update the playlist thumbnail: $error');
    }
  }

  @override
  void onClose() {
    unawaited(stopSongUpdates());
    tempListContainer.clear();
    _animationController.dispose();
    Get.find<HomeScreenController>().whenHomeScreenOnTop();
    super.onClose();
  }

  Future<void> exportPlaylistToJson(BuildContext context) async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "permissionDenied".tr,
            size: SanckBarSize.MEDIUM));
      }
      return;
    }

    try {
      isExporting.value = true;
      exportProgress.value = 0.1;

      // Show progress dialog
      if (context.mounted) {
        _showProgressDialog(context, "exportingPlaylist".tr);
      }

      // Get appropriate directory based on platform
      final Directory exportDir = await _getExportDirectory();
      exportProgress.value = 0.2;

      // Create playlist data map
      final playlistData = {
        "playlistInfo": playlist.value.toJson(),
        "songs": songsToExport.map(MediaItemBuilder.toJson).toList(),
        "exportDate": DateTime.now().toIso8601String(),
        "appVersion": Get.find<SettingsScreenController>().currentVersion,
      };
      exportProgress.value = 0.5;

      // Generate filename with playlist name
      final sanitizedName =
          playlist.value.title.replaceAll(RegExp(r'[^\w\s]+'), '_');

      // Find available filename with incremental suffix if needed
      String filename = "$sanitizedName.json";
      String filePath = "${exportDir.path}/$filename";
      File file = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filename = "${sanitizedName}_$counter.json";
        filePath = "${exportDir.path}/$filename";
        file = File(filePath);
        counter++;
      }

      exportProgress.value = 0.7;

      // Write JSON to file
      await file.writeAsString(jsonEncode(playlistData));
      exportProgress.value = 1.0;

      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      // Show success message with platform-specific path info
      String locationMsg = _getLocationMessage(exportDir.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "${"playlistExportedMsg".tr}: $locationMsg",
            size: SanckBarSize.MEDIUM));
      }
    } catch (e) {
      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      printERROR("Error exporting playlist: $e");
      
      String errorMsg = "exportError".tr;
      if (e is FileSystemException) {
        if (e.osError?.errorCode == 13) {
          errorMsg = "exportErrorPermission".tr;
        } else if (e.osError?.errorCode == 28) {
          errorMsg = "exportErrorStorage".tr;
        }
      } else if (e is FormatException) {
        errorMsg = "exportErrorFormat".tr;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      isExporting.value = false;
      exportProgress.value = 0.0;
    }
  }

  Future<void> exportPlaylistToCsv(BuildContext context) async {
    if (!await PermissionService.getExtStoragePermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "permissionDenied".tr,
            size: SanckBarSize.MEDIUM));
      }
      return;
    }

    try {
      isExporting.value = true;
      exportProgress.value = 0.1;

      // Show progress dialog
      if (context.mounted) {
        _showProgressDialog(context, "exportingPlaylist".tr);
      }

      // Get appropriate directory based on platform
      final Directory exportDir = await _getExportDirectory();
      exportProgress.value = 0.2;

      // Build CSV content
      final csvContent = _generateCsvContent();
      exportProgress.value = 0.5;

      // Generate filename with playlist name
      final sanitizedName =
          playlist.value.title.replaceAll(RegExp(r'[^\w\s]+'), '_');

      // Find available filename with incremental suffix if needed
      String filename = "$sanitizedName.csv";
      String filePath = "${exportDir.path}/$filename";
      File file = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filename = "${sanitizedName}_$counter.csv";
        filePath = "${exportDir.path}/$filename";
        file = File(filePath);
        counter++;
      }

      exportProgress.value = 0.7;

      // Write CSV to file
      await file.writeAsString(csvContent);
      exportProgress.value = 1.0;

      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      // Show success message with platform-specific path info
      String locationMsg = _getLocationMessage(exportDir.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "${"playlistExportedMsg".tr}: $locationMsg",
            size: SanckBarSize.MEDIUM));
      }
    } catch (e) {
      // Close progress dialog if it's still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }

      printERROR("Error exporting playlist to CSV: $e");
      
      String errorMsg = "exportError".tr;
      if (e is FileSystemException) {
        if (e.osError?.errorCode == 13) {
          errorMsg = "exportErrorPermission".tr;
        } else if (e.osError?.errorCode == 28) {
          errorMsg = "exportErrorStorage".tr;
        }
      } else if (e is FormatException) {
        errorMsg = "exportErrorFormat".tr;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, errorMsg, size: SanckBarSize.MEDIUM));
      }
    } finally {
      isExporting.value = false;
      exportProgress.value = 0.0;
    }
  }

  String _generateCsvContent() {
    final buffer = StringBuffer();
    
    // CSV Header
    buffer.writeln('PlaylistBrowseId,PlaylistName,MediaId,Title,Artists,Duration,ThumbnailUrl,AlbumId,AlbumTitle,ArtistIds');
    
    // CSV Rows - one for each song
    for (final song in songsToExport) {
      // Keep playlistBrowseId blank for offline/piped playlists
      final playlistBrowseId = (!playlist.value.isCloudPlaylist || playlist.value.isPipedPlaylist)
          ? ''
          : _escapeCsvField(playlist.value.playlistId);
      final playlistName = _escapeCsvField(playlist.value.title);
      final mediaId = _escapeCsvField(song.id);
      final title = _escapeCsvField(song.title);
      
      // Extract artists as comma-separated string
      final artistsList = song.extras?['artists'] as List?;
      final artists = artistsList != null
          ? _escapeCsvField(artistsList.map((a) => a['name']).join(', '))
          : '';
      
      // Format duration as HH:MM:SS or MM:SS
      final duration = song.duration != null
          ? _formatDuration(song.duration!)
          : '';
      
      final thumbnailUrl = _escapeCsvField(song.artUri.toString());
      
      // Extract album information
      final albumData = song.extras?['album'] as Map?;
      final albumId = albumData != null ? _escapeCsvField(albumData['id'] ?? '') : '';
      final albumTitle = albumData != null ? _escapeCsvField(albumData['name'] ?? '') : '';
      
      // Extract all artist IDs (comma-separated)
      final artistIds = artistsList != null && artistsList.isNotEmpty
          ? _escapeCsvField(artistsList.map((a) => a['id'] ?? '').join(','))
          : '';
      
      buffer.writeln('$playlistBrowseId,$playlistName,$mediaId,$title,$artists,$duration,$thumbnailUrl,$albumId,$albumTitle,$artistIds');
    }
    
    return buffer.toString();
  }

  String _escapeCsvField(String field) {
    // Escape double quotes by doubling them
    String escaped = field.replaceAll('"', '""');
    
    // If field contains comma, newline, or double quote, wrap in quotes
    if (escaped.contains(',') || escaped.contains('\n') || escaped.contains('"')) {
      escaped = '"$escaped"';
    }
    
    return escaped;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // Helper method to get the appropriate export directory for each platform
  Future<Directory> _getExportDirectory() async {
    Directory directory;
    const appFolderName = "HarmonyMusic";

    try {
      if (Platform.isAndroid) {
        // Android: use Downloads folder
        directory = Directory('/storage/emulated/0/Download/$appFolderName');
      } else if (Platform.isIOS) {
        // iOS: use Documents directory
        final docDir = await path_provider.getApplicationDocumentsDirectory();
        directory = Directory('${docDir.path}/$appFolderName');
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop platforms: use Downloads folder in user's home directory
        final homeDir = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
        directory = Directory('$homeDir/Downloads/$appFolderName');
      } else {
        // Fallback: use temporary directory
        final tempDir = await path_provider.getTemporaryDirectory();
        directory = Directory('${tempDir.path}/$appFolderName');
      }

      // Create directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      return directory;
    } catch (e) {
      // Fallback to app's documents directory if any error occurs
      final appDocDir = await path_provider.getApplicationDocumentsDirectory();
      directory = Directory('${appDocDir.path}/$appFolderName');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    }
  }

  // Helper method to get a user-friendly location message
  String _getLocationMessage(String path) {
    if (Platform.isAndroid) {
      return "Downloads/HarmonyMusic";
    } else if (Platform.isIOS) {
      return "Files App > HarmonyMusic";
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return "Downloads/HarmonyMusic";
    } else {
      return path.split('/').last;
    }
  }

  // Helper method to show progress dialog
  void _showProgressDialog(BuildContext context, String title) {
    Get.dialog(
      AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Obx(() => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: exportProgress.value,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "${(exportProgress.value * 100).toInt()}%",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            )),
      ),
      barrierDismissible: false,
    );
  }
}
