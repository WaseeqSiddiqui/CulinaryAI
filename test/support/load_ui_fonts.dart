import 'package:flutter/services.dart';

Future<void> loadUiFonts() async {
  final inter = FontLoader('Inter');
  for (final style in ['Regular', 'Medium', 'SemiBold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$style.ttf'));
  }
  await inter.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
