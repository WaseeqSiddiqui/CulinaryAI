import 'package:flutter/material.dart';

/// Shared colors, typography and controls for every CulinaryAI screen.
class AppTheme {
  static const primaryFlame = Color(0xFF2D654F);
  static const primaryFlameLight = Color(0xFF82AF95);
  static const primaryFlameDark = Color(0xFF1C4434);
  static const freshHerb = Color(0xFF548268);
  static const freshHerbLight = Color(0xFFA5C6AB);
  static const freshHerbDark = Color(0xFF31543D);
  static const warmSaffron = Color(0xFFA47A32);
  static const warmSaffronLight = Color(0xFFECD9AF);
  static const errorRed = Color(0xFFBA5146);
  static const successGreen = freshHerb;
  static const primaryEmerald = primaryFlame;
  static const primaryLight = primaryFlameLight;
  static const primaryDark = primaryFlameDark;
  static const terracottaAccent = Color(0xFFB66D50);
  static const warmAmber = warmSaffron;
  static const zoneFridge = Color(0xFF5D8290);
  static const zoneFreezer = Color(0xFF7B7D9E);
  static const zonePantry = Color(0xFFA47A32);
  static const zoneSpice = Color(0xFFB66D50);
  static const creamWarm = Color(0xFFFAFAF6);
  static const creamBeige = Color(0xFFEDEEE5);
  static const creamSurface = Color(0xFFF3F4ED);
  static const creamBorder = Color(0xFFE3E7DE);
  static const creamAccent = Color(0xFFEBF1E8);
  static const bgLight = creamWarm;
  static const surfaceLight = Colors.white;
  static const surfaceLight2 = creamSurface;
  static const cardLight = surfaceLight;
  static const borderLight = creamBorder;
  static const borderLightSubtle = Color(0xFFF0F1EB);
  static const textLightPrimary = Color(0xFF22332A);
  static const textLightSecondary = Color(0xFF68766C);
  static const textLightMuted = Color(0xFF78847B);
  static const bgDark = Color(0xFF131C17);
  static const surfaceDark = Color(0xFF1B2720);
  static const cardDark = surfaceDark;
  static const surfaceDark2 = Color(0xFF25332A);
  static const surfaceDark3 = Color(0xFF304135);
  static const borderDark = Color(0xFF36443A);
  static const borderDarkSubtle = Color(0xFF26332B);
  static const textDarkPrimary = Color(0xFFF0F3EB);
  static const textDarkSecondary = Color(0xFFB2BFB2);
  static const textDarkMuted = Color(0xFF94A695);
  static const textPrimary = textLightPrimary;
  static const textSecondary = textLightSecondary;
  static const primaryGradient = LinearGradient(
    colors: [primaryFlame, primaryFlameDark],
  );
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF2C5743), Color(0xFF1F3C30)],
  );
  static const heroDarkGradient = LinearGradient(
    colors: [Color(0xFF2C4635), Color(0xFF22372A)],
  );
  static const herbGradient = primaryGradient;

  static ThemeData get lightTheme => _build(false);
  static ThemeData get darkTheme => _build(true);

  static ThemeData _build(bool dark) {
    final ink = dark ? textDarkPrimary : textLightPrimary;
    final muted = dark ? textDarkSecondary : textLightSecondary;
    final border = dark ? borderDark : borderLight;
    final surface = dark ? surfaceDark : surfaceLight;
    final background = dark ? bgDark : bgLight;
    final accent = dark ? const Color(0xFFA7C9AC) : primaryFlame;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'PlusJakartaSans',
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final typography = base.textTheme.apply(
      fontFamily: 'PlusJakartaSans',
      bodyColor: ink,
      displayColor: ink,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primaryFlame,
          brightness: base.brightness,
        ).copyWith(
          primary: accent,
          onPrimary: dark ? bgDark : Colors.white,
          secondary: dark ? primaryFlameLight : freshHerb,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainerHighest: dark ? surfaceDark2 : creamSurface,
          primaryContainer: dark ? surfaceDark3 : creamAccent,
          onPrimaryContainer: ink,
          outline: border,
          outlineVariant: border,
          error: dark ? const Color(0xFFE9A095) : errorRed,
        );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: typography.copyWith(
        displaySmall: typography.displaySmall?.copyWith(
          fontSize: 38,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.5,
          height: 1.16,
        ),
        headlineLarge: typography.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.1,
          height: 1.2,
        ),
        headlineMedium: typography.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -.9,
          height: 1.22,
        ),
        titleLarge: typography.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
        titleMedium: typography.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -.2,
        ),
        bodyLarge: typography.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
        bodyMedium: typography.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
        bodySmall: typography.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.5,
          color: muted,
        ),
        labelLarge: typography.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: 24,
        titleTextStyle: typography.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: shape,
          textStyle: typography.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: shape,
          textStyle: typography.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: border),
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: typography.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? surfaceDark2 : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        hintStyle: typography.bodyMedium?.copyWith(color: muted),
        labelStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: typography.labelMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => typography.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryFlame,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        iconColor: muted,
        titleTextStyle: typography.titleSmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: typography.bodySmall?.copyWith(color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        modalBarrierColor: Colors.black.withValues(alpha: .35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? creamBeige : textLightPrimary,
        contentTextStyle: typography.bodyMedium?.copyWith(
          color: dark ? textLightPrimary : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        strokeWidth: 2,
      ),
    );
  }
}
