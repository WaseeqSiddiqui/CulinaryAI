import 'package:flutter/material.dart';

/// Shared colors, typography and controls for every CulinaryAI screen.
class AppTheme {
  static const primaryFlame = Color(0xFFA63625);
  static const primaryFlameLight = Color(0xFFFFE0D3);
  static const primaryFlameDark = Color(0xFF762418);
  static const freshHerb = Color(0xFF2D624D);
  static const freshHerbLight = Color(0xFFDCECE0);
  static const freshHerbDark = Color(0xFF234C3C);
  static const warmSaffron = Color(0xFF8B5117);
  static const warmSaffronLight = Color(0xFFFFEBC9);
  static const errorRed = Color(0xFFB42334);
  static const successGreen = freshHerb;
  static const primaryEmerald = primaryFlame;
  static const primaryLight = primaryFlameLight;
  static const primaryDark = primaryFlameDark;
  static const terracottaAccent = primaryFlame;
  static const copperLight = primaryFlameLight;
  static const warmAmber = warmSaffron;
  static const zoneFridge = Color(0xFF356B68);
  static const zoneFreezer = Color(0xFF426A81);
  static const zonePantry = freshHerb;
  static const zoneSpice = warmSaffron;
  static const creamWarm = Color(0xFFFFF7EC);
  static const creamBeige = Color(0xFFF8E9D9);
  static const creamSurface = Color(0xFFF9EDE0);
  static const creamBorder = Color(0xFFE9D5C4);
  static const creamAccent = Color(0xFFF9DDCF);
  static const bgLight = creamWarm;
  static const surfaceLight = Color(0xFFFFFCF7);
  static const surfaceLight2 = creamSurface;
  static const cardLight = surfaceLight;
  static const borderLight = creamBorder;
  static const borderLightSubtle = Color(0xFFF3E6D9);
  static const textLightPrimary = Color(0xFF35251F);
  static const textLightSecondary = Color(0xFF6C5548);
  static const textLightMuted = Color(0xFF735C4F);
  static const bgDark = Color(0xFF141518);
  static const surfaceDark = Color(0xFF1E2025);
  static const cardDark = surfaceDark;
  static const surfaceDark2 = Color(0xFF292C32);
  static const surfaceDark3 = Color(0xFF33363D);
  static const borderDark = Color(0xFF41454D);
  static const borderDarkSubtle = Color(0xFF2D3036);
  static const textDarkPrimary = Color(0xFFF6F7FA);
  static const textDarkSecondary = Color(0xFFBEC1CB);
  static const textDarkMuted = Color(0xFF9DA2AD);
  static const textPrimary = textLightPrimary;
  static const textSecondary = textLightSecondary;
  static const primaryGradient = LinearGradient(
    colors: [primaryFlame, primaryFlameDark],
  );
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF5D3425), Color(0xFF301A14)],
  );
  static const heroDarkGradient = LinearGradient(
    colors: [Color(0xFF65402F), Color(0xFF32201A)],
  );
  static const herbGradient = primaryGradient;

  static ThemeData get lightTheme => _build(false);

  static ThemeData _build(bool dark) {
    final ink = dark ? textDarkPrimary : textLightPrimary;
    final muted = dark ? textDarkSecondary : textLightSecondary;
    final border = dark ? borderDark : borderLight;
    final surface = dark ? surfaceDark : surfaceLight;
    final background = dark ? bgDark : bgLight;
    final accent = dark ? primaryFlameLight : primaryFlame;
    final barBackground = dark ? primaryFlameDark : primaryFlame;
    final navBackground = dark ? surfaceDark : surfaceLight;
    final navSelected = dark ? primaryFlameLight : primaryFlameDark;
    final navIndicator = dark ? primaryFlameDark : creamAccent;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final typography = base.textTheme.apply(
      fontFamily: 'Inter',
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
          secondary: dark ? freshHerbLight : freshHerb,
          onSecondary: dark ? bgDark : Colors.white,
          secondaryContainer: dark ? surfaceDark3 : freshHerbLight,
          onSecondaryContainer: ink,
          tertiary: dark ? warmSaffronLight : warmSaffron,
          onTertiary: dark ? bgDark : Colors.white,
          tertiaryContainer: dark ? surfaceDark3 : warmSaffronLight,
          onTertiaryContainer: ink,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainerHighest: dark ? surfaceDark2 : creamSurface,
          primaryContainer: dark ? surfaceDark3 : creamAccent,
          onPrimaryContainer: ink,
          outline: border,
          outlineVariant: border,
          error: dark ? const Color(0xFFFFB4BF) : errorRed,
          onError: dark ? bgDark : Colors.white,
        );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: typography.copyWith(
        displaySmall: typography.displaySmall?.copyWith(
          fontSize: 38,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.1,
          height: 1.16,
        ),
        headlineLarge: typography.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
          height: 1.2,
        ),
        headlineMedium: typography.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -.7,
          height: 1.22,
        ),
        headlineSmall: typography.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -.45,
          height: 1.25,
        ),
        titleLarge: typography.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -.35,
        ),
        titleMedium: typography.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -.2,
        ),
        bodyLarge: typography.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
        bodyMedium: typography.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
        bodySmall: typography.bodySmall?.copyWith(
          fontSize: 13,
          height: 1.5,
          color: muted,
        ),
        labelLarge: typography.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: barBackground,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: 24,
        titleTextStyle: typography.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w500,
          letterSpacing: -.35,
          color: Colors.white,
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
            fontWeight: FontWeight.w500,
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
            fontWeight: FontWeight.w500,
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
            fontWeight: FontWeight.w500,
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
        fillColor: dark ? surfaceDark2 : surfaceLight,
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
        backgroundColor: navBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: navIndicator,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return navSelected.withValues(alpha: .12);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return navSelected.withValues(alpha: .07);
          }
          return null;
        }),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => typography.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? navSelected : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? navSelected : muted,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
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
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: .2),
        selectionHandleColor: accent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: typography.bodyMedium,
        shape: shape,
      ),
    );
  }
}
