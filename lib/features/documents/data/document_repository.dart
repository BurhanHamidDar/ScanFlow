// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/files/file_storage_service.dart';
import '../../../core/image_processing/document_detector.dart';
import '../../../core/image_processing/image_processing_service.dart';
import '../../../core/pdf/pdf_service.dart';
import '../../ocr/data/ocr_service.dart';

enum DocumentSort { recentlyEdited, newest, title, pageCount }

class DocumentQuery {
  const DocumentQuery({
    this.search = '',
    this.folderId,
    this.favoritesOnly = false,
    this.deletedOnly = false,
    this.sort = DocumentSort.recentlyEdited,
  });

  final String search;
  final String? folderId;
  final bool favoritesOnly;
  final bool deletedOnly;
  final DocumentSort sort;

  @override
  bool operator ==(Object other) {
    return other is DocumentQuery &&
        other.search == search &&
        other.folderId == folderId &&
        other.favoritesOnly == favoritesOnly &&
        other.deletedOnly == deletedOnly &&
        other.sort == sort;
  }

  @override
  int get hashCode => Object.hash(search, folderId, favoritesOnly, deletedOnly, sort);
}

class HomeStats {
  const HomeStats({
    required this.documents,
    required this.pages,
    required this.favorites,
    required this.storageBytes,
  });

  final int documents;
  final int pages;
  final int favorites;
  final int storageBytes;
}

class DocumentRepository {
  DocumentRepository({
    required AppDatabase database,
    required FileStorageService storage,
    required ImageProcessingService imageProcessing,
    required OcrService ocrService,
    required PdfService pdfService,
  })  : _db = database,
        _storage = storage,
        _imageProcessing = imageProcessing,
        _ocrService = ocrService,
        _pdfService = pdfService;

  final AppDatabase _db;
  final FileStorageService _storage;
  final ImageProcessingService _imageProcessing;
  final OcrService _ocrService;
  final PdfService _pdfService;
  final _uuid = const Uuid();

  Stream<List<ScanDocument>> watchDocuments(DocumentQuery input) {
    final query = _db.select(_db.documents);
    query.where((d) => d.isDeleted.equals(input.deletedOnly));
    if (input.favoritesOnly) {
      query.where((d) => d.isFavorite.equals(true));
    }
    if (input.folderId != null) {
      query.where((d) => d.folderId.equals(input.folderId!));
    }
    final search = input.search.trim();
    if (search.isNotEmpty) {
      final like = '%$search%';
      query.where((d) => d.title.like(like) | d.ocrSummary.like(like));
    }
    query.orderBy([
      (d) => switch (input.sort) {
            DocumentSort.recentlyEdited =>
              OrderingTerm(expression: d.updatedAt, mode: OrderingMode.desc),
            DocumentSort.newest =>
              OrderingTerm(expression: d.createdAt, mode: OrderingMode.desc),
            DocumentSort.title =>
              OrderingTerm(expression: d.title, mode: OrderingMode.asc),
            DocumentSort.pageCount =>
              OrderingTerm(expression: d.pageCount, mode: OrderingMode.desc),
          },
    ]);
    return query.watch();
  }

  Stream<List<Folder>> watchFolders() {
    final query = _db.select(_db.folders)
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);
    return query.watch();
  }

  Stream<ScanDocument?> watchDocument(String id) {
    return (_db.select(_db.documents)..where((d) => d.id.equals(id)))
        .watchSingleOrNull();
  }

  Stream<List<ScanPage>> watchPages(String documentId) {
    final query = _db.select(_db.scanPages)
      ..where((p) => p.documentId.equals(documentId))
      ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]);
    return query.watch();
  }

  Stream<List<OcrResult>> watchOcr(String documentId) {
    final query = _db.select(_db.ocrResults)
      ..where((o) => o.documentId.equals(documentId))
      ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]);
    return query.watch();
  }

  Stream<HomeStats> watchHomeStats() async* {
    await for (final docs in watchDocuments(const DocumentQuery())) {
      yield HomeStats(
        documents: docs.length,
        pages: docs.fold(0, (total, doc) => total + doc.pageCount),
        favorites: docs.where((doc) => doc.isFavorite).length,
        storageBytes: await _storage.storageBytes(),
      );
    }
  }

  Future<String> createFolder(String name) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    await _db.into(_db.folders).insert(
          FoldersCompanion.insert(
            id: id,
            name: name.trim(),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<String> createDocumentFromFiles(List<File> files) async {
    if (files.isEmpty) {
      throw ArgumentError('At least one page is required');
    }
    final now = DateTime.now();
    final documentId = _uuid.v4();
    final title = 'Scan ${DateFormat('MMM d, h:mm a').format(now)}';
    await _db.into(_db.documents).insert(
          DocumentsCompanion.insert(
            id: documentId,
            title: title,
            createdAt: now,
            updatedAt: now,
          ),
        );

    for (var i = 0; i < files.length; i++) {
      await addPage(documentId: documentId, source: files[i], pageIndex: i);
    }
    return documentId;
  }

  Future<void> addPage({
    required String documentId,
    required File source,
    int? pageIndex,
  }) async {
    final pageId = _uuid.v4();
    final original = await _storage.copyOriginal(
      source: source,
      documentId: documentId,
      pageId: pageId,
    );
    final processed = await _imageProcessing.processDocument(source: original);
    final processedFile = await _storage.writeProcessedJpg(
      bytes: processed.bytes,
      documentId: documentId,
      pageId: pageId,
    );
    final existingPages = await (_db.select(_db.scanPages)
          ..where((p) => p.documentId.equals(documentId)))
        .get();
    final index = pageIndex ?? existingPages.length;
    final now = DateTime.now();
    await _db.into(_db.scanPages).insert(
          ScanPagesCompanion.insert(
            id: pageId,
            documentId: documentId,
            pageIndex: index,
            originalPath: original.path,
            processedPath: processedFile.path,
            width: processed.width,
            height: processed.height,
            cropPolygonJson: Value(processed.cropJson),
            filter: Value(ScanFilter.auto.name),
            processingJson: const Value('{}'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _refreshPageCount(documentId);
  }

  Future<void> reprocessPage({
    required ScanPage page,
    required ScanFilter filter,
    required ProcessingSettings settings,
    List<CropPoint>? cropPoints,
    int rotation = 0,
  }) async {
    final processed = await _imageProcessing.processDocument(
      source: File(page.originalPath),
      filter: filter,
      settings: settings,
      cropPoints: cropPoints,
      rotation: rotation,
    );
    final processedFile = await _storage.writeProcessedJpg(
      bytes: processed.bytes,
      documentId: page.documentId,
      pageId: page.id,
    );
    await (_db.update(_db.scanPages)..where((p) => p.id.equals(page.id))).write(
      ScanPagesCompanion(
        processedPath: Value(processedFile.path),
        width: Value(processed.width),
        height: Value(processed.height),
        cropPolygonJson: Value(processed.cropJson),
        filter: Value(filter.name),
        processingJson: Value(settings.toJson().toString()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _touchDocument(page.documentId);
  }

  Future<void> runOcr(
    ScanPage page, {
    TextRecognitionScript script = TextRecognitionScript.latin,
  }) async {
    final extraction = await _ocrService.extractText(
      File(page.processedPath),
      script: script,
    );
    final now = DateTime.now();
    await _db.into(_db.ocrResults).insertOnConflictUpdate(
          OcrResultsCompanion.insert(
            id: '${page.id}-${script.name}',
            documentId: page.documentId,
            pageId: page.id,
            script: extraction.script,
            content: extraction.text,
            confidence: Value(extraction.confidence),
            createdAt: now,
          ),
        );
    final all = await (_db.select(_db.ocrResults)
          ..where((o) => o.documentId.equals(page.documentId)))
        .get();
    final summary = all.map((item) => item.content).join('\n').trim();
    await (_db.update(_db.documents)..where((d) => d.id.equals(page.documentId)))
        .write(
      DocumentsCompanion(
        ocrSummary: Value(summary),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<File> exportPdf(String documentId) async {
    final document = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(documentId)))
        .getSingle();
    final pages = await (_db.select(_db.scanPages)
          ..where((p) => p.documentId.equals(documentId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    final file = await _pdfService.createDocumentPdf(
      documentId: documentId,
      title: document.title,
      pages: pages
          .map((page) => PdfPageInput(path: page.processedPath, label: '${page.pageIndex + 1}'))
          .toList(),
    );
    await _db.into(_db.exports).insert(
          ExportsCompanion.insert(
            id: _uuid.v4(),
            documentId: documentId,
            kind: 'pdf',
            path: file.path,
            byteSize: await file.length(),
            createdAt: DateTime.now(),
          ),
        );
    return file;
  }

  Future<File> exportPagePng(ScanPage page) async {
    final bytes = await _imageProcessing.exportPng(File(page.processedPath));
    final file = await _storage.writePng(
      bytes: bytes,
      documentId: page.documentId,
      pageId: page.id,
    );
    await _db.into(_db.exports).insert(
          ExportsCompanion.insert(
            id: _uuid.v4(),
            documentId: page.documentId,
            kind: 'png',
            path: file.path,
            byteSize: await file.length(),
            createdAt: DateTime.now(),
          ),
        );
    return file;
  }

  Future<void> sharePdf(String documentId) async {
    final file = await exportPdf(documentId);
    await _pdfService.shareFiles([file], text: 'ScanFlow PDF');
  }

  Future<void> shareText(String text) => _pdfService.shareText(text);

  Future<void> previewPdf(String documentId) async {
    final file = await exportPdf(documentId);
    await _pdfService.previewPdf(file);
  }

  Future<void> renameDocument(String id, String title) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(title: Value(title.trim()), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> toggleFavorite(ScanDocument document) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(document.id))).write(
      DocumentsCompanion(
        isFavorite: Value(!document.isFavorite),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> moveDocument(String id, String? folderId) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(folderId: Value(folderId), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> softDeleteDocument(String id) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> restoreDocument(String id) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(
        isDeleted: const Value(false),
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> duplicateDocument(String documentId) async {
    final sourceDoc = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(documentId)))
        .getSingle();
    final pages = await (_db.select(_db.scanPages)
          ..where((p) => p.documentId.equals(documentId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    final now = DateTime.now();
    final newDocumentId = _uuid.v4();
    await _db.into(_db.documents).insert(
          DocumentsCompanion.insert(
            id: newDocumentId,
            title: '${sourceDoc.title} copy',
            folderId: Value(sourceDoc.folderId),
            isFavorite: Value(sourceDoc.isFavorite),
            pageCount: Value(pages.length),
            ocrSummary: Value(sourceDoc.ocrSummary),
            createdAt: now,
            updatedAt: now,
          ),
        );
    for (final page in pages) {
      final newPageId = _uuid.v4();
      final original = await _storage.copyOriginal(
        source: File(page.originalPath),
        documentId: newDocumentId,
        pageId: newPageId,
      );
      final processedBytes = await File(page.processedPath).readAsBytes();
      final processed = await _storage.writeProcessedJpg(
        bytes: processedBytes,
        documentId: newDocumentId,
        pageId: newPageId,
      );
      await _db.into(_db.scanPages).insert(
            ScanPagesCompanion.insert(
              id: newPageId,
              documentId: newDocumentId,
              pageIndex: page.pageIndex,
              originalPath: original.path,
              processedPath: processed.path,
              width: page.width,
              height: page.height,
              rotation: Value(page.rotation),
              cropPolygonJson: Value(page.cropPolygonJson),
              filter: Value(page.filter),
              processingJson: Value(page.processingJson),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  Future<void> deletePage(ScanPage page) async {
    await (_db.delete(_db.scanPages)..where((p) => p.id.equals(page.id))).go();
    final files = [File(page.originalPath), File(page.processedPath)];
    for (final file in files) {
      if (file.existsSync()) {
        await file.delete();
      }
    }
    await _reindexPages(page.documentId);
    await _refreshPageCount(page.documentId);
  }

  Future<void> rotatePage(ScanPage page, int degrees) async {
    final rotation = (page.rotation + degrees) % 360;
    await reprocessPage(
      page: page,
      filter: ScanFilter.values.firstWhere(
        (filter) => filter.name == page.filter,
        orElse: () => ScanFilter.auto,
      ),
      settings: const ProcessingSettings(),
      rotation: rotation,
    );
    await (_db.update(_db.scanPages)..where((p) => p.id.equals(page.id))).write(
      ScanPagesCompanion(rotation: Value(rotation), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> _refreshPageCount(String documentId) async {
    final count = await (_db.select(_db.scanPages)
          ..where((p) => p.documentId.equals(documentId)))
        .get()
        .then((pages) => pages.length);
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId))).write(
      DocumentsCompanion(pageCount: Value(count), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> _reindexPages(String documentId) async {
    final pages = await (_db.select(_db.scanPages)
          ..where((p) => p.documentId.equals(documentId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    for (var i = 0; i < pages.length; i++) {
      await (_db.update(_db.scanPages)..where((p) => p.id.equals(pages[i].id)))
          .write(ScanPagesCompanion(pageIndex: Value(i)));
    }
  }

  Future<void> _touchDocument(String documentId) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId))).write(
      DocumentsCompanion(updatedAt: Value(DateTime.now())),
    );
  }
}
