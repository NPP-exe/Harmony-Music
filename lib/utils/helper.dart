import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'app_constants.dart';
import '/ui/navigator.dart';
import '/ui/widgets/sort_widget.dart';

void printERROR(dynamic text, {String tag = "Harmony Music"}) {
  if (kReleaseMode) return;
  debugPrint("\x1B[31m[$tag]: $text\x1B[0m");
}

void printWarning(dynamic text, {String tag = 'Harmony Music'}) {
  if (kReleaseMode) return;
  debugPrint("\x1B[33m[$tag]: $text\x1B[34m");
}

void printINFO(dynamic text, {String tag = 'Harmony Music'}) {
  if (kReleaseMode) return;
  debugPrint("\x1B[32m[$tag]: $text\x1B[34m");
}

String? getCurrentRouteName() {
  String? currentPath;
  Get.nestedKey(ScreenNavigationSetup.id)?.currentState?.popUntil((route) {
    currentPath = route.settings.name;
    return true;
  });
  return currentPath;
}

void sortSongsNVideos(
  List songlist,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Date:
      compareFunction = (a, b) {
        if (a.extras!['date'] == null || b.extras!['date'] == null) {
          return 0.compareTo(0);
        }
        return a.extras!['date'].compareTo(b.extras!['date']);
      };
      break;
    case SortType.Duration:
      compareFunction = (a, b) =>
          (a.duration ?? Duration.zero).compareTo(b.duration ?? Duration.zero);
    case SortType.Name:
    default:
      compareFunction =
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
      break;
  }

  songlist.sort(compareFunction);

  if (!isAscending) {
    List reversed = songlist.reversed.toList();
    songlist.clear();
    songlist.addAll(reversed);
  }
}

void sortAlbumNSingles(
  List albumList,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Date:
      compareFunction =
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
      break;
    case SortType.Name:
    default:
      compareFunction = (a, b) {
        if (a.year == null || b.year == null) {
          return 0.compareTo(0);
        }
        return a.year!.compareTo(b.year!);
      };
      break;
  }

  albumList.sort(compareFunction);

  if (!isAscending) {
    List reversed = albumList.reversed.toList();
    albumList.clear();
    albumList.addAll(reversed);
  }
}

void sortPlayLists(
  List playlists,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;
  int titleSort(a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());

  switch (sortType) {
    case SortType.RecentlyPlayed:
      compareFunction = (a, b) {
        DateTime? alp = a.lastPlayed;
        DateTime? blp = b.lastPlayed;
        if (alp == null && blp == null) {
          return titleSort(a, b);
        }
        if (alp == null) {
          return 1;
        }
        if (blp == null) {
          return -1;
        }
        return blp.compareTo(alp);
      };
      break;
    case SortType.Name:
    default:
      compareFunction = titleSort;
      break;
  }

  playlists.sort(compareFunction);

  if (!isAscending) {
    List reversed = playlists.reversed.toList();
    playlists.clear();
    playlists.addAll(reversed);
  }
}

void sortArtist(
  List artistList,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Name:
    default:
      compareFunction =
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
      break;
  }

  artistList.sort(compareFunction);

  if (!isAscending) {
    List reversed = artistList.reversed.toList();
    artistList.clear();
    artistList.addAll(reversed);
  }
}

class VersionUpdateInfo {
  final bool isAvailable;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;

  const VersionUpdateInfo({
    required this.isAvailable,
    required this.latestVersion,
    this.releaseNotes = '',
    this.releaseUrl = appReleasesUrl,
  });
}

List<int> _parseVersionParts(String version) {
  var clean = version.trim();
  if (clean.startsWith('v') || clean.startsWith('V')) {
    clean = clean.substring(1);
  }
  if (clean.contains('+')) {
    clean = clean.split('+')[0];
  }
  if (clean.contains('-')) {
    clean = clean.split('-')[0];
  }
  return clean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
}

bool isVersionGreater(String current, String available) {
  final c = _parseVersionParts(current);
  final a = _parseVersionParts(available);
  final len = max(c.length, a.length);
  for (int i = 0; i < len; i++) {
    final cPart = i < c.length ? c[i] : 0;
    final aPart = i < a.length ? a[i] : 0;
    if (aPart > cPart) return true;
    if (aPart < cPart) return false;
  }
  return false;
}

/// Checks for new version and returns detailed update info
Future<VersionUpdateInfo> newVersionCheckWithDetails(String currentVersion) async {
  try {
    final dio = Dio();
    try {
      final res = await dio.get(appLatestReleaseApiUrl);
      if (res.data != null) {
        final tagName = (res.data['tag_name'] as String?)?.trim() ?? '';
        final htmlUrl = (res.data['html_url'] as String?) ?? appReleasesUrl;
        final body = (res.data['body'] as String?) ?? '';
        final isAvailable = isVersionGreater(currentVersion, tagName);
        return VersionUpdateInfo(
          isAvailable: isAvailable,
          latestVersion: tagName.startsWith('v') || tagName.startsWith('V')
              ? tagName
              : 'v$tagName',
          releaseNotes: body,
          releaseUrl: htmlUrl,
        );
      }
    } catch (_) {
      // Fallback to tags API if latest release endpoint fails
    }

    final tags = (await dio.get(appTagsApiUrl)).data;
    if (tags != null && (tags as List).isNotEmpty) {
      final availableVersion = (tags[0]['name'] as String).trim();
      final isAvailable = isVersionGreater(currentVersion, availableVersion);
      return VersionUpdateInfo(
        isAvailable: isAvailable,
        latestVersion: availableVersion.startsWith('v') || availableVersion.startsWith('V')
            ? availableVersion
            : 'v$availableVersion',
      );
    }
    return const VersionUpdateInfo(isAvailable: false, latestVersion: '');
  } catch (e) {
    printINFO("Error checking new version: $e");
    return const VersionUpdateInfo(isAvailable: false, latestVersion: '');
  }
}

/// Return true if new version available
Future<bool> newVersionCheck(String currentVersion) async {
  final info = await newVersionCheckWithDetails(currentVersion);
  return info.isAvailable;
}

String getTimeString(Duration time) {
  final minutes = time.inMinutes.remainder(Duration.minutesPerHour).toString();
  final seconds = time.inSeconds
      .remainder(Duration.secondsPerMinute)
      .toString()
      .padLeft(2, '0');
  return time.inHours > 0
      ? "${time.inHours}:${minutes.padLeft(2, "0")}:$seconds"
      : "$minutes:$seconds";
}
