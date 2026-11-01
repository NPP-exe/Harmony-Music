import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/invidious_service.dart';

void main() {
  group('InvidiousService.resolveMediaUrl', () {
    const instanceUri = 'https://yt.chocolatemoo53.com';

    test('resolves cached relative thumbnails against the active instance', () {
      final service = InvidiousService();
      addTearDown(service.onClose);

      expect(
        service.resolveMediaUrlForActiveInstance('/vi/video-id/3.jpg'),
        '$instanceUri/vi/video-id/3.jpg',
      );
    });

    test('resolves a relative thumbnail against the Invidious instance', () {
      final resolved = InvidiousService.resolveMediaUrl(
        '/vi/video-id/3.jpg',
        Uri.parse(instanceUri),
      );

      expect(
        resolved,
        'https://yt.chocolatemoo53.com/vi/video-id/3.jpg',
      );
    });

    test('preserves an absolute thumbnail URL', () {
      final resolved = InvidiousService.resolveMediaUrl(
        'https://i.ytimg.com/vi/video-id/hqdefault.jpg',
        Uri.parse(instanceUri),
      );

      expect(
        resolved,
        'https://i.ytimg.com/vi/video-id/hqdefault.jpg',
      );
    });
  });

  group('InvidiousService.musicTrendItems', () {
    test('filters live streams and items without a duration', () {
      final items = InvidiousService.musicTrendItems([
        {
          'type': 'video',
          'videoId': 'song-id',
          'title': 'A music video',
          'lengthSeconds': 180,
          'liveNow': false,
          'videoThumbnails': [],
        },
        {
          'type': 'video',
          'videoId': 'live-id',
          'title': 'Live stream',
          'lengthSeconds': 0,
          'liveNow': true,
        },
        {
          'type': 'video',
          'videoId': 'unknown-length-id',
          'title': 'Unknown length',
          'lengthSeconds': 0,
          'liveNow': false,
        },
        {
          'type': 'channel',
          'authorId': 'channel-id',
          'author': 'Not a video',
        },
      ]);

      expect(items.map((item) => item.id), ['song-id']);
    });
  });
}
