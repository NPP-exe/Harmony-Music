import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/playlist_import_service.dart';

Map<String, dynamic> exportData(List<dynamic> songs) => {
      'playlistInfo': Playlist(
        title: 'Minha playlist',
        playlistId: 'cloud-id',
        thumbnailUrl: 'https://example.com/cover.png',
        description: 'Descrição',
        isPipedPlaylist: true,
      ).toJson(),
      'songs': songs,
    };

void main() {
  late Directory directory;
  late Box library;
  late Box preferences;
  late Box favorites;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harmony-playlist-test-');
    Hive.init(directory.path);
    library = await Hive.openBox('LibraryPlaylists');
    await library.put('existing', {'title': 'Existing playlist'});
    preferences = await Hive.openBox('AppPrefs');
    await preferences.put('theme', 'dark');
    favorites = await Hive.openBox('LIBFAV');
    await favorites.add({'videoId': 'favorite', 'title': 'Favorite song'});
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<Playlist?> import(PlaylistImportData data,
          {void Function(double)? onProgress}) =>
      PlaylistImportService().importPlaylist(data,
          importedLabel: 'importada',
          fallbackDescription: 'Playlist importada',
          onProgress: onProgress);

  test('imports valid tracks in order, preserves metadata and existing data',
      () async {
    final song = {
      'videoId': 'one',
      'title': 'First',
      'album': {'name': 'Album without a remote ID'},
      'futureMetadata': {'source': 'original'},
    };
    final file = File('${directory.path}/playlist.json');
    await file.writeAsString(jsonEncode(exportData([
      song,
      {'title': '  Música rejeitada — ao vivo  '},
      {'videoId': 'two', 'title': 'Second'},
      {'videoId': 'bad', 'title': 'Outra música', 'length': 'invalid'},
      song,
      null,
    ])));
    final data = await PlaylistImportData.readFile(file.path);
    final playlist = (await import(data))!;
    expect(playlist.title, 'Minha playlist (importada)');
    expect(playlist.description, 'Descrição');
    expect(playlist.isCloudPlaylist, isFalse);
    expect(playlist.isPipedPlaylist, isFalse);
    expect(playlist.playlistId, isNot('cloud-id'));
    final songs = await Hive.openBox(playlist.playlistId);
    expect(songs.values.map((song) => song['videoId']), ['one', 'two', 'one']);
    expect(songs.values.first, song);
    expect(data.rejectedSongTitles,
        ['  Música rejeitada — ao vivo  ', 'Outra música', null]);
    expect(library.get('existing')['title'], 'Existing playlist');
    expect(preferences.get('theme'), 'dark');
    expect(favorites.values.single['videoId'], 'favorite');
  });

  test('rejecting every track creates no playlist or song database', () async {
    final filesBefore = directory.listSync().map((file) => file.path).toSet();
    final data = PlaylistImportData.parse(jsonEncode(exportData([
      {'title': 'Rejected'},
    ])));
    expect(await import(data), isNull);
    expect(library.keys, ['existing']);
    expect(directory.listSync().map((file) => file.path).toSet(), filesBefore);
  });

  test('a failed write removes the partial import and preserves existing data',
      () async {
    final filesBefore = directory.listSync().map((file) => file.path).toSet();
    final data = PlaylistImportData.parse(jsonEncode(exportData([
      {'videoId': 'one', 'title': 'First'},
      {'videoId': 'two', 'title': 'Second'},
    ])));
    await expectLater(
      import(data,
          onProgress: (_) => throw HiveError('Simulated write failure')),
      throwsA(isA<HiveError>()),
    );
    expect(library.keys, ['existing']);
    expect(directory.listSync().map((file) => file.path).toSet(), filesBefore);
    expect(preferences.get('theme'), 'dark');
    expect(favorites.length, 1);
  });
}
