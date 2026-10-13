import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptOcrLine {
  final String text;
  final double? confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const ReceiptOcrLine({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get height => math.max(1, bottom - top);
  double get centerY => (top + bottom) / 2;
}

class ReceiptOcrResult {
  final String rawText;
  final List<ReceiptOcrLine> structuredLines;

  const ReceiptOcrResult({
    required this.rawText,
    required this.structuredLines,
  });

  List<String> get lines => structuredLines.map((line) => line.text).toList();

  String get diagnosticText =>
      'Reconstructed receipt rows:\n${lines.join('\n')}\n\n'
      'Raw OCR output:\n$rawText';
}

class ReceiptOcrService {
  ReceiptOcrService({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<ReceiptOcrResult> recognize(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(image);
    final fragments = <ReceiptOcrLine>[
      for (final block in recognized.blocks)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty)
            ReceiptOcrLine(
              text: line.text.trim(),
              confidence: line.confidence,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
    ];
    final rows = reconstructRows(fragments);
    return ReceiptOcrResult(rawText: recognized.text, structuredLines: rows);
  }

  @visibleForTesting
  static List<ReceiptOcrLine> reconstructRows(List<ReceiptOcrLine> fragments) {
    if (fragments.isEmpty) return const [];
    final sorted = [...fragments]
      ..sort((left, right) {
        final vertical = left.centerY.compareTo(right.centerY);
        return vertical == 0 ? left.left.compareTo(right.left) : vertical;
      });
    final rows = <_ReceiptRow>[];

    for (final fragment in sorted) {
      _ReceiptRow? bestRow;
      var bestDistance = double.infinity;
      for (final row in rows) {
        final overlap = math.max(
          0,
          math.min(row.bottom, fragment.bottom) -
              math.max(row.top, fragment.top),
        );
        final overlapRatio = overlap / math.min(row.height, fragment.height);
        final centerDistance = (row.centerY - fragment.centerY).abs();
        final samePrintedRow =
            overlapRatio >= 0.3 ||
            centerDistance <= math.min(row.height, fragment.height) * 0.55;
        if (samePrintedRow && centerDistance < bestDistance) {
          bestDistance = centerDistance;
          bestRow = row;
        }
      }
      if (bestRow == null) {
        rows.add(_ReceiptRow(fragment));
      } else {
        bestRow.add(fragment);
      }
    }

    rows.sort((left, right) => left.top.compareTo(right.top));
    return rows.map((row) => row.toLine()).toList();
  }

  Future<void> close() => _recognizer.close();
}

class _ReceiptRow {
  final List<ReceiptOcrLine> fragments = [];
  double top;
  double bottom;

  _ReceiptRow(ReceiptOcrLine first) : top = first.top, bottom = first.bottom {
    fragments.add(first);
  }

  double get height => math.max(1, bottom - top);
  double get centerY => (top + bottom) / 2;

  void add(ReceiptOcrLine fragment) {
    fragments.add(fragment);
    top = math.min(top, fragment.top);
    bottom = math.max(bottom, fragment.bottom);
  }

  ReceiptOcrLine toLine() {
    fragments.sort((left, right) => left.left.compareTo(right.left));
    final confidences = fragments
        .map((fragment) => fragment.confidence)
        .whereType<double>()
        .toList();
    return ReceiptOcrLine(
      text: fragments.map((fragment) => fragment.text).join(' '),
      confidence: confidences.isEmpty
          ? null
          : confidences.reduce((left, right) => left + right) /
                confidences.length,
      left: fragments.first.left,
      top: top,
      right: fragments.map((fragment) => fragment.right).reduce(math.max),
      bottom: bottom,
    );
  }
}
