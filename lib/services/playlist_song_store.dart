import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';

/// Playlist metadata stays in storage, never in a MediaItem or shared export.
class PlaylistSongRecord {
  PlaylistSongRecord(this.key, Map<dynamic, dynamic> json)
      : json = Map<String, dynamic>.from(json);

  final dynamic key;
  final Map<String, dynamic> json;
  late final MediaItem song = MediaItemBuilder.fromJson(json);
  int? get additionOrder {
    final value = json['playlistAdditionOrder'];
    return value is int && value >= 0 ? value : null;
  }

  int get position => (json['playlistPosition'] as int?) ?? 0;
}

class PlaylistSongChange {
  const PlaylistSongChange(this.playlistId,
      {this.upserts = const [],
      this.removedKeys = const [],
      this.remote = false});

  final String playlistId;
  final List<PlaylistSongRecord> upserts;
  final List<dynamic> removedKeys;
  final bool remote;
}

class _OrderState {
  bool initialized = false;
  int nextAddition = 0;
  int nextPosition = 0;
}

/// Serializes playlist mutations and publishes deltas after successful writes.
/// Consumers refresh independently: their failures cannot fail a saved song.
class PlaylistSongStore {
  static final _changes = StreamController<PlaylistSongChange>.broadcast();
  static Stream<PlaylistSongChange> get changes => _changes.stream;
  static final _states = Expando<_OrderState>();
  static final _pending = <String, Future<void>>{};

  static Future<T> _enqueue<T>(String id, Future<T> Function() work) {
    final queueKey = id.toLowerCase();
    final previous = _pending[queueKey] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _pending[queueKey] = tail;
    tail.then((_) {
      if (identical(_pending[queueKey], tail)) _pending.remove(queueKey);
    });
    return result;
  }

  static Future<T> _run<T>(
          String id, Future<T> Function(Box, _OrderState) work) =>
      _enqueue(id, () async {
        final wasOpen = Hive.isBoxOpen(id);
        final box = await Hive.openBox(id);
        try {
          final state = _states[box] ??= _OrderState();
          await _initialize(box, state);
          return await work(box, state);
        } finally {
          if (!wasOpen &&
              box.isOpen &&
              !{'libfav', 'librp', 'songscache', 'songdownloads'}
                  .contains(id.toLowerCase())) {
            await box.close();
          }
        }
      });

  /// Wait for previously queued writes before removing the playlist's box.
  static Future<void> delete(String id) =>
      _enqueue(id, () => Hive.deleteBoxFromDisk(id));

  static Future<void> _initialize(Box box, _OrderState state) async {
    if (state.initialized) return;
    final updates = <dynamic, dynamic>{};
    final legacy = <(dynamic, num)>[];
    for (final key in box.keys) {
      final json = _songJson(box.get(key));
      if (json == null) continue;
      final order = json['playlistAdditionOrder'];
      if (order is int && order >= state.nextAddition) {
        state.nextAddition = order + 1;
      }
      final position = json['playlistPosition'];
      if (position is int && position >= state.nextPosition) {
        state.nextPosition = position + 1;
      }
    }
    for (final key in box.keys) {
      final original = _songJson(box.get(key));
      if (original == null) continue;
      final json = Map<String, dynamic>.from(original);
      final order = json['playlistAdditionOrder'];
      if (json.containsKey('playlistAdditionOrder') &&
          order != null &&
          (order is! int || order < 0)) {
        json['playlistAdditionOrder'] = null;
      }
      if (!json.containsKey('playlistAdditionOrder')) {
        final num? history = key is int
            ? key
            : box.name.toLowerCase() == 'songscache' && json['date'] is num
                ? json['date'] as num
                : null;
        json['playlistAdditionOrder'] = null;
        if (history != null) legacy.add((key, history));
      }
      // Positions describe the existing display sequence, not addition history.
      if (json['playlistPosition'] is! int) {
        json['playlistPosition'] = state.nextPosition++;
      }
      if (!_sameMetadata(original, json)) updates[key] = json;
    }
    legacy.sort((a, b) {
      final result = a.$2.compareTo(b.$2);
      return result != 0
          ? result
          : (updates[a.$1]['playlistPosition'] as int)
              .compareTo(updates[b.$1]['playlistPosition'] as int);
    });
    for (final entry in legacy) {
      final json =
          updates[entry.$1] ?? Map<String, dynamic>.from(box.get(entry.$1));
      json['playlistAdditionOrder'] = state.nextAddition++;
      updates[entry.$1] = json;
    }
    if (updates.isNotEmpty) await box.putAll(updates);
    state.initialized = true;
  }

  static bool _sameMetadata(Map a, Map b) =>
      a.containsKey('playlistAdditionOrder') &&
      a['playlistAdditionOrder'] == b['playlistAdditionOrder'] &&
      a['playlistPosition'] == b['playlistPosition'];

  static Map<String, dynamic>? _songJson(dynamic value) {
    if (value is! Map ||
        value['videoId'] is! String ||
        value['title'] is! String) {
      return null;
    }
    // Leave damaged entries untouched; a bad row must not block other songs.
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      return null;
    }
  }

  static List<PlaylistSongRecord> _records(Box box) => [
        for (final key in box.keys)
          if (_songJson(box.get(key)) case final json?)
            PlaylistSongRecord(key, json),
      ]..sort((a, b) => a.position.compareTo(b.position));

  static Future<List<PlaylistSongRecord>> read(String id) =>
      _run(id, (box, _) async => _records(box));

  static Map<String, dynamic> _newSong(
          Map<String, dynamic> song, _OrderState state) =>
      {
        ...song,
        'playlistAdditionOrder': state.nextAddition++,
        'playlistPosition': state.nextPosition++,
      };

  static Future<void> put(String id, dynamic key, Map<String, dynamic> song) =>
      _run(id, (box, state) async {
        final existing = _songJson(box.get(key));
        final json = existing == null
            ? _newSong(song, state)
            : {
                ...song,
                'playlistAdditionOrder': existing['playlistAdditionOrder'],
                'playlistPosition': existing['playlistPosition']
              };
        await box.put(key, json);
        _changes.add(
            PlaylistSongChange(id, upserts: [PlaylistSongRecord(key, json)]));
      });

  static Future<void> append(String id, List<Map<String, dynamic>> songs,
          {bool skipDuplicates = false}) =>
      _run(id, (box, state) async {
        final ids = skipDuplicates
            ? box.values
                .map(_songJson)
                .whereType<Map<String, dynamic>>()
                .map((song) => song['videoId'])
                .toSet()
            : <dynamic>{};
        final added = <PlaylistSongRecord>[];
        for (final song in songs) {
          if (skipDuplicates && !ids.add(song['videoId'])) continue;
          final json = _newSong(song, state);
          final key = await box.add(json);
          added.add(PlaylistSongRecord(key, json));
        }
        if (added.isNotEmpty) {
          _changes.add(PlaylistSongChange(id, upserts: added));
        }
      });

  static Future<void> remove(String id, List<dynamic> keys) =>
      _run(id, (box, _) async {
        await box.deleteAll(keys);
        _changes.add(PlaylistSongChange(id, removedKeys: keys));
      });

  static Future<void> recentlyPlayed(MediaItem song) =>
      _run('LIBRP', (box, state) async {
        final current = _records(box);
        final removed = current
            .where((entry) => entry.song.id == song.id)
            .map((e) => e.key)
            .toList();
        final remaining =
            current.where((entry) => entry.song.id != song.id).toList();
        if (remaining.length >= 30) {
          removed
              .addAll(remaining.take(remaining.length - 29).map((e) => e.key));
        }
        await box.deleteAll(removed);
        final json = _newSong(MediaItemBuilder.toJson(song), state);
        final key = await box.add(json);
        _changes.add(PlaylistSongChange('LIBRP',
            removedKeys: removed, upserts: [PlaylistSongRecord(key, json)]));
      });

  /// A rearrangement changes positions only. Concurrent additions are appended;
  /// concurrent removals are excluded. No existing song is cleared or recreated.
  static Future<List<PlaylistSongRecord>> reorder(
          String id, List<dynamic> requestedKeys,
          {Map<dynamic, int?>? originalAdditions}) =>
      _run(id, (box, state) async {
        final current = _records(box);
        final requested = requestedKeys
            .where((key) =>
                box.containsKey(key) &&
                (originalAdditions == null ||
                    originalAdditions[key] ==
                        box.get(key)['playlistAdditionOrder']))
            .toSet();
        final keys = [
          ...requested,
          ...current
              .where((entry) => !requested.contains(entry.key))
              .map((entry) => entry.key),
        ];
        final updates = <dynamic, dynamic>{
          for (int i = 0; i < keys.length; i++)
            keys[i]: {
              ...Map<String, dynamic>.from(box.get(keys[i])),
              'playlistPosition': i
            },
        };
        await box.putAll(updates);
        state.nextPosition = keys.length;
        final records = _records(box);
        _changes.add(PlaylistSongChange(id, upserts: records));
        return records;
      });

  /// Used for authoritative online snapshots, never for local rearrangements.
  static Future<void> saveSnapshot(String id, List<PlaylistSongRecord> songs) =>
      _run(id, (box, state) async {
        final updates = <dynamic, dynamic>{
          for (int i = 0; i < songs.length; i++)
            i: {...songs[i].json, 'playlistPosition': i},
        };
        final removed =
            box.keys.where((key) => !updates.containsKey(key)).toList();
        await box.putAll(updates);
        await box.deleteAll(removed);
        state.initialized = false;
        _changes.add(PlaylistSongChange(id,
            upserts: _records(box), removedKeys: removed));
      });

  static void remoteChanged(String id) =>
      _changes.add(PlaylistSongChange(id, remote: true));
}
