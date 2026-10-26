import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class BackupRecoveryException implements Exception {
  BackupRecoveryException(this.cause);
  final Object cause;
  @override
  String toString() => 'Could not recover a pending backup restore: $cause';
}

/// Only basenames and known destination groups are persisted in the journal.
/// Recovery never accepts an arbitrary destination path from a JSON file.
class RestoreEntry {
  RestoreEntry(this.group, this.name,
      {required this.hadOriginal, required this.hasReplacement});
  final String group;
  final String name;
  final bool hadOriginal;
  final bool hasReplacement;

  Map<String, dynamic> toJson() => {
        'group': group,
        'name': name,
        'hadOriginal': hadOriginal,
        'hasReplacement': hasReplacement,
      };
}

class BackupRestoreJournal {
  BackupRestoreJournal(
      {required this.directory,
      required this.databaseDirectory,
      required this.supportDirectory,
      required this.workspaces,
      required this.entries,
      this.state = 'installing'});

  static const stagePrefix = '.harmony-backup-stage-';
  static const workspacePrefix = '.harmony-restore-';
  final String directory;
  final String databaseDirectory;
  final String supportDirectory;
  final Map<String, String> workspaces;
  final List<RestoreEntry> entries;
  String state;

  String parent(String group) =>
      group == 'database' ? databaseDirectory : p.join(supportDirectory, group);
  String workspace(String group) => p.join(parent(group), workspaces[group]!);
  String target(RestoreEntry entry) => p.join(parent(entry.group), entry.name);
  String original(RestoreEntry entry) =>
      p.join(workspace(entry.group), 'old', entry.name);
  String replacement(RestoreEntry entry) =>
      p.join(workspace(entry.group), 'new', entry.name);

  Future<void> save(String newState) async {
    final file = File(p.join(directory, 'journal.json'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'state': newState,
          'workspaces': workspaces,
          'entries': entries.map((entry) => entry.toJson()).toList(),
        }),
        flush: true);
    await temporary.rename(file.path);
    state = newState;
  }

  static Future<BackupRestoreJournal> load(String directory,
      {required String databaseDirectory,
      required String supportDirectory}) async {
    final file = File(p.join(directory, 'journal.json'));
    final data = jsonDecode(await file.readAsString());
    if (data is! Map ||
        data['version'] != 1 ||
        !['installing', 'committed', 'rolledBack'].contains(data['state']) ||
        data['workspaces'] is! Map ||
        data['entries'] is! List) {
      throw const FormatException('Invalid restore journal');
    }
    final workspaces = <String, String>{};
    for (final entry in (data['workspaces'] as Map).entries) {
      if (!_validGroup(entry.key) ||
          !_basename(entry.value) ||
          !(entry.value as String).startsWith(workspacePrefix)) {
        throw const FormatException('Invalid restore workspace');
      }
      workspaces[entry.key as String] = entry.value as String;
    }
    final entries = <RestoreEntry>[];
    final targets = <String>{};
    for (final value in data['entries'] as List) {
      if (value is! Map ||
          !_validGroup(value['group']) ||
          !validName(value['group'], value['name']) ||
          !workspaces.containsKey(value['group']) ||
          value['hadOriginal'] is! bool ||
          value['hasReplacement'] is! bool ||
          !targets.add('${value['group']}/${value['name']}')) {
        throw const FormatException('Invalid restore entry');
      }
      entries.add(RestoreEntry(value['group'], value['name'],
          hadOriginal: value['hadOriginal'],
          hasReplacement: value['hasReplacement']));
    }
    final journal = BackupRestoreJournal(
        directory: directory,
        databaseDirectory: databaseDirectory,
        supportDirectory: supportDirectory,
        workspaces: workspaces,
        entries: entries,
        state: data['state']);
    for (final group in workspaces.keys) {
      if (await FileSystemEntity.isLink(journal.workspace(group))) {
        throw const FormatException('Restore workspace is a symbolic link');
      }
      final old = Directory(p.join(journal.workspace(group), 'old'));
      if (await old.exists()) {
        await for (final file in old.list(followLinks: false)) {
          if (file is! File ||
              !entries.any((entry) =>
                  entry.group == group &&
                  entry.name == p.basename(file.path) &&
                  entry.hadOriginal)) {
            throw const FormatException(
                'Unregistered original in recovery workspace');
          }
        }
      }
    }
    return journal;
  }

  /// Idempotent: originals already recovered on an earlier attempt are kept.
  Future<void> rollback() async {
    Object? failure;
    for (final entry in entries.reversed) {
      try {
        final saved = File(original(entry));
        final destination = File(target(entry));
        if (entry.hadOriginal) {
          if (await saved.exists()) {
            if (await destination.exists()) await destination.delete();
            await saved.rename(destination.path);
          } else if (!await destination.exists()) {
            throw FileSystemException(
                'Original file is missing', destination.path);
          }
        } else if (entry.hasReplacement &&
            !await File(replacement(entry)).exists() &&
            await destination.exists()) {
          await destination.delete();
        }
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw BackupRecoveryException(failure);
    await save('rolledBack');
  }

  Future<void> cleanup() async {
    if (state == 'installing') throw StateError('Unresolved restore journal');
    for (final group in workspaces.keys) {
      final path = workspace(group);
      if (await FileSystemEntity.isLink(path)) {
        throw FileSystemException('Restore workspace is a symbolic link', path);
      }
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    final dir = Directory(directory);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static bool _validGroup(dynamic value) =>
      ['database', 'Music', 'thumbnails'].contains(value);
  static bool _basename(dynamic value) =>
      value is String &&
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains(':') &&
      !value.contains('\u0000');
  static bool validName(dynamic group, dynamic name) {
    if (!_basename(name)) return false;
    final suffix = p.extension(name as String).toLowerCase();
    return group == 'database'
        ? suffix == '.hive'
        : group == 'thumbnails'
            ? suffix == '.png'
            : group == 'Music' &&
                ['.mp3', '.m4a', '.opus', '.aac'].contains(suffix);
  }
}
