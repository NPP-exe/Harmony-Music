import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  final showVersionDialog = true.obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;

  @override
  onInit() {
    super.onInit();
    loadContent();
    if (updateCheckFlag) _checkNewVersion();
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    if (isCachedHomeScreenDataEnabled) {
      var loaded = false;
      try {
        loaded = await loadContentFromDb();
      } catch (e) {
        printERROR("Could not restore cached home content: $e");
      }

      if (loaded) {
        final currTimeSecsDiff =
            DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 3) {
          // Refresh every 3 hours for fresh content
          loadContentFromNetwork(silent: true);
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final quickPicksType = homeScreenData.get("quickPicksType");
      final quickPicksData = homeScreenData.get("quickPicks");
      if (quickPicksType is! String || quickPicksData is! List) {
        return false;
      }
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
        quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
        title: quickPicksType,
      );
      middleContent.value = middleContentData
          .map(
            (e) => e["type"] == "Album Content"
                ? AlbumContent.fromJson(e)
                : PlaylistContent.fromJson(e),
          )
          .toList();
      fixedContent.value = fixedContentData
          .map(
            (e) => e["type"] == "Album Content"
                ? AlbumContent.fromJson(e)
                : PlaylistContent.fromJson(e),
          )
          .toList();
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box("AppPrefs");
    String contentType = box.get("discoverContentType") ?? "QP";

    networkError.value = false;
    try {
      List middleContentTemp = [];
      final homeContentListMap = await _musicServices.getHome(
        limit: Get.find<SettingsScreenController>().noOfHomeScreenContent.value,
      );
      if (contentType == "TR") {
        final index = homeContentListMap.indexWhere(
          (element) => element['title'] == "Trending",
        );
        if (index != -1 && index != 0) {
          final items = (homeContentListMap[index]["contents"] as List)
              .whereType<MediaItem>()
              .toList();
          if (items.isNotEmpty) {
            quickPicks.value = QuickPicks(items, title: "Trending");
          }
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final chartIdx = charts.indexWhere(
            (element) =>
                element['title'] ==
                (contentType == "TMV" ? "Top Music Videos" : "Trending"),
          );
          if (chartIdx != -1) {
            final items = (charts[chartIdx]["contents"] as List)
                .whereType<MediaItem>()
                .toList();
            if (items.isNotEmpty) {
              quickPicks.value = QuickPicks(
                items,
                title: charts[chartIdx]['title'],
              );
              middleContentTemp.addAll(charts);
            }
          }
        }
      } else if (contentType == "TMV") {
        final index = homeContentListMap.indexWhere(
          (element) => element['title'] == "Top music videos",
        );
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          final items = (con["contents"] as List)
              .whereType<MediaItem>()
              .toList();
          if (items.isNotEmpty) {
            quickPicks.value = QuickPicks(items, title: con["title"]);
          }
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final chartIdx = charts.indexWhere(
            (element) =>
                element['title'] ==
                (contentType == "TMV" ? "Top Music Videos" : "Trending"),
          );
          if (chartIdx != -1) {
            final items = (charts[chartIdx]["contents"] as List)
                .whereType<MediaItem>()
                .toList();
            if (items.isNotEmpty) {
              quickPicks.value = QuickPicks(
                items,
                title: charts[chartIdx]["title"],
              );
              middleContentTemp.addAll(charts);
            }
          }
        }
      } else if (contentType == "BOLI") {
        final recentSongId = box.get("recentSongId");
        if (recentSongId != null && recentSongId.toString().isNotEmpty) {
          try {
            final rel = await _musicServices.getContentRelatedToSong(
              recentSongId,
              getContentHlCode(),
            );
            if (rel != null && rel is List && rel.isNotEmpty) {
              for (final section in rel) {
                if (section is Map && section['contents'] is List) {
                  final items = (section['contents'] as List)
                      .whereType<MediaItem>()
                      .toList();
                  if (items.isNotEmpty) {
                    quickPicks.value = QuickPicks(
                      items,
                      title: section['title']?.toString() ?? "Similar Songs",
                    );
                    break;
                  }
                }
              }
              middleContentTemp.addAll(rel);
            }
          } catch (e) {
            printERROR("Could not load recent song suggestions: $e");
          }

          if (quickPicks.value.songList.isEmpty) {
            try {
              final watchData = await _musicServices.getWatchPlaylist(
                videoId: recentSongId,
                limit: 15,
              );
              final tracks = watchData['tracks'];
              if (tracks != null && tracks is List) {
                final items = tracks
                    .whereType<MediaItem>()
                    .where((m) => m.id != recentSongId)
                    .toList();
                if (items.isNotEmpty) {
                  quickPicks.value = QuickPicks(items, title: "Similar Songs");
                }
              }
            } catch (e) {
              printERROR("getWatchPlaylist fallback error on loadContent: $e");
            }
          }
        }
      } else {
        // "QP" (default): Actual Quick picks from YouTube Music home
        final index = homeContentListMap.indexWhere(
          (element) => element['title'] == "Quick picks",
        );
        if (index != -1) {
          final con = homeContentListMap.removeAt(index);
          final items = (con["contents"] as List)
              .whereType<MediaItem>()
              .toList();
          if (items.isNotEmpty) {
            quickPicks.value = QuickPicks(items, title: "Quick picks");
          }
        } else if (homeContentListMap.isNotEmpty) {
          for (int i = 0; i < homeContentListMap.length; i++) {
            final shelf = homeContentListMap[i];
            if (shelf['contents'] is List) {
              final items = (shelf['contents'] as List)
                  .whereType<MediaItem>()
                  .toList();
              if (items.isNotEmpty) {
                homeContentListMap.removeAt(i);
                quickPicks.value = QuickPicks(
                  items,
                  title: shelf['title'] ?? "Quick picks",
                );
                break;
              }
            }
          }
        }
      }

      // If still empty (e.g. BOLI before any song was played), take first song shelf
      if (quickPicks.value.songList.isEmpty && homeContentListMap.isNotEmpty) {
        for (int i = 0; i < homeContentListMap.length; i++) {
          final shelf = homeContentListMap[i];
          if (shelf['contents'] is List) {
            final items = (shelf['contents'] as List)
                .whereType<MediaItem>()
                .toList();
            if (items.isNotEmpty) {
              homeContentListMap.removeAt(i);
              quickPicks.value = QuickPicks(
                items,
                title: shelf['title'] ?? "Quick picks",
              );
              break;
            }
          }
        }
      }

      middleContent.value = _setContentList(middleContentTemp);
      fixedContent.value = _setContentList(homeContentListMap);

      isContentFetched.value = true;

      // set home content last update time
      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      // ignore: unused_catch_stack
    } on NetworkError catch (r, e) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
      isContentFetched.value = true;
    } catch (e) {
      printERROR("Home content request failed: $e");
      networkError.value = !silent;
      isContentFetched.value = true;
    }
  }

  List _setContentList(List<dynamic> contents) {
    List contentTemp = [];
    for (var content in contents) {
      if ((content["contents"]).isEmpty) continue;
      if ((content["contents"][0]).runtimeType == Playlist) {
        final tmp = PlaylistContent(
          playlistList: (content["contents"]).whereType<Playlist>().toList(),
          title: content["title"],
        );
        if (tmp.playlistList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if ((content["contents"][0]).runtimeType == Album) {
        final tmp = AlbumContent(
          albumList: (content["contents"]).whereType<Album>().toList(),
          title: content["title"],
        );
        if (tmp.albumList.length >= 2) {
          contentTemp.add(tmp);
        }
      }
    }
    return contentTemp;
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == 'QP') {
      try {
        final homeContentListMap = await _musicServices.getHome(limit: 4);
        final index = homeContentListMap.indexWhere(
          (element) => element['title'] == "Quick picks",
        );
        if (index != -1) {
          final items = (homeContentListMap[index]["contents"] as List)
              .whereType<MediaItem>()
              .toList();
          if (items.isNotEmpty) {
            quickPicks_ = QuickPicks(items, title: "Quick picks");
          }
        }
        if (quickPicks_ == null && homeContentListMap.isNotEmpty) {
          for (final shelf in homeContentListMap) {
            if (shelf['contents'] is List) {
              final items = (shelf['contents'] as List)
                  .whereType<MediaItem>()
                  .toList();
              if (items.isNotEmpty) {
                quickPicks_ = QuickPicks(
                  items,
                  title: shelf['title'] ?? "Quick picks",
                );
                break;
              }
            }
          }
        }
      } catch (e) {
        printERROR("Error fetching QP discover content: $e");
      }
    } else if (val == "TMV" || val == 'TR') {
      try {
        final charts = await _musicServices.getCharts(val);
        final index = charts.indexWhere(
          (element) =>
              element['title'] ==
              (val == "TMV" ? "Top Music Videos" : "Trending"),
        );
        if (index != -1) {
          final items = (charts[index]["contents"] as List)
              .whereType<MediaItem>()
              .toList();
          if (items.isNotEmpty) {
            quickPicks_ = QuickPicks(items, title: charts[index]["title"]);
          }
        }
        if (quickPicks_ == null && charts.isNotEmpty) {
          for (final c in charts) {
            if (c['contents'] is List) {
              final items = (c['contents'] as List)
                  .whereType<MediaItem>()
                  .toList();
              if (items.isNotEmpty) {
                quickPicks_ = QuickPicks(
                  items,
                  title:
                      c['title'] ??
                      (val == "TMV" ? "Top Music Videos" : "Trending"),
                );
                break;
              }
            }
          }
        }
      } catch (e) {
        printERROR(
          "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available: $e",
        );
      }
    } else {
      songId ??= Hive.box("AppPrefs").get("recentSongId");
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
            songId,
            getContentHlCode(),
          );
          middleContent.value = _setContentList(value);
          if (value is List && value.isNotEmpty) {
            for (final section in value) {
              if (section is Map && section['contents'] is List) {
                final items = (section['contents'] as List)
                    .whereType<MediaItem>()
                    .toList();
                if (items.isNotEmpty) {
                  quickPicks_ = QuickPicks(
                    items,
                    title: section['title']?.toString() ?? "Similar Songs",
                  );
                  break;
                }
              }
            }
            Hive.box("AppPrefs").put("recentSongId", songId);
          }
        } catch (e) {
          printERROR("Error getting content related to song: $e");
        }
      }
      if (quickPicks_ == null && songId != null) {
        try {
          final watchData = await _musicServices.getWatchPlaylist(
            videoId: songId,
            limit: 15,
          );
          final tracks = watchData['tracks'];
          if (tracks != null && tracks is List) {
            final items = tracks
                .whereType<MediaItem>()
                .where((m) => m.id != songId)
                .toList();
            if (items.isNotEmpty) {
              quickPicks_ = QuickPicks(items, title: "Similar Songs");
            }
          }
        } catch (e) {
          printERROR("changeDiscoverContent fallback error: $e");
        }
      }
      if (quickPicks_ == null) {
        try {
          final homeContentListMap = await _musicServices.getHome(limit: 3);
          if (homeContentListMap.isNotEmpty) {
            for (final shelf in homeContentListMap) {
              if (shelf['contents'] is List) {
                final items = (shelf['contents'] as List)
                    .whereType<MediaItem>()
                    .toList();
                if (items.isNotEmpty) {
                  quickPicks_ = QuickPicks(
                    items,
                    title: shelf['title'] ?? "Quick picks",
                  );
                  break;
                }
              }
            }
          }
        } catch (e) {
          printERROR("Fallback home content failed: $e");
        }
      }
    }
    if (quickPicks_ == null) return;

    quickPicks.value = quickPicks_;

    // set home content last update time
    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box("AppPrefs")
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  /// Automatically update quick picks & middle content with similar suggestions when any song is played (only if BOLI is selected)
  Future<void> updateQuickPicksForSong(String songId) async {
    final contentType = Hive.box("AppPrefs").get("discoverContentType") ?? "QP";
    if (contentType != "BOLI") return;
    if (songId.isEmpty || songId.startsWith('local_')) return;
    try {
      List<MediaItem> songSuggestions = [];
      String sectionTitle = "Similar Songs";

      // 1. Try getContentRelatedToSong
      try {
        final value = await _musicServices.getContentRelatedToSong(
          songId,
          getContentHlCode(),
        );
        if (value != null && value is List && value.isNotEmpty) {
          for (final section in value) {
            if (section is Map && section['contents'] is List) {
              final items = (section['contents'] as List)
                  .whereType<MediaItem>()
                  .toList();
              if (items.isNotEmpty) {
                songSuggestions = items;
                sectionTitle = section['title']?.toString() ?? "Similar Songs";
                break;
              }
            }
          }
          middleContent.value = _setContentList(value);
        }
      } catch (e) {
        printERROR("getContentRelatedToSong error: $e");
      }

      // 2. Fallback to getWatchPlaylist radio/automix tracks if needed
      if (songSuggestions.isEmpty) {
        try {
          final watchData = await _musicServices.getWatchPlaylist(
            videoId: songId,
            limit: 15,
          );
          final tracks = watchData['tracks'];
          if (tracks != null && tracks is List) {
            final items = tracks
                .whereType<MediaItem>()
                .where((m) => m.id != songId)
                .toList();
            if (items.isNotEmpty) {
              songSuggestions = items;
              sectionTitle = "Similar Songs";
            }
          }
        } catch (e) {
          printERROR("getWatchPlaylist fallback error on updateQuickPicks: $e");
        }
      }

      if (songSuggestions.isNotEmpty) {
        quickPicks.value = QuickPicks(songSuggestions, title: sectionTitle);
        cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
        await Hive.box("AppPrefs").put("recentSongId", songId);
        await Hive.box("AppPrefs")
            .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      printERROR("Error updating quick picks for song $songId: $e");
    }
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void _checkNewVersion() {
    showVersionDialog.value =
        Hive.box("AppPrefs").get("newVersionVisibility") ?? true;
    if (showVersionDialog.isTrue) {
      final settingsCon = Get.find<SettingsScreenController>();
      newVersionCheckWithDetails(settingsCon.currentVersion).then((info) {
        if (info.isAvailable) {
          settingsCon.isNewVersionAvailable.value = true;
          settingsCon.latestVersion.value = info.latestVersion;
          settingsCon.releaseNotes.value = info.releaseNotes;
          settingsCon.releaseUrl.value = info.releaseUrl;
          if (Get.context != null) {
            showDialog(
              context: Get.context!,
              builder: (context) => const NewVersionDialog(),
            );
          }
        }
      });
    }
  }

  void onChangeVersionVisibility(bool val) {
    Hive.box("AppPrefs").put("newVersionVisibility", !val);
    showVersionDialog.value = !val;
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
            isResultScreenOnTop
                ? const Duration(milliseconds: 300)
                : Duration.zero,
            () {
              playerCon.playerPanelMinHeight.value =
                  75.0 + Get.mediaQuery.viewPadding.bottom;
            },
          );
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(
          quickPicks.value.songList,
          isQuickPicks: true,
        ),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(
          quickPicks.value.songList,
          isQuickPicks: true,
        ),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList()),
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(
    List content, {
    bool isQuickPicks = false,
  }) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void dispose() {
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
