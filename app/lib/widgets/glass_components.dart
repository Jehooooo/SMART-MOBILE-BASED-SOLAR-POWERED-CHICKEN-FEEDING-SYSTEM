import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

bool get _isTestEnvironment {
  if (kIsWeb) return false;
  return Platform.environment.containsKey('FLUTTER_TEST');
}

/// Atmospheric fluid background with dynamic, living ambient lighting orbs.
///
/// Refracts through translucent Liquid Glass and Glassmorphism surfaces
/// to create Apple-inspired depth, illumination, and soft specular reflections.
class LiquidBackground extends StatefulWidget {
  final Widget child;

  const LiquidBackground({super.key, required this.child});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    // Only start continuous looping animation outside of widget test harness
    // to prevent pumpAndSettle timeouts during automated test verification.
    if (!_isTestEnvironment) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_isTestEnvironment && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base canvas tone
        Container(
          color: isDark ? const Color(0xFF0C110E) : const Color(0xFFF6F5F0),
        ),

        // Animated Ambient Organic Lighting Orbs (Liquid Caustics Mesh)
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final offset1 = math.sin(t * math.pi * 2) * 22.0;
            final offset2 = math.cos(t * math.pi * 2) * 26.0;
            final scale1 = 1.0 + (math.sin(t * math.pi) * 0.10);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Emerald Liquid Orb (Top Right)
                Positioned(
                  top: -90 + offset1,
                  right: -70 - offset2,
                  width: 360 * scale1,
                  height: 360 * scale1,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (isDark ? c.brand : const Color(0xFF227B40))
                              .withValues(alpha: isDark ? 0.24 : 0.15),
                          (isDark ? c.brand : const Color(0xFF2E6F40))
                              .withValues(alpha: isDark ? 0.10 : 0.05),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),

                // Solar Honey Caustic Orb (Bottom Left)
                Positioned(
                  bottom: 100 - offset1,
                  left: -80 + offset2,
                  width: 340,
                  height: 340,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (isDark ? c.solar : const Color(0xFFF59E0B))
                              .withValues(alpha: isDark ? 0.18 : 0.12),
                          (isDark ? c.solar : const Color(0xFFE5A93C))
                              .withValues(alpha: isDark ? 0.06 : 0.03),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),

                // Clear Sky Liquid Highlight (Center Right)
                Positioned(
                  top: 320 + offset2,
                  right: -50 + offset1,
                  width: 280,
                  height: 280,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
                              .withValues(alpha: isDark ? 0.14 : 0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),

                // Soft Ambient Pool (Bottom Right)
                Positioned(
                  bottom: -60 + offset2,
                  right: 40 - offset1,
                  width: 260,
                  height: 260,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (isDark ? c.brand : const Color(0xFF10B981))
                              .withValues(alpha: isDark ? 0.12 : 0.07),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // Child content floating on top of atmospheric fluid lighting
        widget.child,
      ],
    );
  }
}

/// Core Liquid Glass & Glassmorphic Container.
///
/// Features:
/// - Real-time frosted backdrop blur via [BackdropFilter]
/// - Semi-transparent multi-stop liquid gradient wash
/// - Directional specular gradient border rim (light catching liquid edges)
/// - Meniscus light arc reflection across the top curve
/// - Deep floating ambient drop shadow with liquid caustics
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
  final bool showMeniscus;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blurSigma = 20.0,
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
    this.showMeniscus = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = borderRadius ?? BorderRadius.circular(24);

    // Liquid surface gradient tones
    final baseTint = tintColor ?? (isDark ? const Color(0xFF161E19) : Colors.white);
    final topOpacity = tintOpacity ?? (isDark ? 0.68 : 0.80);
    final midOpacity = (topOpacity * 0.85).clamp(0.0, 1.0);
    final bottomOpacity = (topOpacity * 0.68).clamp(0.0, 1.0);

    // Liquid specular border gradient
    final gradientBorderColorTop = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.95);
    final gradientBorderColorBottom = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.35);

    final effectiveShadow = customShadow ??
        [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.48)
                : const Color(0x121A2E20),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -1,
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.22)
                : const Color(0x0A000000),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
          stops: const [0.0, 0.4, 1.0],
          colors: [
            baseTint.withValues(alpha: topOpacity),
            baseTint.withValues(alpha: midOpacity),
            baseTint.withValues(alpha: bottomOpacity),
          ],
        ),
      ),
      child: child,
    );

    if (showMeniscus) {
      content = CustomPaint(
        foregroundPainter: _LiquidMeniscusPainter(
          borderRadius: r,
          isDark: isDark,
        ),
        child: content,
      );
    }

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          splashColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          highlightColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
          child: content,
        ),
      );
    }

    // Wrap in custom painted border or explicit border
    Widget glassSurface = ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      ),
    );

    if (customBorder != null) {
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: r,
          border: customBorder,
          boxShadow: effectiveShadow,
        ),
        child: glassSurface,
      );
    }

    // Default: Directional Liquid Specular Border (gleams on top/left, fades at bottom)
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: effectiveShadow,
      ),
      child: CustomPaint(
        foregroundPainter: _LiquidBorderPainter(
          strokeWidth: 1.2,
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 1.0],
            colors: [
              gradientBorderColorTop,
              gradientBorderColorTop.withValues(alpha: gradientBorderColorTop.a * 0.45),
              gradientBorderColorBottom,
            ],
          ),
        ),
        child: glassSurface,
      ),
    );
  }
}

/// Paints the directional specular light reflection edge along the container boundary.
class _LiquidBorderPainter extends CustomPainter {
  final double strokeWidth;
  final BorderRadius borderRadius;
  final Gradient gradient;

  _LiquidBorderPainter({
    required this.strokeWidth,
    required this.borderRadius,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _LiquidBorderPainter oldDelegate) =>
      strokeWidth != oldDelegate.strokeWidth ||
      borderRadius != oldDelegate.borderRadius ||
      gradient != oldDelegate.gradient;
}

/// Paints the subtle top specular meniscus sheen (light refraction off liquid curvature).
class _LiquidMeniscusPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool isDark;

  _LiquidMeniscusPainter({required this.borderRadius, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 20 || size.height <= 20) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    canvas.save();
    canvas.clipRRect(rrect);

    final meniscusHeight = math.min(18.0, size.height * 0.35);

    // Specular light sheen along the top edge
    final specularPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.3, 1.0],
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.22 : 0.55),
          Colors.white.withValues(alpha: isDark ? 0.06 : 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, meniscusHeight));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, meniscusHeight), specularPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidMeniscusPainter oldDelegate) =>
      borderRadius != oldDelegate.borderRadius || isDark != oldDelegate.isDark;
}

/// Convenience card widget implementing Liquid Glassmorphism with optional glowing border.
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
  final bool showMeniscus;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18.0),
    this.margin,
    this.borderRadius,
    this.onTap,
    this.tintColor,
    this.blurSigma = 20.0,
    this.customBorder,
    this.glowBorderColor,
    this.showMeniscus = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = borderRadius ?? BorderRadius.circular(24);

    return LiquidGlassContainer(
      padding: padding,
      margin: margin,
      borderRadius: r,
      onTap: onTap,
      tintColor: tintColor,
      blurSigma: blurSigma,
      showMeniscus: showMeniscus,
      customBorder: customBorder ??
          (glowBorderColor != null
              ? Border.all(color: glowBorderColor!, width: 1.3)
              : null),
      customShadow: glowBorderColor != null
          ? [
              BoxShadow(
                color: glowBorderColor!.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 6),
                spreadRadius: 1,
              ),
            ]
          : null,
      child: child,
    );
  }
}

/// Liquid Progress Bar that simulates a fluid vessel filling with liquid.
///
/// Features:
/// - Translucent frosted glass trough
/// - Fluid multi-stop liquid gradient with specular top highlight
/// - Soft glowing meniscus wave at the leading edge
class LiquidProgressBar extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final double height;
  final Color color;
  final Color? trackColor;
  final BorderRadius? borderRadius;

  const LiquidProgressBar({
    super.key,
    required this.value,
    this.height = 16,
    required this.color,
    this.trackColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = borderRadius ?? BorderRadius.circular(height / 2);
    final clampedValue = value.clamp(0.0, 1.0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: trackColor ??
            (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0x18000000)),
        borderRadius: r,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            // Liquid fill with tween animation
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: clampedValue),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, animatedVal, _) {
                return FractionallySizedBox(
                  widthFactor: animatedVal,
                  heightFactor: 1.0,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: r,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.4, 1.0],
                        colors: [
                          color.withValues(alpha: 0.95),
                          color,
                          color.withValues(alpha: 0.80),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.40),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Top specular meniscus shine
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: height * 0.45,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.50),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Leading edge meniscus glow
                        if (animatedVal > 0.02)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 0,
                            width: math.min(12.0, height),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: 0.45),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS-Inspired Floating Navigation Dock.
///
/// Sits elevated above page content with frosted backdrop blur, specular
/// highlights, smooth animated liquid droplet selection pill, and tactile icon items.
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
          borderRadius: BorderRadius.circular(38),
          blurSigma: 26.0,
          tintOpacity: isDark ? 0.72 : 0.84,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 7.0),
          customShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.55)
                  : const Color(0x2018291E),
              blurRadius: 36,
              offset: const Offset(0, 12),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.70),
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
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                c.brand.withValues(alpha: isDark ? 0.32 : 0.22),
                                c.brand.withValues(alpha: isDark ? 0.16 : 0.08),
                              ],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(26),
                      border: isSelected
                          ? Border.all(
                              color: isDark
                                  ? c.brand.withValues(alpha: 0.55)
                                  : c.brand.withValues(alpha: 0.40),
                              width: 1.2,
                            )
                          : Border.all(color: Colors.transparent),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: c.brand.withValues(alpha: isDark ? 0.40 : 0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.10 : 0.95,
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
        borderRadius: BorderRadius.circular(34),
        blurSigma: 26.0,
        tintOpacity: isDark ? 0.72 : 0.84,
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
                        borderRadius: BorderRadius.circular(22),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 6.0),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      c.brand.withValues(alpha: isDark ? 0.30 : 0.20),
                                      c.brand.withValues(alpha: isDark ? 0.14 : 0.07),
                                    ],
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(22),
                            border: isSelected
                                ? Border.all(
                                    color: isDark ? c.brand.withValues(alpha: 0.50) : c.brand.withValues(alpha: 0.35),
                                    width: 1.2,
                                  )
                                : Border.all(color: Colors.transparent),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: c.brand.withValues(alpha: isDark ? 0.35 : 0.22),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
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

/// Frosted liquid status badge capsule with specular glint.
class LiquidGlassBadge extends StatelessWidget {
  final String label;
  final Widget? icon;
  final Color color;
  final Color? textColor;
  final double fontSize;
  final VoidCallback? onTap;

  const LiquidGlassBadge({
    super.key,
    required this.label,
    this.icon,
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
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: isDark ? 0.28 : 0.18),
            color.withValues(alpha: isDark ? 0.14 : 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.38),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.20 : 0.10),
            blurRadius: 10,
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

/// Liquid Glass interactive button with tactile spring feedback,
/// specular meniscus reflections, and glowing caustic drop shadows.
class LiquidGlassButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? glowColor;
  final bool isSecondary;
  final bool isDanger;
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  const LiquidGlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.glowColor,
    this.isSecondary = false,
    this.isDanger = false,
    this.height = 48,
    this.width,
    this.borderRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;
    final isEnabled = widget.onPressed != null;

    final baseColor = widget.backgroundColor ??
        (widget.isDanger
            ? c.danger
            : (widget.isSecondary
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.75))
                : c.brand));

    final fgColor = widget.foregroundColor ??
        (widget.isDanger
            ? Colors.white
            : (widget.isSecondary ? c.textPrimary : c.onBrand));

    final glow = widget.glowColor ??
        (widget.isSecondary
            ? Colors.transparent
            : (widget.isDanger ? c.danger : baseColor));

    final r = widget.borderRadius ?? BorderRadius.circular(widget.height / 2);

    return AnimatedScale(
      scale: _isPressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: isEnabled && glow != Colors.transparent
              ? [
                  BoxShadow(
                    color: glow.withValues(alpha: isDark ? 0.40 : 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                    spreadRadius: _isPressed ? 1.5 : 0.5,
                  ),
                ]
              : null,
        ),
        child: CustomPaint(
          foregroundPainter: _LiquidBorderPainter(
            strokeWidth: 1.2,
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.42 : 0.88),
                Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: r,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: r,
                  onTap: widget.onPressed,
                  onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
                  onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
                  onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
                  splashColor: Colors.white.withValues(alpha: 0.16),
                  highlightColor: Colors.white.withValues(alpha: 0.08),
                  child: Container(
                    padding: widget.padding,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isEnabled
                            ? [
                                baseColor.withValues(alpha: widget.isSecondary ? 0.82 : 0.95),
                                baseColor,
                                baseColor.withValues(alpha: widget.isSecondary ? 0.62 : 0.85),
                              ]
                            : [
                                (isDark ? Colors.grey[800]! : Colors.grey[300]!)
                                    .withValues(alpha: 0.5),
                                (isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDCDCDC))
                                    .withValues(alpha: 0.45),
                                (isDark ? Colors.grey[850]! : Colors.grey[350]!)
                                    .withValues(alpha: 0.4),
                              ],
                      ),
                    ),
                    child: Row(
                      mainAxisSize: widget.width != null
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          IconTheme(
                            data: IconThemeData(
                              color: isEnabled
                                  ? fgColor
                                  : (isDark ? Colors.white38 : Colors.black38),
                              size: 18,
                            ),
                            child: widget.icon!,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: DefaultTextStyle(
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: isEnabled
                                  ? fgColor
                                  : (isDark ? Colors.white38 : Colors.black38),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular or squircle liquid glass icon button with frosted backdrop,
/// specular rim, and glowing pressed state.
class LiquidGlassIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? tooltip;
  final BorderRadius? borderRadius;

  const LiquidGlassIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.size = 42,
    this.backgroundColor,
    this.iconColor,
    this.tooltip,
    this.borderRadius,
  });

  @override
  State<LiquidGlassIconButton> createState() => _LiquidGlassIconButtonState();
}

class _LiquidGlassIconButtonState extends State<LiquidGlassIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;
    final isEnabled = widget.onPressed != null;
    final r = widget.borderRadius ?? BorderRadius.circular(widget.size / 2);

    final baseColor = widget.backgroundColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.80));

    Widget button = AnimatedScale(
      scale: _isPressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.40)
                  : const Color(0x18000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: _LiquidBorderPainter(
            strokeWidth: 1.1,
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.38 : 0.90),
                Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: r,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: r,
                  onTap: widget.onPressed,
                  onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
                  onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
                  onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          baseColor.withValues(alpha: isDark ? 0.28 : 0.85),
                          baseColor.withValues(alpha: isDark ? 0.14 : 0.65),
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: IconTheme(
                      data: IconThemeData(
                        color: widget.iconColor ??
                            (isEnabled ? c.textPrimary : c.textMuted),
                        size: widget.size * 0.52,
                      ),
                      child: widget.icon,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }
}

/// Liquid pill choice chip with fluid selected state, glowing aura,
/// specular meniscus reflection, and smooth spring feedback.
class LiquidGlassChip extends StatelessWidget {
  final String label;
  final Widget? icon;
  final bool isSelected;
  final ValueChanged<bool>? onSelected;
  final Color? activeColor;
  final EdgeInsetsGeometry padding;

  const LiquidGlassChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onSelected,
    this.activeColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;
    final color = activeColor ?? c.brand;
    final r = BorderRadius.circular(20);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: color.withValues(alpha: isDark ? 0.40 : 0.24),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        foregroundPainter: _LiquidBorderPainter(
          strokeWidth: isSelected ? 1.3 : 1.0,
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [
                    Colors.white.withValues(alpha: isDark ? 0.55 : 0.90),
                    color.withValues(alpha: isDark ? 0.40 : 0.30),
                  ]
                : [
                    Colors.white.withValues(alpha: isDark ? 0.25 : 0.70),
                    Colors.white.withValues(alpha: isDark ? 0.05 : 0.15),
                  ],
          ),
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: r,
                onTap: onSelected != null ? () => onSelected!(!isSelected) : null,
                splashColor: color.withValues(alpha: 0.2),
                child: Container(
                  padding: padding,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isSelected
                          ? [
                              color.withValues(alpha: isDark ? 0.35 : 0.24),
                              color.withValues(alpha: isDark ? 0.18 : 0.10),
                            ]
                          : [
                              (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.65)),
                              (isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.white.withValues(alpha: 0.45)),
                            ],
                    ),
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
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? (isDark ? Colors.white : color)
                              : c.textSecondary,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Liquid Glass Floating Action Button with fluid specular sheen,
/// caustic drop shadow, and tactile bounce.
class LiquidGlassFAB extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;

  const LiquidGlassFAB({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 56,
  });

  @override
  State<LiquidGlassFAB> createState() => _LiquidGlassFABState();
}

class _LiquidGlassFABState extends State<LiquidGlassFAB> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;
    final isEnabled = widget.onPressed != null;
    final baseColor = widget.backgroundColor ?? c.brand;
    final fgColor = widget.foregroundColor ?? c.onBrand;
    final r = BorderRadius.circular(widget.size / 2);

    Widget fab = AnimatedScale(
      scale: _isPressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: isDark ? 0.45 : 0.32),
              blurRadius: 20,
              offset: const Offset(0, 6),
              spreadRadius: 1,
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: _LiquidBorderPainter(
            strokeWidth: 1.3,
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.55 : 0.95),
                Colors.white.withValues(alpha: isDark ? 0.10 : 0.30),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: r,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: r,
                  onTap: widget.onPressed,
                  onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
                  onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
                  onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.5, 1.0],
                        colors: [
                          baseColor.withValues(alpha: 0.95),
                          baseColor,
                          baseColor.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: IconTheme(
                      data: IconThemeData(
                        color: fgColor,
                        size: 24,
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      fab = Tooltip(message: widget.tooltip!, child: fab);
    }

    return fab;
  }
}


