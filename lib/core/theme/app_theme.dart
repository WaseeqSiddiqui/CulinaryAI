import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CulinaryAI Design System: "Warm Hearth & Fresh Herb"
/// Inspired by award-winning culinary apps (NYT Cooking, Kitchen Stories, Quisine AI)
/// and food psychology principles (warmth, appetite stimulation, zero cold-blue dark modes).
class AppTheme {
  // ── Brand Primary Palette (Appetite-Stimulating Warm Flame / Saffron) ──────
  static const Color primaryFlame       = Color(0xFFFF5A36); // Gourmet Saffron Vermillion
  static const Color primaryFlameLight  = Color(0xFFFF7E61);
  static const Color primaryFlameDark   = Color(0xFFD9401F);
  
  // ── Secondary Fresh Palette (Farm-Fresh Organic & Pantry Freshness) ────────
  static const Color freshHerb          = Color(0xFF10B981); // Crisp Garden Basil / Sage
  static const Color freshHerbLight     = Color(0xFF34D399);
  static const Color freshHerbDark      = Color(0xFF059669);

  // ── Warm Saffron & Amber (Spices, Alerts & Highlights) ─────────────────────
  static const Color warmSaffron        = Color(0xFFF59E0B);
  static const Color warmSaffronLight   = Color(0xFFFCD34D);

  // ── Semantic Status ────────────────────────────────────────────────────────
  static const Color errorRed           = Color(0xFFEF4444);
  static const Color successGreen       = Color(0xFF10B981);

  // ── Aliases for backward compatibility ─────────────────────────────────────
  static const Color primaryEmerald     = primaryFlame;
  static const Color primaryLight       = primaryFlameLight;
  static const Color primaryDark        = primaryFlameDark;
  static const Color terracottaAccent   = primaryFlame;
  static const Color warmAmber          = warmSaffron;

  // ── Zone Palette (Curated Gourmet Color Coding) ───────────────────────────
  static const Color zoneFridge         = Color(0xFF0284C7); // Chilled Ice Blue
  static const Color zoneFreezer        = Color(0xFF818CF8); // Frost Indigo Violet
  static const Color zonePantry         = Color(0xFFF59E0B); // Harvest Wheat Amber
  static const Color zoneSpice          = Color(0xFFF43F5E); // Cayenne / Paprika Rose

  // ── Warm Beige & Culinary Cream Palette ────────────────────────────────────
  static const Color creamWarm         = Color(0xFFFBF8F3); // Warm culinary rich cream
  static const Color creamBeige        = Color(0xFFF3ECE0); // Soft artisan linen / biscuit beige
  static const Color creamSurface      = Color(0xFFFAF5ED); // Cream card container
  static const Color creamBorder       = Color(0xFFEADBCE); // Subtle warm beige border
  static const Color creamAccent       = Color(0xFFF7EFE3); // Cream chip / pill background

  // ── Light Surfaces (Warm Porcelain, Cream & Linen Beige) ───────────────────
  static const Color bgLight            = Color(0xFFFAF6F0); // Warm culinary cream linen
  static const Color surfaceLight       = Color(0xFFFFFFFF); // Pure crisp white
  static const Color surfaceLight2      = Color(0xFFFAF5ED); // Elevated warm cream
  static const Color cardLight          = creamSurface;      // Warm artisan cream card
  static const Color borderLight        = Color(0xFFEADBCE); // Warm beige border
  static const Color borderLightSubtle  = Color(0xFFF4ECE1);
  static const Color textLightPrimary   = Color(0xFF111827); // Deep charcoal
  static const Color textLightSecondary = Color(0xFF4B5563); // Warm slate
  static const Color textLightMuted     = Color(0xFF9CA3AF);

  // ── Dark Surfaces (Warm Obsidian & Truffle Slate — NO COLD BLUE!) ──────────
  static const Color bgDark             = Color(0xFF0F1012); // Deep obsidian slate
  static const Color surfaceDark        = Color(0xFF17181D); // Rich charcoal card
  static const Color cardDark           = surfaceDark;       // Rich charcoal card
  static const Color surfaceDark2       = Color(0xFF202229); // Elevated card & inputs
  static const Color surfaceDark3       = Color(0xFF282B34); // Active highlight
  static const Color borderDark         = Color(0xFF292C35); // Delicate dark micro-border
  static const Color borderDarkSubtle   = Color(0xFF1E2027);
  static const Color textDarkPrimary    = Color(0xFFF9FAFB); // Soft bright white
  static const Color textDarkSecondary  = Color(0xFF9CA3AF); // Warm muted slate
  static const Color textDarkMuted      = Color(0xFF6B7280);

  // Common Aliases
  static const Color textPrimary        = textLightPrimary;
  static const Color textSecondary      = textLightSecondary;

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryFlame, Color(0xFFE0451F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFFF5A36), Color(0xFFC73614)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroDarkGradient = LinearGradient(
    colors: [Color(0xFF241C1A), Color(0xFF171312)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient herbGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF047857)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Typography ─────────────────────────────────────────────────────────────
  static String get _font => GoogleFonts.plusJakartaSans().fontFamily!;

  // ── LIGHT THEME ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: _font,
      scaffoldBackgroundColor: bgLight,
      primaryColor: primaryFlame,
      colorScheme: const ColorScheme.light(
        primary: primaryFlame,
        primaryContainer: Color(0xFFFFECE5),
        secondary: freshHerb,
        secondaryContainer: Color(0xFFECFDF5),
        tertiary: warmSaffron,
        surface: surfaceLight,
        error: errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textLightPrimary,
        outline: borderLight,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textLightPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: textLightPrimary),
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryFlame,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(
            fontFamily: _font,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryFlame,
          side: const BorderSide(color: primaryFlame, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(
            fontFamily: _font,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryFlame,
          textStyle: TextStyle(
            fontFamily: _font,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryFlame, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: errorRed, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textLightMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textLightSecondary),
        prefixIconColor: textLightSecondary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight2,
        selectedColor: primaryFlame.withValues(alpha: 0.12),
        labelStyle: TextStyle(
          fontFamily: _font,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textLightPrimary,
        ),
        side: const BorderSide(color: borderLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceLight,
        indicatorColor: primaryFlame.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: _font,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryFlame : textLightSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? primaryFlame : textLightSecondary,
            size: 22,
          );
        }),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryFlame,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textLightPrimary,
        contentTextStyle: TextStyle(fontFamily: _font, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        color: borderLight,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: Color(0xFFCBD5E1),
        dragHandleSize: Size(40, 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textLightPrimary,
        ),
      ),
    );
  }

  // ── DARK THEME ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _font,
      scaffoldBackgroundColor: bgDark,
      primaryColor: primaryFlame,
      colorScheme: const ColorScheme.dark(
        primary: primaryFlame,
        primaryContainer: Color(0xFF351B15),
        secondary: freshHerb,
        secondaryContainer: Color(0xFF142E25),
        tertiary: warmSaffron,
        surface: surfaceDark,
        error: Color(0xFFF87171),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDarkPrimary,
        outline: borderDark,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textDarkPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: textDarkPrimary),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderDark, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryFlame,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(
            fontFamily: _font,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryFlameLight,
          side: const BorderSide(color: primaryFlame, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryFlameLight,
          textStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryFlame, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5),
        ),
        hintStyle: const TextStyle(color: textDarkMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textDarkSecondary),
        prefixIconColor: textDarkSecondary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceDark2,
        selectedColor: primaryFlame.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontFamily: _font,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textDarkPrimary,
        ),
        side: const BorderSide(color: borderDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceDark,
        indicatorColor: primaryFlame.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: _font,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryFlameLight : textDarkSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? primaryFlameLight : textDarkSecondary,
            size: 22,
          );
        }),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryFlame,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceDark2,
        contentTextStyle: TextStyle(fontFamily: _font, color: textDarkPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: borderDark, thickness: 1, space: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: Color(0xFF3F4452),
        dragHandleSize: Size(40, 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textDarkPrimary,
        ),
      ),
    );
  }
}
