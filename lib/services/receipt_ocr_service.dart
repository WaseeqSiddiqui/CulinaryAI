import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptOcrResult {
  final String rawText;
  final List<String> lines;

  const ReceiptOcrResult({required this.rawText, required this.lines});
}

class ReceiptOcrService {
  ReceiptOcrService({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<ReceiptOcrResult> recognize(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(image);
    final lines = <String>[
      for (final block in recognized.blocks)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty) line.text.trim(),
    ];
    return ReceiptOcrResult(rawText: recognized.text, lines: lines);
  }

  Future<void> close() => _recognizer.close();
}
