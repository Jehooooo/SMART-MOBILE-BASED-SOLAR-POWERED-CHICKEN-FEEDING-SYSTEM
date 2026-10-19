import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: widget.onFinished,
            child: Text(
              'Skip',
              style: TextStyle(
                color: c.textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    itemBuilder: (context, idx) {
                      final item = _slides[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: c.brandSoft,
                                borderRadius: BorderRadius.circular(38),
                                border: Border.all(color: c.brandBorder.withValues(alpha: 0.6), width: 1.5),
                              ),
                              child: Icon(item.icon, size: 62, color: c.brand),
                            ),
                            const SizedBox(height: 28),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                              decoration: BoxDecoration(
                                color: c.brandSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.brandBorder.withValues(alpha: 0.7)),
                              ),
                              child: Text(
                                item.badge,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: c.brand,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: c.textPrimary,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              item.description,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

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
                        color: isCurrent ? c.brand : c.border.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                // Bottom Action Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.brand,
                        foregroundColor: c.onBrand,
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        isLastPage ? 'GET STARTED' : 'CONTINUE',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
