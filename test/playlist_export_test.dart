import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_screen_controller.dart';

class _MusicServices extends MusicServices {
  @override
  Future<void> init() async {}
}

void main() {
  tearDown(() => Get.reset());

  test('export includes all songs while a search filters or hides every result',
      () {
    Get.testMode = true;
    Get.put<MusicServices>(_MusicServices());
    final controller = PlaylistScreenController();
    controller.songList.assignAll(const [
      MediaItem(id: 'one', title: 'First song'),
      MediaItem(id: 'two', title: 'Second song'),
      MediaItem(id: 'one', title: 'First song'),
    ]);

    controller.onSearchStart(null);
    controller.onSearch('Second', null);
    expect(controller.songList.map((song) => song.id), ['two']);
    expect(
        controller.songsToExport.map((song) => song.id), ['one', 'two', 'one']);

    controller.onSearch('No matching songs', null);
    expect(controller.songList, isEmpty);
    expect(
        controller.songsToExport.map((song) => song.id), ['one', 'two', 'one']);

    controller.onSearchClose(null);
    expect(
        controller.songsToExport.map((song) => song.id), ['one', 'two', 'one']);
  });
}
