import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/empty_state.dart';

class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentProvider(documentId));
    final pages = ref.watch(pagesProvider(documentId));
    final ocr = ref.watch(ocrProvider(documentId));

    return Scaffold(
      appBar: AppBar(
        title: document.maybeWhen(
          data: (value) => Text(value?.title ?? 'Document'),
          orElse: () => const Text('Document'),
        ),
        actions: [
          IconButton(
            tooltip: 'Preview PDF',
            onPressed: () => ref.read(documentRepositoryProvider).previewPdf(documentId),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Share PDF',
            onPressed: () => ref.read(documentRepositoryProvider).sharePdf(documentId),
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: pages.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.layers_clear_outlined,
              title: 'No pages',
              message: 'This document has no pages left.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _PagesGrid(items: items)),
                        Expanded(child: _OcrPanel(documentId: documentId, ocr: ocr)),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: _PagesGrid(items: items)),
                        SizedBox(height: 220, child: _OcrPanel(documentId: documentId, ocr: ocr)),
                      ],
                    );
            },
          );
        },
        error: (error, _) => Center(child: Text('Could not load pages: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _PagesGrid extends ConsumerWidget {
  const _PagesGrid({required this.items});

  final List<ScanPage> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 330,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _PageCard(page: items[index]),
    );
  }
}

class _PageCard extends ConsumerWidget {
  const _PageCard({required this.page});

  final ScanPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(documentRepositoryProvider);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: Image.file(File(page.processedPath), fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Page ${page.pageIndex + 1}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Edit filters',
                      onPressed: () => context.push('/documents/${page.documentId}/editor/${page.id}'),
                      icon: const Icon(Icons.tune),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Run OCR',
                      onPressed: () => _chooseOcrScript(context, ref, page),
                      icon: const Icon(Icons.text_fields),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Rotate',
                      onPressed: () => repo.rotatePage(page, 90),
                      icon: const Icon(Icons.rotate_right),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Export PNG',
                      onPressed: () async {
                        final file = await repo.exportPagePng(page);
                        await repo.shareText('PNG exported to ${file.path}');
                      },
                      icon: const Icon(Icons.image_outlined),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Delete page',
                      onPressed: () => repo.deletePage(page),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseOcrScript(
    BuildContext context,
    WidgetRef ref,
    ScanPage page,
  ) async {
    final script = await showModalBottomSheet<TextRecognitionScript>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('OCR language script')),
            for (final script in TextRecognitionScript.values)
              ListTile(
                title: Text(script.name),
                onTap: () => Navigator.pop(context, script),
              ),
          ],
        ),
      ),
    );
    if (script == null) {
      return;
    }
    await ref.read(documentRepositoryProvider).runOcr(page, script: script);
  }
}

class _OcrPanel extends ConsumerWidget {
  const _OcrPanel({required this.documentId, required this.ocr});

  final String documentId;
  final AsyncValue<List<OcrResult>> ocr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ocr.when(
          data: (items) {
            final text =
                items.map((item) => item.content).where((item) => item.isNotEmpty).join('\n\n');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('OCR Text', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Copy text',
                      onPressed: text.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: text)),
                      icon: const Icon(Icons.copy),
                    ),
                    IconButton(
                      tooltip: 'Share text',
                      onPressed: text.isEmpty
                          ? null
                          : () => ref.read(documentRepositoryProvider).shareText(text),
                      icon: const Icon(Icons.ios_share),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: text.isEmpty
                      ? const Center(child: Text('Run OCR on a page to extract searchable text.'))
                      : SingleChildScrollView(child: SelectableText(text)),
                ),
              ],
            );
          },
          error: (error, _) => Text('OCR unavailable: $error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
