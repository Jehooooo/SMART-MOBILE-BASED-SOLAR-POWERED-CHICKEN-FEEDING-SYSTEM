import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A stylized circular logo widget featuring the Smart Chicken Feeder emblem
/// with a dedicated circular border, subtle elevation, and scalable sizing.
class AppLogo extends StatelessWidget {
  /// The diameter (width and height) of the circular logo.
  final double size;

  /// Optional custom border color. Defaults to [AppColorPalette.brand].
  final Color? borderColor;

  /// Width of the circular border outline. Defaults to 2.0.
  final double borderWidth;

  /// Whether to render a soft ambient shadow beneath the circular badge.
  final bool hasShadow;

  const AppLogo({
    super.key,
    this.size = 40.0,
    this.borderColor,
    this.borderWidth = 2.0,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strokeColor = borderColor ?? c.brand;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: strokeColor,
          width: borderWidth,
        ),
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: size * 0.18,
                  offset: Offset(0, size * 0.05),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback if image asset is not available
            return CircleAvatar(
              backgroundColor: c.brand,
              child: Icon(
                Icons.solar_power_rounded,
                color: c.onBrand,
                size: size * 0.55,
              ),
            );
          },
        ),
      ),
    );
  }
}
