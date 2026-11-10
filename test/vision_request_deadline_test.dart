import 'dart:async';
import 'dart:ui' as ui;

import 'package:culinary_ai/services/vision_api_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _HangingResponseClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body.stream, 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final receipt in [true, false]) {
    test(
      '${receipt ? 'receipt' : 'fridge'} deadline also covers a stalled response body',
      () async {
        final client = _HangingResponseClient();
        final service = VisionApiService(
          client: client,
          timeout: const Duration(milliseconds: 30),
        );
        final request = receipt
            ? service.parseReceipt(
                imageBytes: Uint8List.fromList([1, 2, 3]),
                userId: 'test',
              )
            : service.scanFridge(
                imageBytes: Uint8List.fromList([1, 2, 3]),
                userId: 'test',
                existingItems: [],
              );
        await expectLater(
          request,
          throwsA(
            isA<VisionApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              504,
            ),
          ),
        );
        await client.body.close();
      },
    );
  }

  test('large camera images are decoded at the bounded upload size', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xff2d654f), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final source = await picture.toImage(3000, 1500);
    final bytes = await source.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    picture.dispose();
    final scaled = await VisionApiService.downscaleImage(
      bytes!.buffer.asUint8List(),
      maxDimension: 1600,
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(scaled);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, 1600);
    expect(descriptor.height, 800);
    descriptor.dispose();
    buffer.dispose();
  });
}
