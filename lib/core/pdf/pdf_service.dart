import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../files/file_storage_service.dart';

class PdfPageInput {
  const PdfPageInput({
    required this.path,
    required this.label,
  });

  final String path;
  final String label;
}

class PdfService {
  const PdfService(this._storage);

  final FileStorageService _storage;

  Future<File> createDocumentPdf({
    required String documentId,
    required String title,
    required List<PdfPageInput> pages,
    int jpegQuality = 92,
  }) async {
    final pdf = pw.Document(title: title, author: 'Burhan Hamid');

    for (final page in pages) {
      final bytes = await File(page.path).readAsBytes();
      final image = pw.MemoryImage(bytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final file = await _storage.writeExport(
      documentId: documentId,
      fileName: '${_safeName(title)}.pdf',
      bytes: await pdf.save(),
    );
    return file;
  }

  Future<void> previewPdf(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> shareFiles(List<File> files, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: files.map((file) => XFile(file.path)).toList(),
      ),
    );
  }

  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^\w\-. ]+'), '').trim();
    return cleaned.isEmpty ? 'ScanFlow Document' : cleaned;
  }
}
