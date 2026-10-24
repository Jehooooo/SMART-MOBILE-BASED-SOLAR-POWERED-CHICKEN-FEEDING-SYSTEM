import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glass_components.dart';

/// Gives every [SkeletonBox] below it a gentle shared pulse animation.
///
/// The pulse turns off when the OS "reduce motion" setting is on.
class SkeletonPulse extends StatefulWidget {
  final Widget child;

  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
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
    return Semantics(
      label: 'Loading feeder data',
      liveRegion: true,
      child: ExcludeSemantics(
        child: _PulseScope(
          notifier: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          child: widget.child,
        ),
      ),
    );
  }
}

class _PulseScope extends InheritedNotifier<Animation<double>> {
  const _PulseScope({required super.notifier, required super.child});

  static double valueOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_PulseScope>();
    return scope?.notifier?.value ?? 0.0;
  }
}

/// A rounded placeholder block shown while content is loading.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = _PulseScope.valueOf(context);
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(
          c.skeletonBase.withValues(alpha: 0.5),
          c.skeletonHighlight.withValues(alpha: 0.8),
          t,
        ),
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
      ),
    );
  }
}

/// Card-shaped container that matches the real cards' liquid glass border and padding.
class SkeletonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SkeletonCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(padding: padding, child: child);
  }
}

/// Placeholder layout that mirrors the Dashboard while the first sync runs.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          SkeletonCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    SkeletonBox(height: 36, width: 36, radius: 10),
                    SizedBox(width: 10),
                    SkeletonBox(height: 16, width: 140),
                    Spacer(),
                    SkeletonBox(height: 26, width: 56, radius: 12),
                  ],
                ),
                SizedBox(height: 18),
                SkeletonBox(height: 18),
                SizedBox(height: 14),
                SkeletonBox(height: 12, width: 200),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: _MetricSkeleton()),
              SizedBox(width: 12),
              Expanded(child: _MetricSkeleton()),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonCard(
            child: Row(
              children: [
                SkeletonBox(height: 44, circle: true),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 11, width: 130),
                      SizedBox(height: 8),
                      SkeletonBox(height: 15, width: 200),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 16, width: 160),
                SizedBox(height: 14),
                Row(
                  children: [
                    SkeletonBox(height: 44, width: 64, radius: 12),
                    SizedBox(width: 8),
                    SkeletonBox(height: 44, width: 64, radius: 12),
                    SizedBox(width: 8),
                    SkeletonBox(height: 44, width: 64, radius: 12),
                  ],
                ),
                SizedBox(height: 18),
                SkeletonBox(height: 48, radius: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSkeleton extends StatelessWidget {
  const _MetricSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 28, width: 90, radius: 8),
          SizedBox(height: 12),
          SkeletonBox(height: 18, width: 70),
          SizedBox(height: 6),
          SkeletonBox(height: 10, width: 100),
        ],
      ),
    );
  }
}

/// Generic list placeholder used by the Schedules and History screens.
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showHeaderCard;

  const ListSkeleton({super.key, this.itemCount = 4, this.showHeaderCard = true});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          if (showHeaderCard) ...[
            const SkeletonCard(
              child: Row(
                children: [
                  SkeletonBox(height: 44, width: 44, radius: 12),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 15, width: 170),
                        SizedBox(height: 8),
                        SkeletonBox(height: 12, width: 120),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          for (var i = 0; i < itemCount; i++) ...[
            const SkeletonCard(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  SkeletonBox(height: 40, circle: true),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 18, width: 90),
                        SizedBox(height: 8),
                        SkeletonBox(height: 12, width: 150),
                      ],
                    ),
                  ),
                  SkeletonBox(height: 24, width: 40, radius: 12),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
