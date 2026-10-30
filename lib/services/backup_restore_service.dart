import 'dart:io';
import 'dart:isolate';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'backup_archive.dart';
import 'backup_restore_journal.dart';

class PreparedBackup {
  PreparedBackup(this.directory, this.files);
  final String directory;
  final List<String> files;
  RandomAccessFile? _lock;

  Future<void> dispose() async {
    try {
      // A pending journal owns the recovery copies until startup resolves it.
      if (await File(p.join(directory, 'journal.json')).exists()) {
        return;
      }
      final dir = Directory(directory);
      if (await dir.exists()) await dir.delete(recursive: true);
    } finally {
      await _lock?.close();
      _lock = null;
    }
  }
}

class BackupRestoreException implements Exception {
  BackupRestoreException(this.cause,
      {required this.restartRequired, this.recoveryRequired = false});
  final Object cause;
  final bool restartRequired;
  final bool recoveryRequired;

  @override
  String toString() => 'Backup restoration failed: $cause';
}

class BackupRestoreService {
  BackupRestoreService(
      {required String databaseDirectory, required String supportDirectory})
      : databaseDirectory = p.normalize(databaseDirectory),
        supportDirectory = p.normalize(supportDirectory);
  final String databaseDirectory;
  final String supportDirectory;

  Future<RandomAccessFile> _acquireLock({bool wait = true}) async {
    await Directory(supportDirectory).create(recursive: true);
    final file = await File(p.join(supportDirectory, '.harmony-restore.lock'))
        .open(mode: FileMode.append);
    try {
      await file.lock(wait ? FileLock.blockingExclusive : FileLock.exclusive);
      return file;
    } catch (error) {
      await file.close();
      if (!wait) {
        throw FileSystemException(
            'Could not lock application recovery. Close any other instance '
            'and retry. $error',
            file.path);
      }
      rethrow;
    }
  }

  Future<PreparedBackup> prepare(String archivePath,
      {required bool relocateDownloads}) async {
    final lock = await _acquireLock();
    Directory? stage;
    try {
      stage = await Directory(supportDirectory)
          .createTemp(BackupRestoreJournal.stagePrefix);
      final result = await _runPreparation(
          archivePath, stage.path, supportDirectory, relocateDownloads);
      result._lock = lock;
      return result;
    } catch (error) {
      try {
        if (stage != null) await stage.delete(recursive: true);
      } finally {
        await lock.close();
      }
      if (error is HiveError || error is RemoteError) {
        throw FormatException('Could not validate backup databases: $error');
      }
      rethrow;
    }
  }

  /// Recover interrupted installation before Hive can create or open any box.
  Future<void> recoverPending() async {
    RandomAccessFile? lock;
    try {
      lock = await _acquireLock(wait: false);
      await for (final entry
          in _directories(supportDirectory, BackupRestoreJournal.stagePrefix)) {
        final journal = File(p.join(entry.path, 'journal.json'));
        if (await journal.exists()) {
          final pending = await BackupRestoreJournal.load(entry.path,
              databaseDirectory: databaseDirectory,
              supportDirectory: supportDirectory);
          if (pending.state == 'installing') await pending.rollback();
          await pending.cleanup();
        } else {
          // No original moves until journal.json has been atomically installed.
          await entry.delete(recursive: true);
        }
      }
      // Only discard workspaces that have no saved originals. An orphan old/
      // has no journal to establish which files may safely replace live data.
      await for (final workspace in _workspaces()) {
        if (await _containsOriginals(workspace)) {
          throw FormatException(
              'Saved originals have no recovery journal: ${workspace.path}');
        }
        await workspace.delete(recursive: true);
      }
    } catch (error) {
      throw BackupRecoveryException(error);
    } finally {
      await lock?.close();
    }
  }

  /// Explicitly abandon automatic recovery without deleting its saved files.
  /// Each directory stays on its filesystem and is ignored by future recovery.
  Future<List<String>> quarantinePending() async {
    final lock = await _acquireLock(wait: false);
    final quarantined = <String>[];
    try {
      final pending = [
        ...await _directories(
                supportDirectory, BackupRestoreJournal.stagePrefix)
            .toList(),
        ...await _workspaces().toList(),
      ];
      for (final entry in pending) {
        // createTemp reserves a unique destination beside the source. Keep
        // its original basename so journal references remain inspectable.
        final container = await entry.parent.createTemp('.harmony-quarantine-');
        try {
          final moved = await entry
              .rename(p.join(container.path, p.basename(entry.path)));
          quarantined.add(moved.path);
        } catch (_) {
          await container.delete();
          rethrow;
        }
      }
      return quarantined;
    } finally {
      await lock.close();
    }
  }

  Stream<Directory> _workspaces() async* {
    for (final parent in {
      databaseDirectory,
      p.join(supportDirectory, 'Music'),
      p.join(supportDirectory, 'thumbnails'),
    }) {
      yield* _directories(parent, BackupRestoreJournal.workspacePrefix);
    }
  }

  static Stream<Directory> _directories(String parent, String prefix) async* {
    final directory = Directory(parent);
    if (!await directory.exists()) return;
    for (final entry in await directory.list(followLinks: false).toList()) {
      if (entry is Directory && p.basename(entry.path).startsWith(prefix)) {
        yield entry;
      }
    }
  }

  static Future<bool> _containsOriginals(Directory workspace) async {
    final old = Directory(p.join(workspace.path, 'old'));
    return await FileSystemEntity.isLink(old.path) ||
        (await old.exists() && !await old.list(followLinks: false).isEmpty);
  }

  /// Stage beside destinations by rename whenever possible. Originals remain
  /// recoverable until a commit marker has been recorded. Directory renames
  /// are not fsynced; recovery does not guarantee power-loss durability.
  Future<void> apply(
    PreparedBackup backup, {
    required Future<void> Function() closeDatabases,
    void Function(int)? onProgress,
  }) async {
    if (backup._lock == null) {
      throw StateError('Apply requires an active backup from prepare()');
    }
    final workspaces = <String, Directory>{};
    final replacements = <String, File>{};
    BackupRestoreJournal? journal;
    var restartRequired = false;
    var resolved = false;
    try {
      for (final relative in backup.files) {
        final group = p.split(relative).first;
        final parent = group == 'database'
            ? databaseDirectory
            : p.join(supportDirectory, group);
        final workspace = workspaces[group] ??= await () async {
          await Directory(parent).create(recursive: true);
          return Directory(parent)
              .createTemp(BackupRestoreJournal.workspacePrefix);
        }();
        final name = p.basename(relative);
        final staged = File(p.join(workspace.path, 'new', name));
        await staged.parent.create(recursive: true);
        final source = File(p.join(backup.directory, relative));
        try {
          await source.rename(staged.path);
        } on FileSystemException {
          // Separate filesystems cannot rename. Copy only this entry, then
          // release its old staging copy before processing the next one.
          await source.copy(staged.path);
          await source.delete();
        }
        replacements[relative] = staged;
      }
      restartRequired = true;
      await closeDatabases();
      final entries = <RestoreEntry>[];
      final targets = <String>{...replacements.keys};
      await for (final file in Directory(databaseDirectory).list()) {
        if (file is File && file.path.endsWith('.hive')) {
          targets.add(p.join('database', p.basename(file.path)));
        }
      }
      for (final relative in targets) {
        final group = p.split(relative).first;
        final name = p.basename(relative);
        final parent = group == 'database'
            ? databaseDirectory
            : p.join(supportDirectory, group);
        entries.add(RestoreEntry(group, name,
            hadOriginal: await File(p.join(parent, name)).exists(),
            hasReplacement: replacements.containsKey(relative)));
      }
      final pending = BackupRestoreJournal(
          directory: backup.directory,
          databaseDirectory: databaseDirectory,
          supportDirectory: supportDirectory,
          workspaces: workspaces
              .map((group, dir) => MapEntry(group, p.basename(dir.path))),
          entries: entries);
      await pending.save('installing');
      journal = pending;
      for (final entry in entries.where((entry) => entry.hadOriginal)) {
        final old = File(pending.original(entry));
        await old.parent.create(recursive: true);
        await File(pending.target(entry)).rename(old.path);
      }
      var progress = 0;
      for (final entry in entries.where((entry) => entry.hasReplacement)) {
        await File(pending.replacement(entry)).rename(pending.target(entry));
        onProgress?.call(++progress);
      }
      await pending.save('committed');
      resolved = true;
    } catch (error) {
      var rollbackFailed = false;
      if (journal != null) {
        try {
          await journal.rollback();
          resolved = true;
        } catch (_) {
          rollbackFailed = true;
        }
      }
      throw BackupRestoreException(error,
          restartRequired: restartRequired, recoveryRequired: rollbackFailed);
    } finally {
      try {
        if (journal != null && resolved) {
          await journal.cleanup();
        } else if (journal == null) {
          // No original has moved until the initial journal was saved.
          for (final workspace in workspaces.values) {
            if (await workspace.exists()) {
              await workspace.delete(recursive: true);
            }
          }
          final file = File(p.join(backup.directory, 'journal.json'));
          if (await file.exists()) await file.delete();
        }
      } on FileSystemException {
        // Retain the committed/rolled-back journal for cleanup at startup.
      }
    }
  }
}

// Keep the worker closure in its own scope so it cannot capture file locks or
// application controllers, which cannot be transferred between isolates.
Future<PreparedBackup> _runPreparation(String archivePath, String stagePath,
        String support, bool relocateDownloads) =>
    Isolate.run(() async {
      final files = BackupArchive.extract(archivePath, stagePath);
      final databasePath = p.join(stagePath, 'database');
      Hive.init(databasePath);
      try {
        // Read the staged databases with recovery disabled. A corrupt Hive
        // file must not replace a working database or be silently truncated.
        for (final relative in files.where((file) => file.endsWith('.hive'))) {
          final box = await Hive.openBox(p.basenameWithoutExtension(relative),
              crashRecovery: false);
          await box.close();
        }
        if (relocateDownloads &&
            files.contains(p.join('database', 'songdownloads.hive'))) {
          final downloads = await Hive.openBox('SongDownloads');
          for (final key in downloads.keys.toList()) {
            final value = downloads.get(key);
            if (value is! Map || value['url'] is! String) continue;
            final song = Map<dynamic, dynamic>.from(value);
            // Backups may have originated on Windows or on a Unix platform.
            final name =
                (song['url'] as String).replaceAll('\\', '/').split('/').last;
            final path = p.join(support, 'Music', name);
            song['url'] = path;
            final stream = song['streamInfo'];
            if (stream is List && stream.length > 1 && stream[1] is Map) {
              final updatedStream = List<dynamic>.from(stream);
              updatedStream[1] = Map<dynamic, dynamic>.from(stream[1])
                ..['url'] = path;
              song['streamInfo'] = updatedStream;
            }
            await downloads.put(key, song);
          }
        }
      } finally {
        await Hive.close();
      }
      return PreparedBackup(stagePath, files);
    });
