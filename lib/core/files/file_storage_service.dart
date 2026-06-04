import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileStorageService {
  Future<Directory> get _root async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'scanflow'));
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> documentDirectory(String documentId) async {
    final root = await _root;
    final dir = Directory(p.join(root.path, 'documents', documentId));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> exportsDirectory(String documentId) async {
    final root = await _root;
    final dir = Directory(p.join(root.path, 'exports', documentId));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> copyOriginal({
    required File source,
    required String documentId,
    required String pageId,
  }) async {
    final dir = await documentDirectory(documentId);
    final target = File(p.join(dir.path, '$pageId-original.jpg'));
    return source.copy(target.path);
  }

  Future<File> writeProcessedJpg({
    required Uint8List bytes,
    required String documentId,
    required String pageId,
  }) async {
    final dir = await documentDirectory(documentId);
    final target = File(p.join(dir.path, '$pageId-processed.jpg'));
    return target.writeAsBytes(bytes, flush: true);
  }

  Future<File> writePng({
    required Uint8List bytes,
    required String documentId,
    required String pageId,
  }) async {
    final dir = await documentDirectory(documentId);
    final target = File(p.join(dir.path, '$pageId.png'));
    return target.writeAsBytes(bytes, flush: true);
  }

  Future<File> writeExport({
    required String documentId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final dir = await exportsDirectory(documentId);
    final file = File(p.join(dir.path, fileName));
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<int> storageBytes() async {
    final root = await _root;
    if (!root.existsSync()) {
      return 0;
    }
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> deleteDocumentFiles(String documentId) async {
    final root = await _root;
    final docDir = Directory(p.join(root.path, 'documents', documentId));
    final exportDir = Directory(p.join(root.path, 'exports', documentId));
    if (docDir.existsSync()) {
      await docDir.delete(recursive: true);
    }
    if (exportDir.existsSync()) {
      await exportDir.delete(recursive: true);
    }
  }

  Future<File> createBackupArchive() async {
    final appDir = await getApplicationDocumentsDirectory();
    final archive = Archive();
    await for (final entity in appDir.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: appDir.path);
      if (relative.startsWith('scanflow-backups')) {
        continue;
      }
      archive.addFile(ArchiveFile(
        relative.replaceAll('\\', '/'),
        await entity.length(),
        await entity.readAsBytes(),
      ));
    }
    final bytes = ZipEncoder().encode(archive);
    final temp = await getTemporaryDirectory();
    final file = File(
      p.join(temp.path, 'scanflow-backup-${DateTime.now().millisecondsSinceEpoch}.zip'),
    );
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> restoreBackupArchive(File backup) async {
    final appDir = await getApplicationDocumentsDirectory();
    final root = p.normalize(appDir.path);
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final targetPath = p.normalize(p.join(appDir.path, file.name));
      if (!p.isWithin(root, targetPath) && targetPath != root) {
        throw const FileSystemException('Backup contains an invalid path');
      }
      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content as List<int>, flush: true);
    }
  }
}
