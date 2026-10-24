import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '/utils/audio_tags.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
import 'music_service.dart';

//import '../models/thumbnail.dart' as th;

class Downloader extends GetxService {
  final _dio = Dio();
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  final currentPlaylistId = "".obs;
  final songDownloadingProgress = 0.obs;
  final playlistDownloadingProgress = 0.obs;
  final isJobRunning = false.obs;

  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  Future<bool> checkPermissionNDir() async {
    if (GetPlatform.isWeb) return false;
    final settingsScreenController = Get.find<SettingsScreenController>();

    if (!settingsScreenController.isCurrentPathsupportDownDir &&
        !await PermissionService.getExtStoragePermission()) {
      return false;
    }

    final dirPath =
        Get.find<SettingsScreenController>().downloadLocationPath.string;
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return true;
  }

  Future<void> downloadPlaylist(
    String playlistId,
    List<MediaItem> songList,
  ) async {
    if (!(await checkPermissionNDir())) return;

    // for toggle between downloading request & cancelling
    if (playlistQueue.containsKey(playlistId)) {
      songQueue.removeWhere((element) => songList.contains(element));
      playlistQueue.remove(playlistId);
      return;
    }

    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList);

    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> download(MediaItem? song, {List<MediaItem>? songList}) async {
    if (!(await checkPermissionNDir())) return;
    if (songList != null) {
      songQueue.addAll(songList);
    } else {
      songQueue.add(song!);
    }
    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  Future<void> triggerDownloadingJob() async {
    //check if playlist download in queue => download playlistsongs else download from general songs queue
    if (playlistQueue.isNotEmpty) {
      isJobRunning.value = true;
      for (String playlistId in playlistQueue.keys.toList()) {
        //checked in case download cancel request
        if (playlistQueue.containsKey(playlistId)) {
          currentPlaylistId.value = playlistId;
          await downloadSongList(
            (playlistQueue[playlistId]!).toList(),
            isPlaylist: true,
          );
          if (Get.isRegistered<PlaylistScreenController>(
                tag: Key(playlistId).hashCode.toString(),
              ) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<PlaylistScreenController>(
              tag: Key(playlistId).hashCode.toString(),
            ).isDownloaded.value = true;
          }
          // in case of album
          else if (Get.isRegistered<AlbumScreenController>(
                tag: Key(playlistId).hashCode.toString(),
              ) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<AlbumScreenController>(
              tag: Key(playlistId).hashCode.toString(),
            ).isDownloaded.value = true;
          }
          playlistQueue.remove(playlistId);
        }
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
      }
    } else {
      isJobRunning.value = true;
      await downloadSongList(songQueue.toList());
    }

    if (songQueue.isNotEmpty) {
      triggerDownloadingJob();
    } else {
      isJobRunning.value = false;
      currentSong = null;
    }
  }

  Future<void> downloadSongList(
    List<MediaItem> jobSongList, {
    bool isPlaylist = false,
  }) async {
    for (MediaItem song in jobSongList) {
      // intrrupt downloading task in case of playlist download cancel request
      if (isPlaylist && !playlistQueue.containsKey(currentPlaylistId.value)) {
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
        return;
      }

      if (!Hive.box("SongDownloads").containsKey(song.id)) {
        currentSong = song;
        songDownloadingProgress.value = 0;
        await writeFileStream(song);
      }
      songQueue.remove(song);
      //for playlist downloading counter update
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
      }
    }
  }

  Future<void> writeFileStream(MediaItem song) async {
    Completer<void> complete = Completer();

    final settingsScreenController = Get.find<SettingsScreenController>();
    final downloadingFormat = settingsScreenController.downloadingFormat.string;
    final dirPath = settingsScreenController.downloadLocationPath.string;
    final RegExp invalidChar = RegExp(
      r'Container.|\/|\\|\"|\<|\>|\*|\?|\:|\!|\[|\]|\¡|\||\%',
    );
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})"
        .replaceAll(invalidChar, "");

    // --- Cache-to-download shortcut ---
    // If this song is already cached on disk, copy it directly to downloads!
    try {
      final cacheDir = (await getTemporaryDirectory()).path;
      final cachedFile = File('$cacheDir/cachedSongs/${song.id}.mp3');
      if (await cachedFile.exists()) {
        printINFO('Copying from cache for ${song.id}');
        songDownloadingProgress.value = 50;
        final destPath = "$dirPath/$songTitle.mp3";
        await cachedFile.copy(destPath);
        songDownloadingProgress.value = 90;

        // Fetch & embed lyrics
        String lyricsText = '';
        try {
          final musicSvc = Get.find<MusicServices>();
          final lrclibResult = await musicSvc.getLyricsFromLrcLib(
            song.title,
            song.artist ?? '',
            song.duration?.inSeconds ?? 0,
          );
          if (lrclibResult != null) {
            lyricsText = lrclibResult['plain'] ?? lrclibResult['synced'] ?? '';
          }
          if (lyricsText.isEmpty) {
            final ovh = await musicSvc.getLyricsFromLyricsOvh(
              song.title,
              song.artist ?? '',
            );
            if (ovh != null) lyricsText = ovh;
          }
          if (lyricsText.isNotEmpty) {
            final lrcPath = "$dirPath/$songTitle.lrc";
            await File(lrcPath).writeAsString(lyricsText);
          }
        } catch (e) {
          printERROR("Could not cache lyrics: $e");
        }

        // Write metadata tags
        try {
          String? year;
          if (song.extras?['year'] != null) {
            year = song.extras?['year'];
          }
          final imageUrl = song.artUri?.toString();
          final coverBytes = imageUrl == null
              ? null
              : (await NetworkAssetBundle(Uri.parse(imageUrl)).load(imageUrl))
                    .buffer
                    .asUint8List();
          await writeAudioTags(
            destPath,
            title: song.title,
            artist: song.artist,
            album: song.album,
            year: int.tryParse(year ?? ''),
            genre: song.genre,
            coverBytes: coverBytes,
          );
        } catch (e) {
          printERROR('Tag write error (cache copy): $e');
        }

        song.extras?['url'] = destPath;
        if (lyricsText.isNotEmpty) {
          song.extras?['lyrics'] = lyricsText;
        }
        final songJson = MediaItemBuilder.toJson(song);
        if (lyricsText.isNotEmpty) {
          songJson['lyrics'] = lyricsText;
        }
        songJson['streamInfo'] = [
          true,
          {
            'itag': 140,
            'audioCodec': 'Codec.mp4a',
            'bitrate': 128000,
            'loudnessDb': 0.0,
            'url': destPath,
            'approxDurationMs': song.duration?.inSeconds ?? 0,
            'size': await cachedFile.length(),
          },
        ];
        Hive.box('SongDownloads').put(song.id, songJson);
        Get.find<LibrarySongsController>().librarySongsList.add(song);
        songDownloadingProgress.value = 100;
        printINFO('Copied from cache successfully');
        complete.complete();
        return complete.future;
      }
    } catch (e) {
      printERROR('Cache-copy error, falling back to network: $e');
    }
    // --- End cache shortcut ---

    final playerResponse = await StreamProvider.fetch(song.id);
    if (!playerResponse.playable) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(
          Get.context!,
          playerResponse.statusMSG == "networkError"
              ? playerResponse.statusMSG.tr
              : playerResponse.statusMSG,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
          top: !GetPlatform.isDesktop,
        ),
      );
      printINFO("Requested song is not downloadable. You may try again");
      complete.complete();
      return complete.future;
    }

    Audio requiredAudioStream = downloadingFormat == "opus"
        ? playerResponse.highestBitrateOpusAudio!
        : playerResponse.highestBitrateMp4aAudio!;

    final actualDownformat = requiredAudioStream.audioCodec.name.contains("mp")
        ? "m4a"
        : "opus";
    String filePath = "$dirPath/$songTitle.$actualDownformat";
    printINFO("Downloading filePath: $filePath");
    final totalBytes = requiredAudioStream.size;

    _dio
        .download(
          requiredAudioStream.url,
          options: Options(headers: {"Range": 'bytes=0-$totalBytes'}),
          filePath,
          onReceiveProgress: (count, total) {
            if (total <= 0) return;
            songDownloadingProgress.value = ((count / total) * 100).toInt();
          },
        )
        .then((value) async {
          printINFO(value.data);

          String? year;
          try {
            if (song.extras?['year'] != null) {
              year = song.extras?['year'];
            } else {
              if (song.album != null) {
                final musicServ = Get.find<MusicServices>();
                year = await musicServ.getSongYear(song.id);
              }
            }
          } catch (e) {
            printERROR("Could not fetch song year: $e");
          }

          // Save Thumbnail
          try {
            final thumbnailPath =
                "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
            await _dio.downloadUri(song.artUri!, thumbnailPath);
          } catch (e) {
            printERROR("Could not save thumbnail: $e");
          }

          // Fetch & embed lyrics into .lrc file and songJson
          String lyricsText = '';
          try {
            final musicSvc = Get.find<MusicServices>();
            final lrclibResult = await musicSvc.getLyricsFromLrcLib(
              song.title,
              song.artist ?? '',
              song.duration?.inSeconds ?? 0,
            );
            if (lrclibResult != null) {
              lyricsText =
                  lrclibResult['plain'] ?? lrclibResult['synced'] ?? '';
            }
            if (lyricsText.isEmpty) {
              try {
                final related = await musicSvc.getWatchPlaylist(
                  videoId: song.id,
                  onlyRelated: true,
                );
                final browseId = related['lyrics'];
                if (browseId != null) {
                  final ytmLyrics = await musicSvc.getLyrics(browseId);
                  if (ytmLyrics != null) lyricsText = ytmLyrics.toString();
                }
              } catch (e) {
                printERROR("Could not fetch YTM lyrics: $e");
              }
            }
            if (lyricsText.isEmpty) {
              final ovh = await musicSvc.getLyricsFromLyricsOvh(
                song.title,
                song.artist ?? '',
              );
              if (ovh != null) lyricsText = ovh;
            }
            if (lyricsText.isNotEmpty) {
              final lrcPath = "$dirPath/$songTitle.lrc";
              await File(lrcPath).writeAsString(lyricsText);
              printINFO('Lyrics saved to $lrcPath');
            }
          } catch (e) {
            printERROR('Lyrics fetch during download failed: $e');
          }

          song.extras?['url'] = filePath;
          if (lyricsText.isNotEmpty) {
            song.extras?['lyrics'] = lyricsText;
          }
          final songJson = MediaItemBuilder.toJson(song);
          if (lyricsText.isNotEmpty) {
            songJson['lyrics'] = lyricsText;
          }
          final streamInfoJson = requiredAudioStream.toJson();
          streamInfoJson['url'] = filePath;
          songJson["streamInfo"] = [true, streamInfoJson];

          Hive.box("SongDownloads").put(song.id, songJson);
          Get.find<LibrarySongsController>().librarySongsList.add(song);
          printINFO("Downloaded successfully");

          final trackDetails = (song.extras?['trackDetails'])?.split("/");
          final int? trackNumber = int.tryParse(trackDetails?[0] ?? "");
          final int? totalTracks = int.tryParse(trackDetails?[1] ?? "");

          try {
            final imageUrl = song.artUri!.toString();
            final coverBytes = (await NetworkAssetBundle(
              Uri.parse(imageUrl),
            ).load(imageUrl)).buffer.asUint8List();
            await writeAudioTags(
              filePath,
              title: song.title,
              artist: song.artist,
              album: song.album,
              year: int.tryParse(year ?? ''),
              genre: song.genre,
              trackNumber: trackNumber,
              trackTotal: totalTracks,
              coverBytes: coverBytes,
            );
          } catch (e) {
            printERROR("$e");
          }
          complete.complete();
        })
        .onError((error, stackTrace) {
          ScaffoldMessenger.of(Get.context!).showSnackBar(
            snackbar(
              Get.context!,
              "downloadError3".tr,
              size: SanckBarSize.BIG,
              duration: const Duration(seconds: 2),
              top: !GetPlatform.isDesktop,
            ),
          );
          printINFO(
            "Downloading failed due to network/stream error! Please try again",
          );
          complete.complete();
        });

    return complete.future;
  }
}
