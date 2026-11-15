import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final entry in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    test('${entry.key} theme keeps controls and body text readable', () {
      final theme = entry.value;
      final scheme = theme.colorScheme;
      final pairs = <String, (Color, Color)>{
        'primary action': (scheme.onPrimary, scheme.primary),
        'secondary action': (scheme.onSecondary, scheme.secondary),
        'error action': (scheme.onError, scheme.error),
        'body': (scheme.onSurface, scheme.surface),
        'secondary text': (scheme.onSurfaceVariant, scheme.surface),
        'selected control': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'input label': (
          theme.inputDecorationTheme.labelStyle!.color!,
          theme.inputDecorationTheme.fillColor!,
        ),
        'snackbar': (
          theme.snackBarTheme.contentTextStyle!.color!,
          theme.snackBarTheme.backgroundColor!,
        ),
      };
      for (final pair in pairs.entries) {
        expect(
          contrast(pair.value.$1, pair.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${pair.key} needs readable text contrast',
        );
      }
    });
  }
}
