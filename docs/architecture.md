# ScanFlow Architecture

## Product Scope

ScanFlow is an offline-first Flutter document scanning app for Android, designed for daily productivity use. It stores all documents, pages, OCR text, folders, tags, settings, and generated exports on device. There is no backend, cloud dependency, authentication, or internet requirement.

## Architecture

ScanFlow uses Clean Architecture with a feature-first structure. Each feature owns its presentation, application, domain, and data layers where needed.

```text
lib/
  app/
    bootstrap/
    router/
    theme/
  core/
    database/
    errors/
    files/
    image_processing/
    pdf/
    preferences/
    widgets/
  features/
    documents/
      data/
      domain/
      presentation/
    scanner/
      data/
      domain/
      presentation/
    editor/
      domain/
      presentation/
    ocr/
      data/
      domain/
    pdf_tools/
      domain/
      presentation/
    settings/
      presentation/
  main.dart
```

## Feature List

Implemented feature targets:

- Home: recent scans, search, grid/list view, favorites, folders, statistics, storage usage, recently edited, sorting.
- Scanner: live camera preview, flash modes, manual capture, auto-capture mode, grid overlay, multipage capture workflow.
- Document detection: real edge-map based crop suggestion, rectangle scoring, draggable crop corners, perspective crop, deskew/rotation.
- Image processing: brightness, contrast, saturation, sharpness, exposure, gamma, auto enhance, smart enhance.
- Filters: Original, Auto, Black & White, Grayscale, Magic Color, Color Document, High Contrast, Receipt Mode, ID Card Mode, Photo Mode.
- OCR: offline on-device text extraction, copied/shared/exported text, searchable OCR records, language script selection.
- PDF: generated multipage PDFs, page rearrange/delete/rotate, app-level merge/split, compression options, preview, share/export.
- Document management: folders, favorites, tags, search, sort, rename, duplicate, move, delete, restore.
- Export: PDF, JPG, PNG, share, print.
- Settings: theme, language, storage management, backup/restore, app information.

## Database Schema

Drift SQLite tables:

- `folders`: folder metadata and counters.
- `documents`: document title, folder, favorite state, deleted state, timestamps, page count, OCR summary.
- `pages`: image paths, processed image paths, page order, dimensions, rotation, crop polygon, filter, processing settings.
- `tags`: tag labels and colors.
- `document_tags`: many-to-many document/tag join.
- `ocr_results`: page/document text, script, confidence metadata, extracted timestamp.
- `exports`: generated PDF/image/text artifacts and sizes.
- `app_settings`: persisted user preferences.

All file paths are local app-document-directory paths. The database stores metadata only; images and exported files are stored in dedicated app folders.

## Package Selection

- `flutter_riverpod`: robust typed app state, dependency injection, and testable providers.
- `riverpod_annotation`, `riverpod_generator`, `build_runner`: generated provider code where it improves maintainability.
- `go_router`: declarative navigation for scanner/editor/document/settings flows.
- `drift`, `drift_flutter`, `sqlite3_flutter_libs`: typed SQLite schema, migrations, and reliable offline persistence.
- `path_provider`, `path`: app-local storage paths and portable path manipulation.
- `camera`: real live camera preview, flash control, and high-quality image capture.
- `image`: pure Dart image decoding, filters, enhancement, crop, rotate, sharpen, and compression.
- `google_mlkit_text_recognition`: offline on-device OCR through ML Kit text recognition.
- `pdf`: real PDF generation from processed document pages.
- `printing`: PDF preview, print, and share integration.
- `share_plus`: sharing exported PDFs, images, and text.
- `file_picker`: backup restore/import file selection.
- `archive`: local backup and restore archive creation/extraction.
- `permission_handler`: camera and storage-related runtime permissions.
- `flutter_svg`: crisp vector icons/assets if needed.
- `intl`: date, time, and localized formatting.
- `uuid`: stable IDs for documents/pages/exports.

## Implementation Notes

The document detection pipeline is intentionally local and deterministic:

1. Decode the captured image.
2. Downsample for fast analysis.
3. Convert to grayscale and apply contrast normalization.
4. Run Sobel edge detection.
5. Score candidate document bounds from high-energy edge projections.
6. Suggest a rectangle and allow manual corner adjustment.
7. Crop/perspective-adjust the selected document area and save the processed page.

PDF operations are implemented against ScanFlow documents and pages. Merging combines selected documents into a generated multipage PDF. Splitting creates new documents or generated PDFs from selected page ranges. Compression re-encodes page images before PDF generation.
