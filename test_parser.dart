import 'package:harmonymusic/services/nav_parser.dart';
void main() {
  final runs = [
    { 'text': 'Artist Name', 'navigationEndpoint': { 'browseEndpoint': { 'browseId': 'UC1234' } } },
    { 'text': ' • ' },
    { 'text': 'Album Name', 'navigationEndpoint': { 'browseEndpoint': { 'browseId': 'MPREb_1234' } } },
    { 'text': ' • ' },
    { 'text': '3:45' }
  ];
  print(parseSongRuns(runs));
}

