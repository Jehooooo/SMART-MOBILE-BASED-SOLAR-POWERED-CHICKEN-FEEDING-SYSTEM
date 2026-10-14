import 'package:flutter/material.dart';

/// Semantic color tokens used across every screen.
///
/// Screens must read colors from `context.colors` instead of hardcoding hex
/// values, so that Light and Dark mode stay consistent (Nielsen #4:
/// Consistency & Standards).
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

  static const light = AppColors(
    brand: Color(0xFF0F766E),
    onBrand: Colors.white,
    brandSoft: Color(0xFFCCFBF1),
    brandSurface: Color(0xFFF0FDFA),
    brandBorder: Color(0xFF99F6E4),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    border: Color(0xFFE2E8F0),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF8FAFC),
    track: Color(0xFFF1F5F9),
    success: Color(0xFF059669),
    warning: Color(0xFFB45309),
    danger: Color(0xFFB91C1C),
    dangerSoft: Color(0xFFFEF2F2),
    dangerBorder: Color(0xFFFECACA),
    info: Color(0xFF2563EB),
    infoStrong: Color(0xFF1E40AF),
    infoSoft: Color(0xFFEFF6FF),
    infoBorder: Color(0xFF93C5FD),
    manual: Color(0xFFD97706),
    manualSoft: Color(0xFFFEF3C7),
    solar: Color(0xFFB45309),
    skeletonBase: Color(0xFFE2E8F0),
    skeletonHighlight: Color(0xFFF8FAFC),
  );

  static const dark = AppColors(
    brand: Color(0xFF2DD4BF),
    onBrand: Color(0xFF042F2E),
    brandSoft: Color(0xFF134E4A),
    brandSurface: Color(0xFF0D2624),
    brandBorder: Color(0xFF1F5F59),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    border: Color(0xFF2A3647),
    surface: Color(0xFF151E2D),
    surfaceMuted: Color(0xFF0F1724),
    track: Color(0xFF243044),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3A1618),
    dangerBorder: Color(0xFF7F1D1D),
    info: Color(0xFF60A5FA),
    infoStrong: Color(0xFFBFDBFE),
    infoSoft: Color(0xFF13213D),
    infoBorder: Color(0xFF1E3A8A),
    manual: Color(0xFFFBBF24),
    manualSoft: Color(0xFF3B2A0A),
    solar: Color(0xFFFBBF24),
    skeletonBase: Color(0xFF1E293B),
    skeletonHighlight: Color(0xFF2B3A52),
  );

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

  static ThemeData light() => _build(Brightness.light, AppColors.light, const Color(0xFFF8FAFC));

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark, const Color(0xFF0B1120));

  static ThemeData _build(Brightness brightness, AppColors c, Color scaffold) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E), // Natural agricultural teal
      brightness: brightness,
    ).copyWith(
      primary: c.brand,
      onPrimary: c.onBrand,
      surface: c.surface,
      error: c.danger,
    );

    final radius10 = BorderRadius.circular(10);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(borderRadius: radius10, borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: radius10, borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: radius10, borderSide: BorderSide(color: c.brand, width: 1.8)),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.brandSoft,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brandSoft,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onBrand : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : null),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
