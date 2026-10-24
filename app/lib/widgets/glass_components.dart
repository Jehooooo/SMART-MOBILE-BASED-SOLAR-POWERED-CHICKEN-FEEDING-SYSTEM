import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Atmospheric fluid background with subtle ambient color orbs.
///
/// Refracts through translucent Liquid Glass and Glassmorphism surfaces
/// to create Apple-inspired depth, illumination, and soft specular reflections.
class LiquidBackground extends StatelessWidget {
  final Widget child;

  const LiquidBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base canvas tone
        Container(
          color: isDark ? const Color(0xFF0F1411) : const Color(0xFFF7F6F2),
        ),

        // Ambient Organic Lighting Orbs (Liquid Mesh)
        Positioned(
          top: -80,
          right: -60,
          width: 320,
          height: 320,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (isDark ? c.brand : const Color(0xFF2E6F40)).withValues(alpha: isDark ? 0.16 : 0.10),
                  (isDark ? c.brand : const Color(0xFF2E6F40)).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -70,
          width: 300,
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (isDark ? c.solar : const Color(0xFFE5A93C)).withValues(alpha: isDark ? 0.12 : 0.08),
                  (isDark ? c.solar : const Color(0xFFE5A93C)).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 360,
          right: -40,
          width: 240,
          height: 240,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (isDark ? c.info : const Color(0xFF60A5FA)).withValues(alpha: isDark ? 0.09 : 0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Child content on top of atmospheric lighting
        child,
      ],
    );
  }
}

/// Core Liquid Glass & Glassmorphic Container.
///
/// Features:
/// - Real-time frosted backdrop blur via [BackdropFilter]
/// - Semi-transparent liquid gradient wash
/// - Specular highlight rim (light catching glass edges)
/// - Soft ambient floating shadow
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? tintColor;
  final double? tintOpacity;
  final Border? customBorder;
  final List<BoxShadow>? customShadow;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final VoidCallback? onTap;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blurSigma = 18.0,
    this.borderRadius,
    this.padding,
    this.margin,
    this.tintColor,
    this.tintOpacity,
    this.customBorder,
    this.customShadow,
    this.width,
    this.height,
    this.constraints,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = borderRadius ?? BorderRadius.circular(22);

    // Liquid surface gradient
    final baseTint = tintColor ?? (isDark ? const Color(0xFF1A221D) : Colors.white);
    final topOpacity = tintOpacity ?? (isDark ? 0.65 : 0.76);
    final bottomOpacity = (topOpacity * 0.72).clamp(0.0, 1.0);

    // Specular border reflection
    final effectiveBorder = customBorder ??
        Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        );

    final effectiveShadow = customShadow ??
        [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.42)
                : const Color(0x101B2E20),
            blurRadius: 22,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.20)
                : const Color(0x08000000),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ];

    Widget content = Container(
      width: width,
      height: height,
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseTint.withValues(alpha: topOpacity),
            baseTint.withValues(alpha: bottomOpacity),
          ],
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          splashColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
          highlightColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
          child: content,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        border: effectiveBorder,
        boxShadow: effectiveShadow,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      ),
    );
  }
}

/// Convenience card widget implementing Liquid Glassmorphism.
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Color? tintColor;
  final double blurSigma;
  final Border? customBorder;
  final Color? glowBorderColor;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18.0),
    this.margin,
    this.borderRadius,
    this.onTap,
    this.tintColor,
    this.blurSigma = 18.0,
    this.customBorder,
    this.glowBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassContainer(
      padding: padding,
      margin: margin,
      borderRadius: borderRadius ?? BorderRadius.circular(22),
      onTap: onTap,
      tintColor: tintColor,
      blurSigma: blurSigma,
      customBorder: customBorder ??
          (glowBorderColor != null
              ? Border.all(color: glowBorderColor!, width: 1.2)
              : null),
      child: child,
    );
  }
}

/// iOS-Inspired Floating Navigation Dock.
///
/// Sits elevated above page content with frosted backdrop blur, specular
/// highlights, smooth animated selection pill, and tactile icon items.
class IOSFloatingNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<({IconData icon, IconData selected, String label})> destinations;

  const IOSFloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;

    return Center(
      heightFactor: 1.0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: LiquidGlassContainer(
          borderRadius: BorderRadius.circular(34),
          blurSigma: 24.0,
          tintOpacity: isDark ? 0.70 : 0.82,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          customShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.50)
                  : const Color(0x1818291E),
              blurRadius: 30,
              offset: const Offset(0, 10),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.60),
              blurRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(destinations.length, (idx) {
              final d = destinations[idx];
              final isSelected = selectedIndex == idx;

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDestinationSelected(idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                              ? c.brand.withValues(alpha: 0.22)
                              : c.brand.withValues(alpha: 0.12))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      border: isSelected
                          ? Border.all(
                              color: isDark
                                  ? c.brand.withValues(alpha: 0.40)
                                  : c.brand.withValues(alpha: 0.30),
                              width: 1.0,
                            )
                          : Border.all(color: Colors.transparent),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.08 : 0.95,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutBack,
                          child: Icon(
                            isSelected ? d.selected : d.icon,
                            size: 22,
                            color: isSelected ? c.brand : c.textMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected ? c.brand : c.textMuted,
                            letterSpacing: 0.1,
                          ),
                          child: Text(
                            d.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Compact Floating Liquid Glass Dock for Desktop / Tablet side navigation.
class IOSFloatingSideDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<({IconData icon, IconData selected, String label})> destinations;
  final Widget? header;

  const IOSFloatingSideDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;

    return Container(
      width: 96,
      margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 14.0),
      child: LiquidGlassContainer(
        borderRadius: BorderRadius.circular(32),
        blurSigma: 24.0,
        tintOpacity: isDark ? 0.70 : 0.82,
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 8.0),
        child: Column(
          children: [
            if (header != null) ...[
              header!,
              const SizedBox(height: 24),
              Divider(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                height: 1,
              ),
              const SizedBox(height: 16),
            ],
            for (int idx = 0; idx < destinations.length; idx++) ...[
              Builder(
                builder: (context) {
                  final d = destinations[idx];
                  final isSelected = selectedIndex == idx;
                  final index = idx;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Tooltip(
                      message: d.label,
                      child: InkWell(
                        onTap: () => onDestinationSelected(index),
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 6.0),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark ? c.brand.withValues(alpha: 0.22) : c.brand.withValues(alpha: 0.12))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: isSelected
                                ? Border.all(
                                    color: isDark ? c.brand.withValues(alpha: 0.40) : c.brand.withValues(alpha: 0.30),
                                    width: 1.0,
                                  )
                                : Border.all(color: Colors.transparent),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? d.selected : d.icon,
                                size: 22,
                                color: isSelected ? c.brand : c.textMuted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                d.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                  color: isSelected ? c.brand : c.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Frosted liquid glass badge capsule.
class LiquidGlassBadge extends StatelessWidget {
  final Widget? icon;
  final String label;
  final Color color;
  final Color? textColor;
  final double fontSize;
  final VoidCallback? onTap;

  const LiquidGlassBadge({
    super.key,
    this.icon,
    required this.label,
    required this.color,
    this.textColor,
    this.fontSize = 11,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.40 : 0.35),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.16 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: textColor ?? color,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      badge = InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: badge,
      );
    }

    return badge;
  }
}

/// Liquid Glass modal sheet / dialog wrapper with frosted blur.
class LiquidGlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const LiquidGlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.child,
    this.maxWidth = 540,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveChild = child ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              title!,
              const SizedBox(height: 16),
            ],
            if (content != null) ...[
              content!,
              const SizedBox(height: 20),
            ],
            if (actions != null && actions!.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8.0,
                runSpacing: 8.0,
                children: actions!,
              ),
          ],
        );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LiquidGlassContainer(
          borderRadius: BorderRadius.circular(28),
          blurSigma: 26.0,
          padding: padding ?? const EdgeInsets.all(24.0),
          child: effectiveChild,
        ),
      ),
    );
  }
}
