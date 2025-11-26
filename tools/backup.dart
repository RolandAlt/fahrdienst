import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  //
  // Zielverzeichnis (kannst du oben ändern)
  //
  final backupRoot = r'C:\Backups\Fahrdienst App';

  //
  // Projektverzeichnis (da wo du das Script startest)
  //
  final projectDir = Directory.current.path;

  //
  // Ordner & Dateien, die gesichert werden sollen
  //
  final itemsToBackup = [
    'android',
    'assets',
//    'ios',
    'lib',
    'tools',
    'patches',
//    'web',
//    'windows',
//    'linux',
//    'macos',
    'pubspec.yaml',
    'pubspec.lock',
    'analysis_options.yaml',
    'build/app/outputs/apk/release',
  ];

  final timestamp = DateTime.now()
      .toString()
      .replaceAll(':', '-')
      .replaceAll('.', '-')
      .replaceAll(' ', '_');

  final backupPath =
      p.join(backupRoot, 'FahrdienstApp_Backup_$timestamp');

  final backupDir = Directory(backupPath);

  print('Erstelle Backup: $backupPath');
  await backupDir.create(recursive: true);

  for (final item in itemsToBackup) {
    final sourcePath = p.join(projectDir, item);
    final source = FileSystemEntity.typeSync(sourcePath);

    if (source == FileSystemEntityType.notFound) {
      print('Übersprungen (nicht gefunden): $item');
      continue;
    }

    final targetPath = p.join(backupPath, item);

    if (source == FileSystemEntityType.directory) {
      await _copyDirectory(
        Directory(sourcePath),
        Directory(targetPath),
      );
      print('✓ Ordner kopiert: $item');
    } else if (source == FileSystemEntityType.file) {
      await File(sourcePath)
          .copy(targetPath);
      print('✓ Datei kopiert: $item');
    }
  }

  print('\nBackup erfolgreich abgeschlossen.');
}

Future<void> _copyDirectory(
    Directory source, Directory dest) async {
  await dest.create(recursive: true);

  await for (final entity in source.list(recursive: false)) {
    if (entity is Directory) {
      final newDir = Directory(
          p.join(dest.path, p.basename(entity.path)));
      await _copyDirectory(entity, newDir);
    } else if (entity is File) {
      await entity.copy(
          p.join(dest.path, p.basename(entity.path)));
    }
  }
}
