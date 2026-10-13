import 'package:culinary_ai/services/receipt_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconstructs receipt rows from separately detected columns', () {
    const fragments = [
      ReceiptOcrLine(
        text: 'MILK 1L',
        confidence: 0.92,
        left: 20,
        top: 100,
        right: 130,
        bottom: 120,
      ),
      ReceiptOcrLine(
        text: '2',
        confidence: 0.96,
        left: 180,
        top: 101,
        right: 195,
        bottom: 121,
      ),
      ReceiptOcrLine(
        text: '620.00',
        confidence: 0.94,
        left: 270,
        top: 99,
        right: 330,
        bottom: 120,
      ),
      ReceiptOcrLine(
        text: 'BREAD',
        confidence: 0.9,
        left: 20,
        top: 130,
        right: 100,
        bottom: 150,
      ),
      ReceiptOcrLine(
        text: '220.00',
        confidence: 0.91,
        left: 270,
        top: 131,
        right: 330,
        bottom: 151,
      ),
    ];

    final rows = ReceiptOcrService.reconstructRows(fragments);

    expect(rows.map((row) => row.text), ['MILK 1L 2 620.00', 'BREAD 220.00']);
    expect(rows.first.confidence, closeTo(0.94, 0.001));
  });

  test('does not merge vertically adjacent printed rows', () {
    const fragments = [
      ReceiptOcrLine(
        text: 'MILK',
        confidence: null,
        left: 10,
        top: 10,
        right: 80,
        bottom: 25,
      ),
      ReceiptOcrLine(
        text: 'BREAD',
        confidence: null,
        left: 10,
        top: 28,
        right: 80,
        bottom: 43,
      ),
    ];

    final rows = ReceiptOcrService.reconstructRows(fragments);

    expect(rows, hasLength(2));
  });
}
