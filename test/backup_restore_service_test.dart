import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:harmonymusic/services/backup_restore_service.dart';

Future<Map<dynamic, dynamic>> readDownloads(String stage) =>
    Isolate.run(() async {
      Hive.init(p.join(stage, 'database'));
      final box = await Hive.openBox('SongDownloads');
      final result = box.toMap();
      await Hive.close();
      return result;
    });

Future<File> createBackup(String root, {bool corruptDatabase = false}) async {
  final databases = await Isolate.run(() async {
    final dir = Directory(p.join(root, 'fixture-db'))
      ..createSync(recursive: true);
    Hive.init(dir.path);
    final preferences = await Hive.openBox('AppPrefs');
    await preferences.put('theme', 'backup-theme');
    final playlists = await Hive.openBox('LibraryPlaylists');
    await playlists.put('backup-playlist', {'title': 'Backup playlist'});
    final downloads = await Hive.openBox('SongDownloads');
    await downloads.put('no-stream', {
      'videoId': 'no-stream',
      'url': r'C:\Downloads\track.mp3',
    });
    await downloads.put('with-stream', {
      'videoId': 'with-stream',
      'url': '/old/Music/track.mp3',
      'streamInfo': [
        true,
        {'url': '/old/Music/track.mp3'}
      ],
    });
    await Hive.close();
    return <String, List<int>>{
      for (final file in dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.hive')))
        p.basename(file.path): file.readAsBytesSync(),
    };
  });
  if (corruptDatabase) databases['appprefs.hive'] = [1, 2, 3];
  final archive = Archive();
  for (final entry in databases.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  archive.addFile(ArchiveFile.string('track.mp3', 'restored audio'));
  archive.addFile(ArchiveFile.string('cover.png', 'restored cover'));
  return File(p.join(root, 'backup.hmb'))
    ..writeAsBytesSync(ZipEncoder().encode(archive)!);
}

void main() {
  late Directory directory;
  late BackupRestoreService service;
  late String databasePath;
  late String supportPath;
  late Box preferences;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('harmony-restore-test-');
    databasePath = p.join(directory.path, 'live', 'db');
    supportPath = p.join(directory.path, 'live');
    await Directory(databasePath).create(recursive: true);
    Hive.init(databasePath);
    preferences = await Hive.openBox('AppPrefs');
    await preferences.put('theme', 'original-theme');
    final obsolete = await Hive.openBox('Obsolete');
    await obsolete.put('data', 'original-data');
    service = BackupRestoreService(
        databaseDirectory: databasePath, supportDirectory: supportPath);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('a corrupt Hive database is rejected while current data remains open',
      () async {
    final file = await createBackup(directory.path, corruptDatabase: true);
    await expectLater(service.prepare(file.path, relocateDownloads: true),
        throwsFormatException);
    expect(preferences.isOpen, isTrue);
    expect(preferences.get('theme'), 'original-theme');
  });

  test('restores databases and MP3 files and removes obsolete database entries',
      () async {
    final file = await createBackup(directory.path);
    final backup = await service.prepare(file.path, relocateDownloads: true);
    try {
      expect(preferences.isOpen, isTrue);
      expect(p.dirname(backup.directory), supportPath);
      final songs = await readDownloads(backup.directory);
      final expected = p.join(supportPath, 'Music', 'track.mp3');
      expect(songs['no-stream']['url'], expected);
      expect(songs['no-stream'].containsKey('streamInfo'), isFalse);
      expect(songs['with-stream']['streamInfo'][1]['url'], expected);
      await service.apply(backup, closeDatabases: () async {
        // Entries have moved out of the extraction area before live data closes.
        for (final relative in backup.files) {
          expect(
              await File(p.join(backup.directory, relative)).exists(), isFalse);
        }
        await Hive.close();
      });
      final restored = await Hive.openBox('AppPrefs');
      expect(restored.get('theme'), 'backup-theme');
      expect(
          await File(p.join(databasePath, 'obsolete.hive')).exists(), isFalse);
      expect(
          await File(p.join(supportPath, 'Music', 'track.mp3')).readAsString(),
          'restored audio');
      expect(
          await File(p.join(supportPath, 'thumbnails', 'cover.png'))
              .readAsString(),
          'restored cover');
    } finally {
      await backup.dispose();
    }
  });

  test('a real installation failure recovers databases already replaced',
      () async {
    final file = await createBackup(directory.path);
    final backup = await service.prepare(file.path, relocateDownloads: true);
    // The MP3 target is a directory: copies to the preparation area succeed,
    // but installation fails after replacing the databases.
    final blocked = Directory(p.join(supportPath, 'Music', 'track.mp3'));
    await blocked.create(recursive: true);
    try {
      await expectLater(
          service.apply(backup, closeDatabases: Hive.close),
          throwsA(isA<BackupRestoreException>()
              .having(
                  (error) => error.restartRequired, 'requires restart', true)
              .having((error) => error.recoveryRequired, 'rollback incomplete',
                  false)));
      expect(preferences.isOpen, isFalse);
      final recovered = await Hive.openBox('AppPrefs');
      expect(recovered.get('theme'), 'original-theme');
      final obsolete = await Hive.openBox('Obsolete');
      expect(obsolete.get('data'), 'original-data');
      expect(await blocked.exists(), isTrue);
    } finally {
      await backup.dispose();
    }
  });
}
