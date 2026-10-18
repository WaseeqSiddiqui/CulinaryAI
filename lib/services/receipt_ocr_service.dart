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
  final double? baselineSlope;
  final double? baselineIntercept;
  final int? sourceLineId;

  const ReceiptOcrLine({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.angle,
    this.baselineSlope,
    this.baselineIntercept,
    this.sourceLineId,
  });

  double get height => math.max(1, bottom - top);
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  double baselineYAt(double x) {
    final slope = baselineSlope;
    final intercept = baselineIntercept;
    if (slope == null || intercept == null) return centerY;
    return bottom + intercept + (slope * (x - left));
  }
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
    final hocrLines = parseHocrLines(output.hocr);

    if (hocrLines.isNotEmpty) {
      final reconstructedText = hocrLines.map((line) => line.text).join('\n');
      return ReceiptOcrResult(
        rawText: output.text.trim().isEmpty ? reconstructedText : output.text,
        structuredLines: hocrLines,
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
  static List<ReceiptOcrLine> parseHocrLines(String hocr) {
    final lineElements = _spanElementsWithClass(hocr, 'ocr_line');
    final lineFragments = <ReceiptOcrLine>[];

    for (var lineIndex = 0; lineIndex < lineElements.length; lineIndex++) {
      final element = lineElements[lineIndex];
      final baseline = _baseline(element.openingTag);
      final angle = baseline == null
          ? null
          : math.atan(baseline.slope) * 180 / math.pi;
      final words = <ReceiptOcrLine>[];
      for (final word in _spanElementsWithClass(element.body, 'ocrx_word')) {
        final parsed = _parseWord(word, angle: angle, sourceLineId: lineIndex);
        if (parsed != null) words.add(parsed);
      }
      if (words.isEmpty) continue;

      words.sort((left, right) => left.left.compareTo(right.left));
      final declaredBox = _hocrBox(element.openingTag);
      final confidences = words
          .map((word) => word.confidence)
          .whereType<double>()
          .toList();
      lineFragments.add(
        ReceiptOcrLine(
          text: words.map((word) => word.text).join(' '),
          confidence: confidences.isEmpty
              ? null
              : confidences.reduce((sum, value) => sum + value) /
                    confidences.length,
          left:
              declaredBox?.left ??
              words.map((word) => word.left).reduce(math.min),
          top:
              declaredBox?.top ??
              words.map((word) => word.top).reduce(math.min),
          right:
              declaredBox?.right ??
              words.map((word) => word.right).reduce(math.max),
          bottom:
              declaredBox?.bottom ??
              words.map((word) => word.bottom).reduce(math.max),
          angle: angle,
          baselineSlope: baseline?.slope,
          baselineIntercept: baseline?.intercept,
          sourceLineId: lineIndex,
        ),
      );
    }

    if (lineFragments.isNotEmpty) {
      return _reconcileHocrLineFragments(lineFragments);
    }

    final words = parseHocrWords(hocr);
    return words.isEmpty ? const [] : reconstructRows(words);
  }

  @visibleForTesting
  static List<ReceiptOcrLine> parseHocrWords(String hocr) {
    final words = <ReceiptOcrLine>[];
    final lineElements = _spanElementsWithClass(hocr, 'ocr_line');

    for (var lineIndex = 0; lineIndex < lineElements.length; lineIndex++) {
      final line = lineElements[lineIndex];
      final angle = _baselineAngle(line.openingTag);
      for (final word in _spanElementsWithClass(line.body, 'ocrx_word')) {
        final parsed = _parseWord(word, angle: angle, sourceLineId: lineIndex);
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

  static ReceiptOcrLine? _parseWord(
    _HocrElement element, {
    double? angle,
    int? sourceLineId,
  }) {
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
      sourceLineId: sourceLineId,
    );
  }

  static List<ReceiptOcrLine> _reconcileHocrLineFragments(
    List<ReceiptOcrLine> fragments,
  ) {
    final sorted = [...fragments]
      ..sort((left, right) {
        final vertical = left
            .baselineYAt(left.centerX)
            .compareTo(right.baselineYAt(right.centerX));
        return vertical == 0 ? left.left.compareTo(right.left) : vertical;
      });
    final rows = <_HocrRow>[];

    for (final fragment in sorted) {
      _HocrRow? bestRow;
      var bestBaselineDistance = double.infinity;
      for (final row in rows) {
        if (row.maxHorizontalOverlapRatio(fragment) > 0.15) continue;

        final comparisonX = row.comparisonX(fragment);
        final baselineDistance =
            (row.baselineYAt(comparisonX) - fragment.baselineYAt(comparisonX))
                .abs();
        final alignmentThreshold = math.max(
          2.0,
          math.min(row.medianHeight, fragment.height) * 0.35,
        );
        final spreadThreshold = math.max(3.0, row.medianHeight * 0.45);
        final aligned =
            baselineDistance <= alignmentThreshold &&
            row.maxBaselineSpreadWith(fragment, comparisonX) <= spreadThreshold;
        if (aligned && baselineDistance < bestBaselineDistance) {
          bestBaselineDistance = baselineDistance;
          bestRow = row;
        }
      }

      if (bestRow == null) {
        rows.add(_HocrRow(fragment));
      } else {
        bestRow.add(fragment);
      }
    }

    rows.sort((left, right) => left.sortY.compareTo(right.sortY));
    return rows.map((row) => row.toLine()).toList();
  }

  static _HocrBox? _hocrBox(String openingTag) {
    final title = _attribute(openingTag, 'title') ?? '';
    final box = RegExp(
      r'\bbbox\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    if (box == null) return null;
    return _HocrBox(
      left: double.parse(box.group(1)!),
      top: double.parse(box.group(2)!),
      right: double.parse(box.group(3)!),
      bottom: double.parse(box.group(4)!),
    );
  }

  static ({double slope, double intercept})? _baseline(String openingTag) {
    final title = _attribute(openingTag, 'title') ?? '';
    final baseline = RegExp(
      r'\bbaseline\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(title);
    final slope = double.tryParse(baseline?.group(1) ?? '');
    final intercept = double.tryParse(baseline?.group(2) ?? '');
    if (slope == null || intercept == null) return null;
    if (!slope.isFinite || !intercept.isFinite) return null;
    return (slope: slope, intercept: intercept);
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
        final fragmentHeight = fragment.height;
        final fragmentCenter = _adjustedCenterY(fragment, deskewSlope);
        final centerDistance = (row.adjustedCenterY - fragmentCenter).abs();
        final samePrintedRow =
            row.maxHorizontalOverlapRatio(fragment) <= 0.2 &&
            centerDistance <=
                math.max(
                  2.0,
                  math.min(row.adjustedHeight, fragmentHeight) * 0.5,
                ) &&
            row.maxAdjustedCenterSpreadWith(fragment) <=
                math.max(3.0, row.adjustedHeight * 0.65);
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

    rows.sort(
      (left, right) => left.adjustedCenterY.compareTo(right.adjustedCenterY),
    );
    return rows.map((row) => row.toLine()).toList();
  }

  static double _adjustedCenterY(ReceiptOcrLine line, double slope) =>
      line.centerY - (slope * line.centerX);

  static double _deskewSlope(List<ReceiptOcrLine> fragments) {
    final oneAnglePerSourceLine = <int, double>{};
    final ungroupedAngles = <double>[];
    for (final fragment in fragments) {
      final angle = fragment.angle;
      if (angle == null || !angle.isFinite || angle.abs() > 15) continue;
      final sourceLineId = fragment.sourceLineId;
      if (sourceLineId == null) {
        ungroupedAngles.add(angle);
      } else {
        oneAnglePerSourceLine.putIfAbsent(sourceLineId, () => angle);
      }
    }
    final angles = [...oneAnglePerSourceLine.values, ...ungroupedAngles]
      ..sort();
    if (angles.isEmpty) return 0;
    final middle = angles.length ~/ 2;
    final medianAngle = angles.length.isOdd
        ? angles[middle]
        : (angles[middle - 1] + angles[middle]) / 2;
    return math.tan(medianAngle * math.pi / 180);
  }

  static double? _baselineAngle(String openingTag) {
    final baseline = _baseline(openingTag);
    if (baseline == null) return null;
    return math.atan(baseline.slope) * 180 / math.pi;
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

class _HocrBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const _HocrBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}

class _HocrRow {
  final List<ReceiptOcrLine> fragments = [];

  _HocrRow(ReceiptOcrLine first) {
    fragments.add(first);
  }

  double get left => fragments.map((line) => line.left).reduce(math.min);
  double get right => fragments.map((line) => line.right).reduce(math.max);
  double get medianHeight =>
      _median(fragments.map((line) => line.height).toList());
  double get sortY =>
      _median(fragments.map((line) => line.baselineYAt(line.centerX)).toList());

  double maxHorizontalOverlapRatio(ReceiptOcrLine candidate) {
    var maximum = 0.0;
    for (final fragment in fragments) {
      final overlap = math.max(
        0.0,
        math.min(fragment.right, candidate.right) -
            math.max(fragment.left, candidate.left),
      );
      final narrowerWidth = math.max(
        1.0,
        math.min(
          fragment.right - fragment.left,
          candidate.right - candidate.left,
        ),
      );
      maximum = math.max(maximum, overlap / narrowerWidth);
    }
    return maximum;
  }

  double comparisonX(ReceiptOcrLine candidate) {
    if (candidate.right <= left) return (candidate.right + left) / 2;
    if (candidate.left >= right) return (right + candidate.left) / 2;
    return (candidate.centerX + ((left + right) / 2)) / 2;
  }

  double baselineYAt(double x) =>
      _median(fragments.map((line) => line.baselineYAt(x)).toList());

  double maxBaselineSpreadWith(ReceiptOcrLine candidate, double x) {
    final baselines = [
      ...fragments.map((line) => line.baselineYAt(x)),
      candidate.baselineYAt(x),
    ];
    return baselines.reduce(math.max) - baselines.reduce(math.min);
  }

  void add(ReceiptOcrLine fragment) => fragments.add(fragment);

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
    final sourceLineIds = fragments
        .map((fragment) => fragment.sourceLineId)
        .whereType<int>()
        .toSet();
    final onlyFragment = fragments.length == 1 ? fragments.single : null;

    return ReceiptOcrLine(
      text: fragments.map((fragment) => fragment.text).join(' '),
      confidence: confidences.isEmpty ? null : _median(confidences),
      left: fragments.map((fragment) => fragment.left).reduce(math.min),
      top: fragments.map((fragment) => fragment.top).reduce(math.min),
      right: fragments.map((fragment) => fragment.right).reduce(math.max),
      bottom: fragments.map((fragment) => fragment.bottom).reduce(math.max),
      angle: angles.isEmpty ? null : _median(angles),
      baselineSlope: onlyFragment?.baselineSlope,
      baselineIntercept: onlyFragment?.baselineIntercept,
      sourceLineId: sourceLineIds.length == 1 ? sourceLineIds.single : null,
    );
  }
}

class _ReceiptRow {
  final List<ReceiptOcrLine> fragments = [];
  final double deskewSlope;
  double top;
  double bottom;

  _ReceiptRow(ReceiptOcrLine first, this.deskewSlope)
    : top = first.top,
      bottom = first.bottom {
    fragments.add(first);
  }

  double get adjustedHeight =>
      _median(fragments.map((fragment) => fragment.height).toList());
  double get adjustedCenterY => _median(
    fragments
        .map((fragment) => fragment.centerY - (deskewSlope * fragment.centerX))
        .toList(),
  );

  double maxHorizontalOverlapRatio(ReceiptOcrLine candidate) {
    var maximum = 0.0;
    for (final fragment in fragments) {
      final overlap = math.max(
        0.0,
        math.min(fragment.right, candidate.right) -
            math.max(fragment.left, candidate.left),
      );
      final narrowerWidth = math.max(
        1.0,
        math.min(
          fragment.right - fragment.left,
          candidate.right - candidate.left,
        ),
      );
      maximum = math.max(maximum, overlap / narrowerWidth);
    }
    return maximum;
  }

  double maxAdjustedCenterSpreadWith(ReceiptOcrLine candidate) {
    final centers = [
      ...fragments.map(
        (fragment) => fragment.centerY - (deskewSlope * fragment.centerX),
      ),
      candidate.centerY - (deskewSlope * candidate.centerX),
    ];
    return centers.reduce(math.max) - centers.reduce(math.min);
  }

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
    final angles = fragments
        .map((fragment) => fragment.angle)
        .whereType<double>()
        .toList();
    final sourceLineIds = fragments
        .map((fragment) => fragment.sourceLineId)
        .whereType<int>()
        .toSet();
    return ReceiptOcrLine(
      text: fragments.map((fragment) => fragment.text).join(' '),
      confidence: confidences.isEmpty ? null : _median(confidences),
      left: fragments.map((fragment) => fragment.left).reduce(math.min),
      top: top,
      right: fragments.map((fragment) => fragment.right).reduce(math.max),
      bottom: bottom,
      angle: angles.isEmpty ? null : _median(angles),
      sourceLineId: sourceLineIds.length == 1 ? sourceLineIds.single : null,
    );
  }
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
