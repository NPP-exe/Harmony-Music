// ignore_for_file: avoid_print
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  const videoId = 'dQw4w9WgXcQ'; // Rick roll
  
  print('Fetching manifest for $videoId');
  
  try {
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [
        YoutubeApiClient.tv,
        YoutubeApiClient.ios,
        YoutubeApiClient.androidVr,
      ],
    );
    
    print('Manifest fetched successfully.');
    print('Audio only streams:');
    for (final audio in manifest.audioOnly) {
      print(' - ${audio.tag} (${audio.audioCodec}) | Bitrate: ${audio.bitrate} | URL: ${audio.url.toString().substring(0, 50)}...');
      
      // Test URL accessibility
      final client = HttpClient();
      try {
        final request = await client.headUrl(audio.url);
        final response = await request.close();
        print('   HEAD status: ${response.statusCode}');
        if (response.statusCode >= 400) {
          final getReq = await client.getUrl(audio.url);
          final getRes = await getReq.close();
          print('   GET status: ${getRes.statusCode}');
        }
      } catch (e) {
        print('   Failed to access URL: $e');
      }
    }
  } catch (e, st) {
    print('Error fetching manifest: $e');
    print(st);
  } finally {
    yt.close();
    exit(0);
  }
}
