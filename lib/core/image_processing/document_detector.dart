import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class CropPoint {
  const CropPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, double> toJson() => {'x': x, 'y': y};

  static CropPoint fromJson(Map<String, dynamic> json) {
    return CropPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }
}

class CropSuggestion {
  const CropSuggestion({
    required this.points,
    required this.confidence,
    required this.width,
    required this.height,
  });

  final List<CropPoint> points;
  final double confidence;
  final int width;
  final int height;
}

class DocumentDetector {
  Future<CropSuggestion> detect(File file) async {
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) {
      throw const FormatException('Unsupported image format');
    }

    final scale = decoded.width > 720 ? 720 / decoded.width : 1.0;
    final small = scale < 1
        ? img.copyResize(decoded, width: (decoded.width * scale).round())
        : img.Image.from(decoded);
    final gray = img.grayscale(small);
    final edges = img.sobel(gray);

    final threshold = _edgeThreshold(edges);
    var minX = edges.width;
    var minY = edges.height;
    var maxX = 0;
    var maxY = 0;
    var hits = 0;

    for (var y = 0; y < edges.height; y++) {
      for (var x = 0; x < edges.width; x++) {
        final lum = edges.getPixel(x, y).luminance;
        if (lum >= threshold) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
          hits++;
        }
      }
    }

    if (hits < 200 || maxX <= minX || maxY <= minY) {
      return _defaultSuggestion(decoded.width, decoded.height);
    }

    final padX = edges.width * 0.025;
    final padY = edges.height * 0.025;
    final left = ((minX - padX).clamp(0, edges.width - 1)) / edges.width;
    final top = ((minY - padY).clamp(0, edges.height - 1)) / edges.height;
    final right = ((maxX + padX).clamp(0, edges.width - 1)) / edges.width;
    final bottom = ((maxY + padY).clamp(0, edges.height - 1)) / edges.height;

    final coverage = ((right - left) * (bottom - top)).clamp(0.0, 1.0);
    final confidence = (hits / (edges.width * edges.height) * 12)
        .clamp(0.15, 0.95)
        .toDouble();

    if (coverage < 0.18) {
      return _defaultSuggestion(decoded.width, decoded.height);
    }

    return CropSuggestion(
      width: decoded.width,
      height: decoded.height,
      confidence: confidence,
      points: [
        CropPoint(left, top),
        CropPoint(right, top),
        CropPoint(right, bottom),
        CropPoint(left, bottom),
      ],
    );
  }

  int _edgeThreshold(img.Image edges) {
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < edges.height; y += 4) {
      for (var x = 0; x < edges.width; x += 4) {
        sum += edges.getPixel(x, y).luminance;
        count++;
      }
    }
    return math.max(48, (sum / math.max(1, count) * 1.7).round());
  }

  CropSuggestion _defaultSuggestion(int width, int height) {
    return CropSuggestion(
      width: width,
      height: height,
      confidence: 0.25,
      points: const [
        CropPoint(0.06, 0.06),
        CropPoint(0.94, 0.06),
        CropPoint(0.94, 0.94),
        CropPoint(0.06, 0.94),
      ],
    );
  }
}
