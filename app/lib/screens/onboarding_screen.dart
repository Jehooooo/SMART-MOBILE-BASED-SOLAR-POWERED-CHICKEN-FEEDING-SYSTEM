import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/glass_components.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _slides = [
    (
      icon: Icons.solar_power_rounded,
      badge: 'Solar-Powered • Off-Grid',
      title: 'Automated Poultry Feeding',
      description:
          'Monitor your flock\'s feeding routines anywhere. Powered 24/7 by a 12V solar system designed for rural farms and remote poultry coops.',
    ),
    (
      icon: Icons.inventory_2_rounded,
      badge: 'Sensors & Telemetry',
      title: 'Real-Time Hopper & Battery Levels',
      description:
          'HC-SR04 ultrasonic sensors measure remaining feed depth, while battery voltage telemetry keeps you alerted before feed or power runs low.',
    ),
    (
      icon: Icons.schedule_rounded,
      badge: 'Fail-Safe Automation',
      title: 'Set Scheduled Feeding Routines',
      description:
          'Configure morning, midday, and afternoon rations. Once programmed, scheduled feeds execute locally on the controller even during network dropouts.',
    ),
    (
      icon: Icons.scale_rounded,
      badge: 'Precision Dispensing',
      title: 'Load-Cell Accuracy & Research Logs',
      description:
          'Every dispense is weighed using an HX711 load cell down to ±2g accuracy. Export comprehensive CSV logs for Excel, SPSS, and thesis documentation.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    } else {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LiquidBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar with Skip Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    LiquidGlassContainer(
                      borderRadius: BorderRadius.circular(20),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: TextButton(
                        onPressed: widget.onFinished,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Slide Content
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (idx) => setState(() => _currentPage = idx),
                      itemBuilder: (context, idx) {
                        final item = _slides[idx];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                          child: LiquidGlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (idx == 0)
                                    const AppLogo(size: 100, borderWidth: 3.0)
                                  else
                                    LiquidGlassContainer(
                                      width: 90,
                                      height: 90,
                                      borderRadius: BorderRadius.circular(28),
                                      child: Center(
                                        child: Icon(item.icon, size: 48, color: c.brand),
                                      ),
                                    ),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: c.brandSoft,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: c.brand.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      item.badge,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: c.brand,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    item.title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                      color: c.textPrimary,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    item.description,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.textSecondary,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Dot Page Indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (idx) {
                  final isCurrent = idx == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: isCurrent ? 28 : 8,
                    decoration: BoxDecoration(
                      color: isCurrent ? c.brand : c.border.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: c.brand.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),

              // Bottom Action Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.brand,
                        foregroundColor: c.onBrand,
                        elevation: 4,
                        shadowColor: c.brand.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Text(
                        isLastPage ? 'GET STARTED' : 'CONTINUE',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
