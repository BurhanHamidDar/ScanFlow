import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrExtraction {
  const OcrExtraction({
    required this.text,
    required this.script,
    required this.confidence,
  });

  final String text;
  final String script;
  final double? confidence;
}

class OcrService {
  Future<OcrExtraction> extractText(
    File imageFile, {
    TextRecognitionScript script = TextRecognitionScript.latin,
  }) async {
    if (kIsWeb) {
      return OcrExtraction(
        text: "OCR extraction is not available in the web version.",
        script: script.name,
        confidence: 1.0,
      );
    }

    final recognizer = TextRecognizer(script: script);
    try {
      final image = InputImage.fromFilePath(imageFile.path);
      final result = await recognizer.processImage(image);
      final confidences = result.blocks
          .expand((block) => block.lines)
          .map((line) => line.confidence)
          .whereType<double>()
          .toList();
      final confidence = confidences.isEmpty
          ? null
          : confidences.reduce((a, b) => a + b) / confidences.length;
      return OcrExtraction(
        text: result.text.trim(),
        script: script.name,
        confidence: confidence,
      );
    } finally {
      await recognizer.close();
    }
  }
}
