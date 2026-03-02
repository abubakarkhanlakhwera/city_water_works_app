import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';

class BackupService {
  final AppDatabase _db = AppDatabase.instance;

  String _nowFormatted() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
  }

  /// Create a backup file (.cww = zip of DB + metadata)
  Future<String> createBackup() async {
    final dbPath = await _db.databasePath;
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      throw Exception('Database file not found');
    }

    // Create metadata
    final metadata = {
      'app_version': '1.0.0',
      'schema_version': 1,
      'created_at': _nowFormatted(),
      'platform': Platform.operatingSystem,
    };

    // Create archive
    final archive = Archive();

    // Add database file
    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile('city_water_works.db', dbBytes.length, dbBytes));

    // Add metadata JSON
    final metadataBytes = utf8.encode(jsonEncode(metadata));
    archive.addFile(ArchiveFile('metadata.json', metadataBytes.length, metadataBytes));

    // Encode as zip
    final zipBytes = ZipEncoder().encode(archive);

    // Save backup file
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final filename = 'CityWaterWorks_Backup_${_nowFormatted()}.cww';
    final backupFile = File('${backupDir.path}/$filename');
    await backupFile.writeAsBytes(zipBytes!);

    return backupFile.path;
  }

  /// Restore from a backup file
  Future<void> restoreBackup(String backupPath) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception('Backup file not found');
    }

    final bytes = await backupFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Verify metadata
    ArchiveFile? metadataFile;
    ArchiveFile? dbBackupFile;

    for (final file in archive) {
      if (file.name == 'metadata.json') metadataFile = file;
      if (file.name == 'city_water_works.db') dbBackupFile = file;
    }

    if (dbBackupFile == null) {
      throw Exception('Invalid backup file: database not found');
    }

    if (metadataFile != null) {
      final metadata = jsonDecode(utf8.decode(metadataFile.content));
      final schemaVersion = metadata['schema_version'] ?? 1;
      // Validate schema version
      if (schemaVersion > 1) {
        throw Exception('Backup from newer app version (schema v$schemaVersion). Please update the app.');
      }
    }

    // Close current database
    await _db.closeDatabase();

    // Replace database
    final dbPath = await _db.databasePath;
    final targetFile = File(dbPath);

    // Delete existing
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    // Write restored DB
    await targetFile.writeAsBytes(dbBackupFile.content);

    // Re-initialize database
    await _db.database;
  }

  /// List available local backups
  Future<List<BackupInfo>> listBackups() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/backups');

    if (!await backupDir.exists()) return [];

    final files = await backupDir
        .list()
        .where((f) => f.path.endsWith('.cww'))
        .toList();

    final backups = <BackupInfo>[];
    for (final f in files) {
      final file = File(f.path);
      final stat = await file.stat();
      backups.add(BackupInfo(
        path: f.path,
        filename: f.path.split(Platform.pathSeparator).last,
        size: stat.size,
        date: stat.modified,
      ));
    }

    backups.sort((a, b) => b.date.compareTo(a.date));
    return backups.take(10).toList();
  }

  /// Delete all data (factory reset)
  Future<void> deleteAllData() async {
    final db = await _db.database;
    await db.delete('billing_entries');
    await db.delete('machinery');
    await db.delete('sets');
    await db.delete('schemes');
  }
}

class BackupInfo {
  final String path;
  final String filename;
  final int size;
  final DateTime date;

  BackupInfo({
    required this.path,
    required this.filename,
    required this.size,
    required this.date,
  });

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
