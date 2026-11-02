import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../models/artist.dart';
import '../models/playlist.dart';

class InvidiousService extends GetxService {
  static const officialInstances = [
    'https://yt.chocolatemoo53.com',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://invidious.tiekoetter.com',
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ),
  );

  String? _activeInstance;

  Future<dynamic> _get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final instances = [
      if (_activeInstance != null) _activeInstance!,
      ...officialInstances.where((instance) => instance != _activeInstance),
    ];
    Object? lastError;

    for (final instance in instances) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await _dio.get<dynamic>(
            '$instance/api/v1/$endpoint',
            queryParameters: queryParameters,
          );
          final data = response.data is String
              ? jsonDecode(response.data as String)
              : response.data;
          if (data is! List && data is! Map) {
            throw const FormatException('Unexpected Invidious API response');
          }
          _activeInstance = instance;
          return _resolveRelativeMediaUrls(data, Uri.parse(instance));
        } on DioException catch (error) {
          lastError = error;
          if (attempt == 0 &&
              (error.response?.statusCode == 500 ||
                  error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.receiveTimeout)) {
            await Future.delayed(const Duration(milliseconds: 600));
            continue;
          }
          break;
        } on FormatException catch (error) {
          lastError = error;
          break;
        }
      }
    }

    throw InvidiousUnavailableException(
      'All official Invidious instances failed for /api/v1/$endpoint. '
      'Last error: $lastError',
    );
  }

  Future<List<dynamic>> trending({String? type}) async {
    final result = await _get(
      'trending',
      queryParameters: {if (type != null) 'type': type},
    );
    return List<dynamic>.from(result as List);
  }

  Future<List<dynamic>> search(
    String query, {
    String type = 'video',
    int page = 1,
  }) async {
    final result = await _get(
      'search',
      queryParameters: {'q': query, 'type': type, 'page': page},
    );
    return List<dynamic>.from(result as List);
  }

  Future<List<String>> suggestions(String query) async {
    final result = await _get(
      'search/suggestions',
      queryParameters: {'q': query},
    );
    return List<String>.from(
      (result as Map)['suggestions'] as List? ?? const [],
    );
  }

  Future<Map<String, dynamic>> video(
    String videoId, {
    bool local = false,
    String? region,
  }) async {
    final queryParameters = <String, dynamic>{'local': local};
    if (region != null && region.isNotEmpty) {
      queryParameters['region'] = region;
    }
    final result = await _get(
      'videos/${Uri.encodeComponent(videoId)}',
      queryParameters: queryParameters,
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> playlist(
    String playlistId, {
    int page = 1,
  }) async {
    final normalizedId =
        playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;
    final result = await _get(
      'playlists/${Uri.encodeComponent(normalizedId)}',
      queryParameters: {'page': page},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> channel(String channelId) async {
    final normalizedId =
        channelId.startsWith('MPLA') ? channelId.substring(4) : channelId;
    final result = await _get(
      'channels/${Uri.encodeComponent(normalizedId)}',
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<dynamic>> channelVideos(String channelId, {int page = 1}) async {
    final normalizedId =
        channelId.startsWith('MPLA') ? channelId.substring(4) : channelId;
    final result = await _get(
      'channels/${Uri.encodeComponent(normalizedId)}/videos',
      queryParameters: {'page': page},
    );
    return List<dynamic>.from(result as List);
  }

  static List<MediaItem> mediaItems(Iterable<dynamic> videos) {
    return videos
        .whereType<Map>()
        .map((video) => mediaItem(video))
        .whereType<MediaItem>()
        .toList();
  }

  static List<MediaItem> musicTrendItems(Iterable<dynamic> videos) {
    final seenIds = <String>{};
    return videos
        .whereType<Map>()
        .where((video) {
          final lengthSeconds = _asInt(video['lengthSeconds']) ?? 0;
          return video['type'] == 'video' &&
              video['liveNow'] != true &&
              lengthSeconds > 0;
        })
        .map(mediaItem)
        .whereType<MediaItem>()
        .where((item) => seenIds.add(item.id))
        .toList();
  }

  static String resolveMediaUrl(String url, Uri instanceUri) {
    final uri = Uri.parse(url);
    return uri.hasScheme ? url : instanceUri.resolveUri(uri).toString();
  }

  String resolveMediaUrlForActiveInstance(String url) {
    return resolveMediaUrl(
      url,
      Uri.parse(_activeInstance ?? officialInstances.first),
    );
  }

  static dynamic _resolveRelativeMediaUrls(dynamic value, Uri instanceUri) {
    if (value is List) {
      return value
          .map((item) => _resolveRelativeMediaUrls(item, instanceUri))
          .toList();
    }
    if (value is Map) {
      return value.map((key, item) {
        if ((key == 'url' || key == 'playlistThumbnail') && item is String) {
          return MapEntry(key, resolveMediaUrl(item, instanceUri));
        }
        return MapEntry(key, _resolveRelativeMediaUrls(item, instanceUri));
      });
    }
    return value;
  }

  static MediaItem? mediaItem(Map video) {
    final id = video['videoId'] as String?;
    if (id == null || id.isEmpty) return null;

    final title = video['title'] as String? ?? id;
    final author = video['author'] as String? ?? '';
    final authorId = video['authorId'] as String?;
    final seconds = _asInt(video['lengthSeconds']) ?? 0;
    final thumbnails = video['videoThumbnails'];
    final thumbnailUrl = thumbnails is List && thumbnails.isNotEmpty
        ? (thumbnails.last as Map)['url'] as String?
        : null;

    return MediaItem(
      id: id,
      title: title,
      artist: author.isEmpty ? null : author,
      duration: seconds > 0 ? Duration(seconds: seconds) : null,
      artUri: thumbnailUrl == null ? null : Uri.tryParse(thumbnailUrl),
      playable: true,
      extras: {
        'artists': [
          {'name': author, if (authorId != null) 'id': authorId},
        ],
        'length': seconds.toString(),
        'resultType': 'video',
        'invidious': true,
      },
    );
  }

  static Playlist playlistFromJson(Map data) {
    final thumbnail = data['playlistThumbnail'] as String? ?? '';
    return Playlist(
      title: data['title'] as String? ?? 'Playlist',
      playlistId: data['playlistId'] as String? ?? '',
      description: data['description'] as String?,
      thumbnailUrl: thumbnail,
      songCount: data['videoCount']?.toString(),
    );
  }

  static Artist artistFromJson(Map data) {
    final thumbnails = data['authorThumbnails'];
    final thumbnailUrl = thumbnails is List && thumbnails.isNotEmpty
        ? (thumbnails.last as Map)['url'] as String? ?? ''
        : '';
    return Artist(
      name: data['author'] as String? ?? '',
      browseId: data['authorId'] as String? ?? '',
      thumbnailUrl: thumbnailUrl,
      subscribers: data['subCountText'] as String?,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  void onClose() {
    _dio.close();
    super.onClose();
  }
}

class InvidiousUnavailableException implements Exception {
  const InvidiousUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
