import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final stats = ref.watch(homeStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (value) {
                      ref.read(themeModeProvider.notifier).state = value.single;
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: stats.when(
              data: (value) => Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('Local storage'),
                    subtitle: Text(_formatBytes(value.storageBytes)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Documents'),
                    subtitle: Text('${value.documents} scans, ${value.pages} pages'),
                  ),
                ],
              ),
              error: (error, _) => ListTile(title: Text('Storage unavailable: $error')),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Create local backup'),
                  subtitle: const Text('Archive ScanFlow data and share it to a safe location.'),
                  onTap: () => _createBackup(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('Restore backup'),
                  subtitle: const Text('Import a ScanFlow backup archive from device storage.'),
                  onTap: () => _restoreBackup(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.language_outlined),
                  title: Text('Language'),
                  subtitle: Text('OCR script is chosen per page before extraction.'),
                ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('ScanFlow'),
                  subtitle: Text('Developer: Burhan Hamid\nOffline document scanner, version 1.0.0'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    final file = await ref.read(fileStorageProvider).createBackupArchive();
    await SharePlus.instance.share(
      ShareParams(
        text: 'ScanFlow backup',
        files: [XFile(file.path)],
      ),
    );
  }

  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result?.paths.whereType<String>().firstOrNull;
    if (path == null) {
      return;
    }
    await ref.read(fileStorageProvider).restoreBackupArchive(File(path));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored. Restart ScanFlow to reload restored metadata.')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
