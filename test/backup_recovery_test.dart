import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:harmonymusic/services/backup_restore_journal.dart';
import 'package:harmonymusic/services/backup_restore_service.dart';

void main() {
  late Directory root;
  late String database;
  late String support;
  late BackupRestoreService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('harmony-recovery-test-');
    support = p.join(root.path, 'support');
    database = p.join(root.path, 'documents');
    await Directory(support).create();
    await Directory(database).create();
    service = BackupRestoreService(
        databaseDirectory: database, supportDirectory: support);
  });
  tearDown(() => root.delete(recursive: true));

  Future<BackupRestoreJournal> interruptedRestore() async {
    final stage =
        await Directory(support).createTemp(BackupRestoreJournal.stagePrefix);
    final workspaces = <String, String>{};
    for (final group in ['database', 'Music']) {
      final parent = group == 'database' ? database : p.join(support, group);
      await Directory(parent).create(recursive: true);
      final workspace = await Directory(parent)
          .createTemp(BackupRestoreJournal.workspacePrefix);
      workspaces[group] = p.basename(workspace.path);
    }
    final journal = BackupRestoreJournal(
      directory: stage.path,
      databaseDirectory: database,
      supportDirectory: support,
      workspaces: workspaces,
      entries: [
        RestoreEntry('database', 'appprefs.hive',
            hadOriginal: true, hasReplacement: true),
        RestoreEntry('Music', 'track.mp3',
            hadOriginal: true, hasReplacement: true),
      ],
    );
    await journal.save('installing');
    // Snapshot after installation, interrupted before the commit marker.
    for (final entry in journal.entries) {
      final original = File(journal.original(entry));
      await original.parent.create(recursive: true);
      await original.writeAsString('original ${entry.name}');
      await File(journal.target(entry)).writeAsString('new ${entry.name}');
    }
    return journal;
  }

  test('startup rolls back an interrupted installation', () async {
    final journal = await interruptedRestore();
    await service.recoverPending();
    for (final entry in journal.entries) {
      expect(await File(journal.target(entry)).readAsString(),
          'original ${entry.name}');
      expect(await Directory(journal.workspace(entry.group)).exists(), isFalse);
    }
    expect(await Directory(journal.directory).exists(), isFalse);
  });

  test('quarantine preserves pending files and leaves current data untouched',
      () async {
    final journal = await interruptedRestore();
    await File(p.join(journal.directory, 'journal.json'))
        .writeAsString('invalid journal');
    await expectLater(
        service.recoverPending(), throwsA(isA<BackupRecoveryException>()));
    final quarantined = await service.quarantinePending();
    expect(quarantined, hasLength(3));
    final stage = quarantined.singleWhere(
        (path) => p.basename(path) == p.basename(journal.directory));
    expect(await File(p.join(stage, 'journal.json')).readAsString(),
        'invalid journal');
    for (final entry in journal.entries) {
      final workspace = quarantined.singleWhere((path) =>
          p.basename(path) == p.basename(journal.workspace(entry.group)));
      expect(await File(p.join(workspace, 'old', entry.name)).readAsString(),
          'original ${entry.name}');
      expect(await File(journal.target(entry)).readAsString(),
          'new ${entry.name}');
      expect(await Directory(journal.workspace(entry.group)).exists(), isFalse);
    }
    expect(await Directory(journal.directory).exists(), isFalse);
    await service.recoverPending();
    for (final path in quarantined) {
      expect(await Directory(path).exists(), isTrue);
    }
  });
}
