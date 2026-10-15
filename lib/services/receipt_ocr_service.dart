import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef ReceiptOcrExtractor = Future<ReceiptOcrEngineOutput> Function(
  String imagePath,
);

class ReceiptOcrEngineOutput {
  final String hocr;
  final String text;

  const ReceiptOcrEngineOutput({required this.hocr, required this.text});
}

class ReceiptOcrLine {
  final String text;
  final double? confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? angle;

  const ReceiptOcrLine({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.angle,
  });

  double get height => math.max(1, bottom - top);
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

class ReceiptOcrResult {
  final String rawText;
  final List<ReceiptOcrLine> structuredLines;
  final String engine;

  const ReceiptOcrResult({
    required this.rawText,
    required this.structuredLines,
    this.engine = 'Tesseract OCR',
  });

  List<String> get lines => structuredLines.map((line) => line.text).toList();

  String get diagnosticText =>
      'OCR engine: $engine\n\n'
      'Reconstructed receipt rows:\n${lines.join('\n')}\n\n'
      'Raw OCR output:\n$rawText';
}

class ReceiptOcrService {
  ReceiptOcrService({ReceiptOcrExtractor? extractor})
    : _extractor = extractor ?? _recognizeWithTesseract;

  static const _tesseractChannel = MethodChannel('culinary_ai/tesseract');

  final ReceiptOcrExtractor _extractor;

  Future<ReceiptOcrResult> recognize(String imagePath) async {
    final output = await _extractor(imagePath);
    final words = parseHocrWords(output.hocr);

    if (words.isNotEmpty) {
      final rows = reconstructRows(words);
      final reconstructedText = rows.map((line) => line.text).join('\n');
      return ReceiptOcrResult(
        rawText: output.text.trim().isEmpty ? reconstructedText : output.text,
        structuredLines: rows,
      );
    }

    final rows = _plainTextLines(output.text);
    return ReceiptOcrResult(rawText: output.text, structuredLines: rows);
  }

  static Future<ReceiptOcrEngineOutput> _recognizeWithTesseract(
    String imagePath,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Tesseract receipt scanning is currently supported on Android.',
      );
    }
    final result = await _tesseractChannel.invokeMapMethod<String, dynamic>(
      'recognize',
      {'imagePath': imagePath},
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_ocr_response',
        message: 'Tesseract returned no response.',
      );
    }
    return ReceiptOcrEngineOutput(
      hocr: result['hocr'] as String? ?? '',
      text: result['text'] as String? ?? '',
    );
  }

  @visibleForTesting
  static List<ReceiptOcrLine> parseHocrWords(String hocr) {
    final words = <ReceiptOcrLine>[];
    final lineElements = _spanElementsWithClass(hocr, 'ocr_line');

    for (final line in lineElements) {
      final angle = _baselineAngle(line.openingTag);
      for (final word in _spanElementsWithClass(line.body, 'ocrx_word')) {
        final parsed = _parseWord(word, angle: angle);
        if (parsed != null) words.add(parsed);
      }
    }

    if (words.isNotEmpty) return words;

    for (final word in _spanElementsWithClass(hocr, 'ocrx_word')) {
      final parsed = _parseWord(word);
      if (parsed != null) words.add(parsed);
    }
    return words;
  }

  static ReceiptOcrLine? _parseWord(_HocrElement element, {double? angle}) {
    final title = _attribute(element.openingTag, 'title') ?? '';
    final box = RegExp(
      r'\bbbox\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    if (box == null) return null;

    final text = _decodeHtml(element.body.replaceAll(RegExp(r'<[^>]+>'), ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;

    final confidenceMatch = RegExp(
      r'\bx_wconf\s+(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(title);
    final confidencePercent = double.tryParse(confidenceMatch?.group(1) ?? '');

    return ReceiptOcrLine(
      text: text,
      confidence: confidencePercent == null
          ? null
          : (confidencePercent.clamp(0, 100) / 100).toDouble(),
      left: double.parse(box.group(1)!),
      top: double.parse(box.group(2)!),
      right: double.parse(box.group(3)!),
      bottom: double.parse(box.group(4)!),
      angle: angle,
    );
  }

  static List<ReceiptOcrLine> _plainTextLines(String text) {
    var row = 0;
    return [
      for (final rawLine in text.split(RegExp(r'\r?\n')))
        if (rawLine.trim().isNotEmpty)
          ReceiptOcrLine(
            text: rawLine.replaceAll(RegExp(r'\s+'), ' ').trim(),
            confidence: null,
            left: 0,
            top: (row++ * 24).toDouble(),
            right: math.max(1, rawLine.length * 8).toDouble(),
            bottom: (row * 24).toDouble(),
          ),
    ];
  }

  @visibleForTesting
  static List<ReceiptOcrLine> reconstructRows(List<ReceiptOcrLine> fragments) {
    if (fragments.isEmpty) return const [];
    final deskewSlope = _deskewSlope(fragments);
    final sorted = [...fragments]
      ..sort((left, right) {
        final vertical = _adjustedCenterY(
          left,
          deskewSlope,
        ).compareTo(_adjustedCenterY(right, deskewSlope));
        return vertical == 0 ? left.left.compareTo(right.left) : vertical;
      });
    final rows = <_ReceiptRow>[];

    for (final fragment in sorted) {
      _ReceiptRow? bestRow;
      var bestDistance = double.infinity;
      for (final row in rows) {
        final fragmentTop = _adjustedTop(fragment, deskewSlope);
        final fragmentBottom = _adjustedBottom(fragment, deskewSlope);
        final fragmentHeight = math.max(1, fragmentBottom - fragmentTop);
        final overlap = math.max(
          0,
          math.min(row.adjustedBottom, fragmentBottom) -
              math.max(row.adjustedTop, fragmentTop),
        );
        final overlapRatio =
            overlap / math.min(row.adjustedHeight, fragmentHeight);
        final fragmentCenter = _adjustedCenterY(fragment, deskewSlope);
        final centerDistance = (row.adjustedCenterY - fragmentCenter).abs();
        final samePrintedRow =
            overlapRatio >= 0.3 ||
            centerDistance <=
                math.min(row.adjustedHeight, fragmentHeight) * 0.55;
        if (samePrintedRow && centerDistance < bestDistance) {
          bestDistance = centerDistance;
          bestRow = row;
        }
      }
      if (bestRow == null) {
        rows.add(_ReceiptRow(fragment, deskewSlope));
      } else {
        bestRow.add(fragment);
      }
    }

    rows.sort((left, right) => left.adjustedTop.compareTo(right.adjustedTop));
    return rows.map((row) => row.toLine()).toList();
  }

  static double _adjustedTop(ReceiptOcrLine line, double slope) =>
      line.top - (slope * line.centerX);

  static double _adjustedBottom(ReceiptOcrLine line, double slope) =>
      line.bottom - (slope * line.centerX);

  static double _adjustedCenterY(ReceiptOcrLine line, double slope) =>
      line.centerY - (slope * line.centerX);

  static double _deskewSlope(List<ReceiptOcrLine> fragments) {
    final angles =
        fragments
            .map((fragment) => fragment.angle)
            .whereType<double>()
            .where((angle) => angle.isFinite && angle.abs() <= 15)
            .toList()
          ..sort();
    if (angles.isEmpty) return 0;
    final middle = angles.length ~/ 2;
    final medianAngle = angles.length.isOdd
        ? angles[middle]
        : (angles[middle - 1] + angles[middle]) / 2;
    return math.tan(medianAngle * math.pi / 180);
  }

  static double? _baselineAngle(String openingTag) {
    final title = _attribute(openingTag, 'title') ?? '';
    final baseline = RegExp(
      r'\bbaseline\s+(-?\d+(?:\.\d+)?)\s+-?\d+(?:\.\d+)?',
      caseSensitive: false,
    ).firstMatch(title);
    final slope = double.tryParse(baseline?.group(1) ?? '');
    if (slope == null || !slope.isFinite) return null;
    return math.atan(slope) * 180 / math.pi;
  }

  static List<_HocrElement> _spanElementsWithClass(
    String source,
    String className,
  ) {
    final elements = <_HocrElement>[];
    final openingPattern = RegExp(r'<span\b[^>]*>', caseSensitive: false);
    final tokenPattern = RegExp(
      r'<span\b[^>]*>|</span\s*>',
      caseSensitive: false,
    );

    for (final opening in openingPattern.allMatches(source)) {
      final openingTag = opening.group(0)!;
      final classes = (_attribute(openingTag, 'class') ?? '').split(
        RegExp(r'\s+'),
      );
      if (!classes.contains(className)) continue;

      var depth = 1;
      for (final token in tokenPattern.allMatches(source, opening.end)) {
        final value = token.group(0)!.toLowerCase();
        if (value.startsWith('</span')) {
          depth--;
        } else {
          depth++;
        }
        if (depth != 0) continue;
        elements.add(
          _HocrElement(
            openingTag: openingTag,
            body: source.substring(opening.end, token.start),
          ),
        );
        break;
      }
    }
    return elements;
  }

  static String? _attribute(String openingTag, String name) {
    final doubleQuoted = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(openingTag);
    if (doubleQuoted != null) return doubleQuoted.group(1);
    return RegExp(
      "$name\\s*=\\s*'([^']*)'",
      caseSensitive: false,
    ).firstMatch(openingTag)?.group(1);
  }

  static String _decodeHtml(String value) {
    var decoded = value.replaceAllMapped(
      RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
      (match) {
        final code = int.tryParse(match.group(1)!, radix: 16);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      },
    );
    decoded = decoded.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1)!);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    });
    const entities = <String, String>{
      '&pound;': '£',
      '&euro;': '€',
      '&times;': '×',
      '&nbsp;': ' ',
      '&quot;': '"',
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&amp;': '&',
    };
    for (final entry in entities.entries) {
      decoded = decoded.replaceAll(entry.key, entry.value);
    }
    return decoded;
  }

  Future<void> close() async {}
}

class _HocrElement {
  final String openingTag;
  final String body;

  const _HocrElement({required this.openingTag, required this.body});
}

class _ReceiptRow {
  final List<ReceiptOcrLine> fragments = [];
  final double deskewSlope;
  double top;
  double bottom;
  double adjustedTop;
  double adjustedBottom;

  _ReceiptRow(ReceiptOcrLine first, this.deskewSlope)
    : top = first.top,
      bottom = first.bottom,
      adjustedTop = first.top - (deskewSlope * first.centerX),
      adjustedBottom = first.bottom - (deskewSlope * first.centerX) {
    fragments.add(first);
  }

  double get adjustedHeight => math.max(1, adjustedBottom - adjustedTop);
  double get adjustedCenterY => (adjustedTop + adjustedBottom) / 2;

  void add(ReceiptOcrLine fragment) {
    fragments.add(fragment);
    top = math.min(top, fragment.top);
    bottom = math.max(bottom, fragment.bottom);
    adjustedTop = math.min(
      adjustedTop,
      fragment.top - (deskewSlope * fragment.centerX),
    );
    adjustedBottom = math.max(
      adjustedBottom,
      fragment.bottom - (deskewSlope * fragment.centerX),
    );
  }

  ReceiptOcrLine toLine() {
    fragments.sort((left, right) => left.left.compareTo(right.left));
    final confidences = fragments
        .map((fragment) => fragment.confidence)
        .whereType<double>()
        .toList();
    final angles = fragments
        .map((fragment) => fragment.angle)
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
      angle: angles.isEmpty
          ? null
          : angles.reduce((left, right) => left + right) / angles.length,
    );
  }
}
