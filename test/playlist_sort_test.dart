import 'dart:io';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/piped_service.dart';
import 'package:harmonymusic/services/playlist_song_store.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';

class _Music extends MusicServices {
  List<MediaItem> tracks = [];
  @override
  Future<void> init() async {}
  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs({
    String? playlistId,
    String? albumId,
    int limit = 3000,
    bool related = false,
    int suggestionsLimit = 0,
  }) async =>
      {'tracks': tracks};
}

class _Piped extends PipedServices {
  final collectionsRequested = Completer<void>();
  bool failAddition = false;
  int refreshes = 0;
  @override
  Future<Res> getAllPlaylists() async {
    if (!collectionsRequested.isCompleted) collectionsRequested.complete();
    return Res(1, response: [
      {
        'id': 'owned',
        'name': 'Owned',
        'thumbnail': Playlist.thumbPlaceholderUrl
      },
    ]);
  }

  @override
  Future<Res> addToPlaylist(String id, List<String> songs) async {
    if (failAddition) throw StateError('Addition failed');
    return Res(1);
  }

  @override
  Future<List<MediaItem>> getPlaylistSongs(String id) async {
    refreshes++;
    throw StateError('Refresh failed');
  }
}

class _Library extends LibraryPlaylistsController {
  final writes = <Future<void>>[];
  @override
  Future<void> updatePlaylistIntoDb(Playlist playlist) {
    final write = super.updatePlaylistIntoDb(playlist);
    writes.add(write);
    return write;
  }

  @override
  // Tests exercise the data flow without starting screen animations.
  // ignore: must_call_super
  void onInit() {}
}

class _Controller extends PlaylistScreenController {
  int reads = 0;
  @override
  Future<void> fetchSongsfromDatabase(String id) async {
    reads++;
    await super.fetchSongsfromDatabase(id);
  }
}

class _Context extends Fake implements BuildContext {}

const songs = [
  MediaItem(id: 'one', title: 'Zulu', duration: Duration(seconds: 20)),
  MediaItem(id: 'two', title: 'Alpha', duration: Duration(seconds: 30)),
  MediaItem(id: 'three', title: 'Middle', duration: Duration(seconds: 10)),
];
Map<String, dynamic> json(String id) =>
    MediaItemBuilder.toJson(MediaItem(id: id, title: id));
Playlist playlist(String id, {bool piped = false}) => Playlist(
    title: id,
    playlistId: id,
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
    isCloudPlaylist: piped,
    isPipedPlaylist: piped);

void main() {
  late Directory directory;
  late _Library library;
  final controllers = <_Controller>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harmony-order-');
    Hive.init(directory.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('SongDownloads');
    Get.testMode = true;
    Get.put<MusicServices>(_Music());
    Get.put<PipedServices>(_Piped());
    library = Get.put<LibraryPlaylistsController>(_Library()) as _Library;
  });
  tearDown(() async {
    for (final controller in controllers) {
      await controller.stopSongUpdates();
    }
    controllers.clear();
    await Future.wait(library.writes);
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<_Controller> open(String id, {bool piped = false}) async {
    final controller = _Controller();
    controllers.add(controller);
    controller.playlist.value = playlist(id, piped: piped);
    controller.isDefaultPlaylist.value =
        {'LIBFAV', 'LIBRP', 'SongsCache', 'SongDownloads'}.contains(id);
    controller.loadSortPreference(id);
    await controller.fetchSongsfromDatabase(id);
    return controller;
  }

  List<String> ids(PlaylistScreenController controller) =>
      controller.songList.map((song) => song.id).toList();

  test(
      'criteria, both directions and per-playlist preferences survive reopen and sync',
      () async {
    for (final song in songs) {
      await PlaylistSongStore.put(
          'LIBFAV', song.id, MediaItemBuilder.toJson(song));
    }
    final controller = await open('LIBFAV');
    expect(
        controller.playlistSortController.sortType.value, SortType.AddedOrder);
    for (final type in [
      SortType.Name,
      SortType.Duration,
      SortType.AddedOrder
    ]) {
      final expected = switch (type) {
        SortType.Name => ['two', 'three', 'one'],
        SortType.Duration => ['three', 'one', 'two'],
        _ => ['one', 'two', 'three'],
      };
      for (final ascending in [true, false]) {
        controller.onSort(type, ascending);
        expect(ids(await open('LIBFAV')),
            ascending ? expected : expected.reversed);
      }
    }
    await PlaylistSongStore.append(
        'local', songs.map(MediaItemBuilder.toJson).toList());
    final local = await open('local');
    local.onSort(SortType.Duration, false);
    (Get.find<MusicServices>() as _Music).tracks = songs.reversed.toList();
    await local.syncPlaylistSongs();
    expect(ids(local), ['two', 'one', 'three']);
    expect(ids(await open('LIBFAV')), ['three', 'two', 'one']);
    local.onSort(SortType.AddedOrder, true);
    expect(ids(local), ['three', 'two', 'one']);
  });

  test(
      'text-key legacy songs keep unknown history; cache dates supply known history',
      () async {
    for (final id in ['LIBFAV', 'SongsCache', 'SongDownloads']) {
      final box = await Hive.openBox(id);
      await box.put('z', json('z'));
      await box.put('a', json('a'));
      final previous = box.values.map((row) => row['videoId']).toList();
      final controller = await open(id);
      expect(controller.hasUnknownAdditionOrder, isTrue);
      controller.onSort(SortType.AddedOrder, true);
      await PlaylistSongStore.put(id, '0-new', json('0-new'));
      await pumpEventQueue();
      expect(ids(controller), [...previous, '0-new']);
      expect(box.get('a')['playlistAdditionOrder'], isNull);
      expect(box.get('0-new')['playlistAdditionOrder'], 0);
    }
    // Existing cache dates are trustworthy; video IDs are not chronology.
    await Hive.box('SongsCache').close();
    final box = await Hive.openBox('SongsCache');
    await box.put('dated-a', {...json('dated-a'), 'date': 200});
    await box.put('dated-z', {...json('dated-z'), 'date': 100});
    final dated = await PlaylistSongStore.read('SongsCache');
    expect(
        dated.firstWhere((r) => r.song.id == 'dated-z').additionOrder!,
        lessThan(
            dated.firstWhere((r) => r.song.id == 'dated-a').additionOrder!));
  });

  test(
      'corrupt rows do not block writes, and download deltas do not reload old rows',
      () async {
    for (final id in ['LIBFAV', 'SongsCache', 'SongDownloads', 'local']) {
      final box = await Hive.openBox(id);
      await box.put('broken', 'not a song');
      await box.put('broken-map', {'videoId': 7});
      await PlaylistSongStore.put(id, 'good', json('good'));
      expect((await PlaylistSongStore.read(id)).single.song.id, 'good');
      expect(box.get('broken'), 'not a song');
    }
    final controller = await open('SongDownloads');
    controller.onSort(SortType.Name, false);
    final writes = <dynamic>[];
    final subscription = Hive.box('SongDownloads')
        .watch()
        .listen((event) => writes.add(event.key));
    await Future.wait([
      for (int i = 0; i < 20; i++)
        PlaylistSongStore.put('SongDownloads', 'new-$i', json('new-$i'))
    ]);
    await pumpEventQueue();
    expect(controller.reads, 1);
    expect(writes, hasLength(20));
    expect(writes, isNot(contains('good')));
    final expected = ['good', for (int i = 0; i < 20; i++) 'new-$i']..sort();
    expect(ids(controller), expected.reversed);
    await subscription.cancel();
    await controller.stopSongUpdates();
    await PlaylistSongStore.put(
        'SongDownloads', 'after-close', json('after-close'));
    await pumpEventQueue();
    expect(ids(controller), isNot(contains('after-close')));
  });

  test('bulk removal deletes only the selected occurrence of a repeated track',
      () async {
    final box = await Hive.openBox('duplicates');
    await box.add({...json('repeat'), 'customMetadata': 'keep'});
    await box.add(json('other'));
    await box.add(json('repeat'));
    final controller = await open('duplicates');
    controller.onSort(SortType.Name, true);
    controller.startAdditionalOperation(
        controller.playlistSortController, OperationMode.delete);
    final selected =
        controller.songList.lastWhere((song) => song.id == 'repeat');
    await controller.deleteMultipleSongs([selected]);
    await pumpEventQueue();
    expect(ids(await open('duplicates')).where((id) => id == 'repeat'),
        hasLength(1));
    expect(box.getAt(0)['customMetadata'], 'keep');
    expect(box.values.map((row) => row['playlistAdditionOrder']), [0, 1]);
    expect(
        controller.songsToExport
            .map(MediaItemBuilder.toJson)
            .expand((song) => song.keys),
        isNot(contains(startsWith('playlist'))));
  });

  test(
      'external removals and additions update the full-list thumbnail while searching',
      () async {
    final tracks = [
      for (final id in ['one', 'two', 'three'])
        MediaItem(
            id: id, title: id, artUri: Uri.parse('https://example.com/$id.jpg'))
    ];
    await PlaylistSongStore.append(
        'covers', tracks.map(MediaItemBuilder.toJson).toList());
    final controller = await open('covers');
    controller.playlist.value = controller.playlist.value
        .copyWith(thumbnailUrl: tracks.first.artUri.toString());
    controller.onSearchStart(null);
    controller.onSearch('three', null);
    final box = await Hive.openBox('covers');
    await PlaylistSongStore.remove('covers', [box.keyAt(0)]);
    await pumpEventQueue();
    expect(controller.playlist.value.thumbnailUrl, tracks[1].artUri.toString());
    final saved = await Hive.openBox('LibraryPlaylists');
    expect(Playlist.fromJson(saved.get('covers')).thumbnailUrl,
        tracks[1].artUri.toString());
    expect(ids(controller), ['three']);
    await PlaylistSongStore.remove('covers', box.keys.toList());
    await pumpEventQueue();
    expect(
        controller.playlist.value.thumbnailUrl, Playlist.thumbPlaceholderUrl);
    await PlaylistSongStore.append(
        'covers', [MediaItemBuilder.toJson(tracks.first)]);
    await pumpEventQueue();
    expect(
        controller.playlist.value.thumbnailUrl, tracks.first.artUri.toString());
  });

  test(
      'manual save merges concurrent additions, removals and re-added favorites',
      () async {
    for (final id in ['one', 'two', 'three']) {
      await PlaylistSongStore.put('LIBFAV', id, json(id));
    }
    final controller = await open('LIBFAV');
    controller.startAdditionalOperation(
        controller.playlistSortController, OperationMode.arrange);
    final original = controller.songList.toList();
    controller.additionalOperationTempList.value = [
      original[0],
      original[2],
      original[1]
    ];
    await PlaylistSongStore.remove('LIBFAV', ['one', 'two']);
    await PlaylistSongStore.put('LIBFAV', 'one', json('one'));
    await PlaylistSongStore.put('LIBFAV', 'new', json('new'));
    await Future.wait([
      controller.performAdditionalOperation(),
      PlaylistSongStore.put('LIBFAV', 'during-save', json('during-save'))
    ]);
    expect(ids(await open('LIBFAV')), ['three', 'one', 'new', 'during-save']);
    controller.onSort(SortType.AddedOrder, false);
    expect(ids(controller), ['during-save', 'new', 'one', 'three']);
    expect(Hive.box('LIBFAV').containsKey('one'), isTrue);
  });

  test(
      'refresh failures preserve successful additions and release the loading state',
      () async {
    final controller = await open('owned', piped: true);
    final add = AddToPlaylistController();
    await (Get.find<PipedServices>() as _Piped).collectionsRequested.future;
    await pumpEventQueue();
    add.playlistType.value = 'piped';
    expect(await add.addSongsToPlaylist(songs, 'owned', _Context()), isTrue);
    await pumpEventQueue();
    final piped = Get.find<PipedServices>() as _Piped;
    expect(piped.refreshes, 1);
    expect(controller.isContentFetched.value, isTrue);
    expect(add.additionInProgress.value, isFalse);
    piped.failAddition = true;
    await expectLater(
        add.addSongsToPlaylist(songs, 'owned', _Context()), throwsStateError);
    expect(add.additionInProgress.value, isFalse);
  });

  test(
      'saved Piped playlists retain preferences outside the bounded temporary history',
      () async {
    await library.syncPipedPlaylist();
    final controller = await open('owned', piped: true);
    expect(await controller.checkIfAddedToLibrary('owned'), isFalse);
    controller.onSort(SortType.Duration, false);
    final temporary = SortWidgetController(isTemporaryPreference: () => true);
    final saves = <Future<void>>[];
    for (int i = 0; i < 101; i++) {
      temporary.loadPreference('playlistSort:remote-$i');
      saves.add(temporary.setSort(SortType.Name, false));
    }
    // Revisit an evicted entry before its earlier write has finished.
    temporary.loadPreference('playlistSort:remote-0');
    saves.add(temporary.setSort(SortType.Duration, true));
    saves.add(SortWidgetController.removePlaylistPreference('remote-50'));
    await Future.wait(saves);
    final prefs = Hive.box('AppPrefs');
    expect(prefs.containsKey('playlistSort:owned'), isTrue);
    expect(prefs.get('playlistSort:remote-0'),
        {'type': 'Duration', 'ascending': true});
    expect(prefs.containsKey('playlistSort:remote-1'), isFalse);
    expect(prefs.containsKey('playlistSort:remote-50'), isFalse);
    expect(prefs.get('temporaryPlaylistSorts'), hasLength(99));
    expect(
        prefs.keys
            .where((key) => key.toString().startsWith('playlistSort:remote-')),
        unorderedEquals(prefs.get('temporaryPlaylistSorts')));
    expect(prefs.get('temporaryPlaylistSorts'),
        isNot(contains('playlistSort:owned')));
    await library.blacklistPipedPlaylist(controller.playlist.value);
    expect(prefs.containsKey('playlistSort:owned'), isFalse);
    expect(controller.playlistSortController.isTemporaryPreference!(), isTrue);
  });

  test(
      'removing a playlist waits for queued song writes before deleting its box',
      () async {
    final content = playlist('deleted');
    await (await Hive.openBox('LibraryPlaylists'))
        .put(content.playlistId, content.toJson());
    final controller = await open('deleted');
    await controller.playlistSortController.setSort(SortType.Name, false);
    final writes = [
      for (int i = 0; i < 20; i++)
        PlaylistSongStore.append('deleted', [json('song-$i')])
    ];
    expect(await controller.addNremoveFromLibrary(content, add: false), isTrue);
    await Future.wait(writes);
    await pumpEventQueue();
    expect(await Hive.boxExists('deleted'), isFalse);
    expect((await Hive.openBox('LibraryPlaylists')).containsKey('deleted'),
        isFalse);
    expect(Hive.box('AppPrefs').containsKey('playlistSort:deleted'), isFalse);
  });

  test(
      'library refresh preserves search, sorting, additions and renamed playlists',
      () async {
    var box = await Hive.openBox('LibraryPlaylists');
    for (final title in ['Rock A', 'Rock Z', 'Jazz']) {
      await box.put(title, playlist(title).toJson());
    }
    await library.refreshLib();
    library.onSearchStart(null);
    library.onSearch('rock', null);
    library.onSort(SortType.Name, false);
    box = await Hive.openBox('LibraryPlaylists');
    await box.put('Rock M', playlist('Rock M').toJson());
    await library.refreshLib();
    expect(library.libraryPlaylists.map((p) => p.title),
        ['Rock Z', 'Rock M', 'Rock A']);
    await library.updatePlaylistIntoDb(playlist('Rock A')..title = 'Jazz A');
    expect(library.libraryPlaylists.map((p) => p.title), ['Rock Z', 'Rock M']);
    library.onSearchClose(null);
    expect(library.libraryPlaylists.skip(4).map((p) => p.title),
        ['Rock Z', 'Rock M', 'Jazz A', 'Jazz']);
  });
}
