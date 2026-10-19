import 'package:flutter/material.dart';

/// Semantic color tokens crafted with a warm, organic farm-tech palette.
///
/// Designed to evoke natural sustainable agriculture:
/// - Deep forest emeralds & fresh meadow greens
/// - Warm linen & oatmeal parchment surfaces
/// - Golden sunlit amber for solar & morning feed
/// - Warm espresso & lichen typography with human warmth
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color brand;
  final Color onBrand;
  final Color brandSoft;
  final Color brandSurface;
  final Color brandBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color surface;
  final Color surfaceMuted;
  final Color track;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerSoft;
  final Color dangerBorder;
  final Color info;
  final Color infoStrong;
  final Color infoSoft;
  final Color infoBorder;
  final Color manual;
  final Color manualSoft;
  final Color solar;
  final Color skeletonBase;
  final Color skeletonHighlight;

  const AppColors({
    required this.brand,
    required this.onBrand,
    required this.brandSoft,
    required this.brandSurface,
    required this.brandBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.surface,
    required this.surfaceMuted,
    required this.track,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.dangerBorder,
    required this.info,
    required this.infoStrong,
    required this.infoSoft,
    required this.infoBorder,
    required this.manual,
    required this.manualSoft,
    required this.solar,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  /// Handcrafted warm organic light palette (Sunlit Farmhouse / Meadow)
  static const light = AppColors(
    brand: Color(0xFF1E4D2B), // Deep artisan forest emerald
    onBrand: Colors.white,
    brandSoft: Color(0xFFE5EFE7), // Soft botanical sage
    brandSurface: Color(0xFFF2F7F3), // Gentle organic meadow wash
    brandBorder: Color(0xFFBEDBC3), // Soft leaf border
    textPrimary: Color(0xFF181C19), // Rich warm espresso obsidian
    textSecondary: Color(0xFF454E46), // Warm cedar bark
    textMuted: Color(0xFF6F7B72), // Soft lichen stone
    border: Color(0xFFE3DED4), // Natural warm linen border
    surface: Colors.white,
    surfaceMuted: Color(0xFFF3EFE7), // Warm toasted oat
    track: Color(0xFFEAE5DC), // Gentle warm track
    success: Color(0xFF15803D), // Fresh clover leaf
    warning: Color(0xFFB45309), // Warm golden wheat
    danger: Color(0xFFB91C1C), // Warm terracotta crimson
    dangerSoft: Color(0xFFFDF2F0),
    dangerBorder: Color(0xFFF8C8C1),
    info: Color(0xFF2563EB), // Clear morning sky
    infoStrong: Color(0xFF1D4ED8),
    infoSoft: Color(0xFFEFF6FF),
    infoBorder: Color(0xFFBFDBFE),
    manual: Color(0xFFD97706), // Warm golden honey
    manualSoft: Color(0xFFFEF3C7), // Buttermilk cream
    solar: Color(0xFFD97706), // Sunlit amber
    skeletonBase: Color(0xFFE7E2D7),
    skeletonHighlight: Color(0xFFF5F2EB),
  );

  /// Handcrafted warm nocturnal dark palette (Night Farm / Peat Obsidian)
  static const dark = AppColors(
    brand: Color(0xFF4ADE80), // Luminous spring sprout green
    onBrand: Color(0xFF04260F), // Deep forest text
    brandSoft: Color(0xFF143820), // Deep moss container
    brandSurface: Color(0xFF0F2B18), // Nocturnal foliage wash
    brandBorder: Color(0xFF225732),
    textPrimary: Color(0xFFF4F6F4), // Warm ivory parchment
    textSecondary: Color(0xFFB8C2BA), // Pale warm sage
    textMuted: Color(0xFF7E8A81), // Muted lichen
    border: Color(0xFF2B332E), // Warm peat border
    surface: Color(0xFF1A1F1D), // Warm peat stone
    surfaceMuted: Color(0xFF212824), // Deeper peat stone
    track: Color(0xFF2A332E),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF381616),
    dangerBorder: Color(0xFF6B2222),
    info: Color(0xFF60A5FA),
    infoStrong: Color(0xFFBFDBFE),
    infoSoft: Color(0xFF14243B),
    infoBorder: Color(0xFF1E3A8A),
    manual: Color(0xFFFBBF24),
    manualSoft: Color(0xFF39290C),
    solar: Color(0xFFFBBF24),
    skeletonBase: Color(0xFF1F2622),
    skeletonHighlight: Color(0xFF2A332E),
  );

  /// Subtle layered shadow for tactile card depth
  List<BoxShadow> get warmShadow => [
        BoxShadow(
          color: const Color(0x0C2B2010),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
        const BoxShadow(
          color: Color(0x05000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ];

  @override
  AppColors copyWith({Color? brand, Color? onBrand}) {
    return AppColors(
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      brandSoft: brandSoft,
      brandSurface: brandSurface,
      brandBorder: brandBorder,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      border: border,
      surface: surface,
      surfaceMuted: surfaceMuted,
      track: track,
      success: success,
      warning: warning,
      danger: danger,
      dangerSoft: dangerSoft,
      dangerBorder: dangerBorder,
      info: info,
      infoStrong: infoStrong,
      infoSoft: infoSoft,
      infoBorder: infoBorder,
      manual: manual,
      manualSoft: manualSoft,
      solar: solar,
      skeletonBase: skeletonBase,
      skeletonHighlight: skeletonHighlight,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      brandSoft: l(brandSoft, other.brandSoft),
      brandSurface: l(brandSurface, other.brandSurface),
      brandBorder: l(brandBorder, other.brandBorder),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      border: l(border, other.border),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      track: l(track, other.track),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      dangerBorder: l(dangerBorder, other.dangerBorder),
      info: l(info, other.info),
      infoStrong: l(infoStrong, other.infoStrong),
      infoSoft: l(infoSoft, other.infoSoft),
      infoBorder: l(infoBorder, other.infoBorder),
      manual: l(manual, other.manual),
      manualSoft: l(manualSoft, other.manualSoft),
      solar: l(solar, other.solar),
      skeletonBase: l(skeletonBase, other.skeletonBase),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Shorthand for the active [AppColors] palette (light or dark).
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
        Brightness.light,
        AppColors.light,
        const Color(0xFFF7F5F0), // Warm unbleached organic linen
      );

  static ThemeData dark() => _build(
        Brightness.dark,
        AppColors.dark,
        const Color(0xFF111413), // Deep peat obsidian
      );

  static ThemeData _build(Brightness brightness, AppColors c, Color scaffold) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E4D2B), // Forest emerald seed
      brightness: brightness,
    ).copyWith(
      primary: c.brand,
      onPrimary: c.onBrand,
      surface: c.surface,
      error: c.danger,
    );

    final isLight = brightness == Brightness.light;
    final cardRadius = BorderRadius.circular(18);
    final buttonRadius = BorderRadius.circular(14);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold, // Seamless header transition
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.border.withValues(alpha: 0.6)),
        ),
        elevation: 6,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? const Color(0xFF1E2420) : const Color(0xFF262F2A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFFAF8F5) : c.surfaceMuted,
        border: OutlineInputBorder(borderRadius: buttonRadius, borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: buttonRadius, borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: buttonRadius, borderSide: BorderSide(color: c.brand, width: 1.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1.0,
        shadowColor: isLight ? const Color(0x0C352410) : Colors.black54,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(
            color: c.border.withValues(alpha: isLight ? 0.75 : 0.4),
            width: 1.0,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.border.withValues(alpha: 0.7),
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: isLight ? const Color(0x12000000) : Colors.black87,
        height: 68,
        indicatorColor: c.brandSoft,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? c.brand : c.textMuted,
            letterSpacing: 0.1,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brandSoft,
        indicatorShape: const StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          elevation: 1.5,
          shadowColor: c.brand.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: buttonRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.brand,
          side: BorderSide(color: c.border, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: buttonRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.brand,
        inactiveTrackColor: c.track,
        thumbColor: c.brand,
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayColor: c.brand.withValues(alpha: 0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onBrand : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : null,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
