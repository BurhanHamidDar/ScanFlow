import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'document_detector.dart';

enum ScanFilter {
  original('Original'),
  auto('Auto'),
  blackWhite('Black & White'),
  grayscale('Grayscale'),
  magicColor('Magic Color'),
  colorDocument('Color Document'),
  highContrast('High Contrast'),
  receipt('Receipt Mode'),
  idCard('ID Card Mode'),
  photo('Photo Mode');

  const ScanFilter(this.label);
  final String label;
}

class ProcessingSettings {
  const ProcessingSettings({
    this.brightness = 1,
    this.contrast = 1,
    this.saturation = 1,
    this.sharpness = 0,
    this.exposure = 0,
    this.gamma = 1,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpness;
  final double exposure;
  final double gamma;

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'sharpness': sharpness,
        'exposure': exposure,
        'gamma': gamma,
      };
}

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.cropJson,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String cropJson;
}

class ImageProcessingService {
  const ImageProcessingService(this._detector);

  final DocumentDetector _detector;

  Future<ProcessedImage> processDocument({
    required File source,
    ScanFilter filter = ScanFilter.auto,
    ProcessingSettings settings = const ProcessingSettings(),
    List<CropPoint>? cropPoints,
    int rotation = 0,
    int jpgQuality = 92,
  }) async {
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw const FormatException('Unsupported image format');
    }

    final suggestion = cropPoints == null ? await _detector.detect(source) : null;
    final points = cropPoints ?? suggestion!.points;
    var output = _warpCrop(decoded, points);
    if (rotation != 0) {
      output = img.copyRotate(output, angle: rotation);
    }
    output = _applyFilter(output, filter);
    output = img.adjustColor(
      output,
      brightness: settings.brightness,
      contrast: settings.contrast,
      saturation: settings.saturation,
      exposure: settings.exposure,
      gamma: settings.gamma,
    );
    if (settings.sharpness > 0) {
      output = img.sobel(output, amount: settings.sharpness.clamp(0.0, 1.0));
      output = img.adjustColor(output, contrast: 1.1);
    }

    return ProcessedImage(
      width: output.width,
      height: output.height,
      cropJson: jsonEncode(points.map((point) => point.toJson()).toList()),
      bytes: Uint8List.fromList(img.encodeJpg(output, quality: jpgQuality)),
    );
  }

  Future<Uint8List> exportPng(File source) async {
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw const FormatException('Unsupported image format');
    }
    return Uint8List.fromList(img.encodePng(decoded));
  }

  img.Image _applyFilter(img.Image source, ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return img.Image.from(source);
      case ScanFilter.auto:
        return img.adjustColor(
          img.normalize(source, min: 0, max: 255),
          brightness: 1.04,
          contrast: 1.18,
          saturation: 1.05,
          gamma: 0.96,
        );
      case ScanFilter.blackWhite:
        return img.luminanceThreshold(img.grayscale(source), threshold: 0.58);
      case ScanFilter.grayscale:
        return img.adjustColor(img.grayscale(source), contrast: 1.12);
      case ScanFilter.magicColor:
        return img.adjustColor(
          img.normalize(source, min: 0, max: 255),
          brightness: 1.06,
          contrast: 1.28,
          saturation: 1.3,
          gamma: 0.92,
        );
      case ScanFilter.colorDocument:
        return img.adjustColor(source, brightness: 1.03, contrast: 1.18);
      case ScanFilter.highContrast:
        return img.adjustColor(img.normalize(source, min: 0, max: 255), contrast: 1.55);
      case ScanFilter.receipt:
        return img.luminanceThreshold(
          img.adjustColor(img.grayscale(source), contrast: 1.35),
          threshold: 0.64,
        );
      case ScanFilter.idCard:
        return img.adjustColor(source, contrast: 1.2, saturation: 0.92);
      case ScanFilter.photo:
        return img.adjustColor(source, brightness: 1.01, saturation: 1.08);
    }
  }

  img.Image _warpCrop(img.Image source, List<CropPoint> points) {
    final tl = _toPixel(points[0], source);
    final tr = _toPixel(points[1], source);
    final br = _toPixel(points[2], source);
    final bl = _toPixel(points[3], source);
    final width = math.max(_distance(tl, tr), _distance(bl, br)).round();
    final height = math.max(_distance(tl, bl), _distance(tr, br)).round();
    final output = img.Image(width: math.max(1, width), height: math.max(1, height));

    for (var y = 0; y < output.height; y++) {
      final v = output.height == 1 ? 0.0 : y / (output.height - 1);
      final left = _lerpPoint(tl, bl, v);
      final right = _lerpPoint(tr, br, v);
      for (var x = 0; x < output.width; x++) {
        final u = output.width == 1 ? 0.0 : x / (output.width - 1);
        final src = _lerpPoint(left, right, u);
        final sx = src.x.round().clamp(0, source.width - 1);
        final sy = src.y.round().clamp(0, source.height - 1);
        output.setPixel(x, y, source.getPixel(sx, sy));
      }
    }
    return output;
  }

  _PixelPoint _toPixel(CropPoint point, img.Image image) {
    return _PixelPoint(point.x * (image.width - 1), point.y * (image.height - 1));
  }

  double _distance(_PixelPoint a, _PixelPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  _PixelPoint _lerpPoint(_PixelPoint a, _PixelPoint b, double t) {
    return _PixelPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  }
}

class _PixelPoint {
  const _PixelPoint(this.x, this.y);

  final double x;
  final double y;
}
