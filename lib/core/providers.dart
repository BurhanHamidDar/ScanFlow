import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../features/documents/data/document_repository.dart';
import '../features/ocr/data/ocr_service.dart';
import 'database/app_database.dart';
import 'files/file_storage_service.dart';
import 'image_processing/document_detector.dart';
import 'image_processing/image_processing_service.dart';
import 'pdf/pdf_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final fileStorageProvider = Provider<FileStorageService>((ref) {
  return FileStorageService();
});

final documentDetectorProvider = Provider<DocumentDetector>((ref) {
  return DocumentDetector();
});

final imageProcessingProvider = Provider<ImageProcessingService>((ref) {
  return ImageProcessingService(ref.watch(documentDetectorProvider));
});

final ocrServiceProvider = Provider<OcrService>((ref) {
  return OcrService();
});

final pdfServiceProvider = Provider<PdfService>((ref) {
  return PdfService(ref.watch(fileStorageProvider));
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(fileStorageProvider),
    imageProcessing: ref.watch(imageProcessingProvider),
    ocrService: ref.watch(ocrServiceProvider),
    pdfService: ref.watch(pdfServiceProvider),
  );
});

final documentsProvider =
    StreamProvider.autoDispose.family<List<ScanDocument>, DocumentQuery>((ref, query) {
  return ref.watch(documentRepositoryProvider).watchDocuments(query);
});

final foldersProvider = StreamProvider.autoDispose<List<Folder>>((ref) {
  return ref.watch(documentRepositoryProvider).watchFolders();
});

final homeStatsProvider = StreamProvider.autoDispose<HomeStats>((ref) {
  return ref.watch(documentRepositoryProvider).watchHomeStats();
});

final documentProvider =
    StreamProvider.autoDispose.family<ScanDocument?, String>((ref, id) {
  return ref.watch(documentRepositoryProvider).watchDocument(id);
});

final pagesProvider =
    StreamProvider.autoDispose.family<List<ScanPage>, String>((ref, documentId) {
  return ref.watch(documentRepositoryProvider).watchPages(documentId);
});

final ocrProvider =
    StreamProvider.autoDispose.family<List<OcrResult>, String>((ref, documentId) {
  return ref.watch(documentRepositoryProvider).watchOcr(documentId);
});
