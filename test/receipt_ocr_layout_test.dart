import 'package:culinary_ai/services/receipt_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Tesseract hOCR words with geometry and confidence', () {
    const hocr = '''
      <div class='ocr_page' id='page_1'>
        <span class='ocr_line' id='line_1_1'
              title="bbox 20 100 450 140; baseline 0.02 -3">
          <span class='ocrx_word' id='word_1_1'
                title='bbox 20 100 150 122; x_wconf 94'>KTC</span>
          <span class='ocrx_word' id='word_1_2'
                title='bbox 165 103 270 125; x_wconf 88'>CHICK&amp;PEAS</span>
          <span class='ocrx_word' id='word_1_3'
                title='bbox 390 108 450 130; x_wconf 97'>&pound;4.75</span>
        </span>
      </div>
    ''';

    final words = ReceiptOcrService.parseHocrWords(hocr);

    expect(words.map((word) => word.text), ['KTC', 'CHICK&PEAS', '£4.75']);
    expect(words.first.confidence, 0.94);
    expect(words.first.left, 20);
    expect(words.first.angle, closeTo(1.1458, 0.001));
  });

  test(
    'recognizes a receipt through an injected Tesseract hOCR engine',
    () async {
      const hocr = '''
      <span class='ocr_line' title='bbox 20 100 330 125; baseline 0 0'>
        <span class='ocrx_word' title='bbox 20 100 100 120; x_wconf 95'>BREAD</span>
        <span class='ocrx_word' title='bbox 270 101 330 121; x_wconf 93'>220.00</span>
      </span>
    ''';
      final service = ReceiptOcrService(
        extractor: (_) async =>
            const ReceiptOcrEngineOutput(hocr: hocr, text: 'BREAD 220.00'),
      );

      final result = await service.recognize('receipt.jpg');

      expect(result.engine, 'Tesseract OCR');
      expect(result.lines, ['BREAD 220.00']);
      expect(result.rawText, 'BREAD 220.00');
    },
  );

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

  test('deskews slanted receipt columns before reconstructing rows', () {
    const angle = 6.45;
    const fragments = [
      ReceiptOcrLine(
        text: 'KTC CHICK PEAS CASE',
        confidence: 0.94,
        left: 20,
        top: 100,
        right: 160,
        bottom: 120,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: '12x400G',
        confidence: 0.93,
        left: 210,
        top: 118,
        right: 290,
        bottom: 138,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: '1',
        confidence: 0.97,
        left: 320,
        top: 128,
        right: 335,
        bottom: 148,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: '4.75',
        confidence: 0.95,
        left: 400,
        top: 138,
        right: 450,
        bottom: 158,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: 'ONION INDIAN',
        confidence: 0.92,
        left: 20,
        top: 137,
        right: 170,
        bottom: 157,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: 'BAG',
        confidence: 0.94,
        left: 210,
        top: 155,
        right: 255,
        bottom: 175,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: '1',
        confidence: 0.98,
        left: 320,
        top: 165,
        right: 335,
        bottom: 185,
        angle: angle,
      ),
      ReceiptOcrLine(
        text: '2.99',
        confidence: 0.96,
        left: 400,
        top: 175,
        right: 450,
        bottom: 195,
        angle: angle,
      ),
    ];

    final rows = ReceiptOcrService.reconstructRows(fragments);

    expect(rows.map((row) => row.text), [
      'KTC CHICK PEAS CASE 12x400G 1 4.75',
      'ONION INDIAN BAG 1 2.99',
    ]);
  });
}
