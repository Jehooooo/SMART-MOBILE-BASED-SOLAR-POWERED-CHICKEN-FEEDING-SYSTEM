import 'package:flutter/material.dart';
import 'services/feeder_service.dart';
import 'services/settings_service.dart';
import 'services/hardware/hardware_adapter.dart';
import 'services/hardware/mock_hardware_adapter.dart';
import 'services/hardware/firebase_hardware_adapter.dart';
import 'services/hardware/rest_hardware_adapter.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.load();
  runApp(SmartChickenFeederApp(settingsService: settings));
}

class SmartChickenFeederApp extends StatefulWidget {
  final SettingsService settingsService;

  /// Optional injected service (used by widget tests to control timing).
  final FeederService? feederService;

  const SmartChickenFeederApp({super.key, required this.settingsService, this.feederService});

  @override
  State<SmartChickenFeederApp> createState() => _SmartChickenFeederAppState();
}

class _SmartChickenFeederAppState extends State<SmartChickenFeederApp> {
  late final FeederService _feederService;

  @override
  void initState() {
    super.initState();
    _feederService = widget.feederService ??
        FeederService(
          adapter: _resolveAdapter(widget.settingsService.hardwareTransport),
        );
  }

  static FeederHardwareAdapter _resolveAdapter(HardwareTransportType type) {
    switch (type) {
      case HardwareTransportType.mockSimulator:
        return MockHardwareAdapter(simulateOffline: true);
      case HardwareTransportType.firebaseCloud:
        return FirebaseHardwareAdapter();
      case HardwareTransportType.localRestHttp:
        return RestHardwareAdapter();
      case HardwareTransportType.bluetoothLowEnergy:
        return MockHardwareAdapter(
          simulateOffline: true,
          sourceLabel: 'Bluetooth Low Energy (Direct BLE)',
          transportType: HardwareTransportType.bluetoothLowEnergy,
        );
    }
  }

  @override
  void dispose() {
    if (widget.feederService == null) {
      _feederService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsService;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Smart Poultry Feeder',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 280),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: settings.onboardingComplete
                ? MainNavigationShell(
                    key: const ValueKey('shell'),
                    feederService: _feederService,
                    settingsService: settings,
                  )
                : OnboardingScreen(
                    key: const ValueKey('onboarding'),
                    onFinished: () => settings.setOnboardingComplete(true),
                  ),
          ),
        );
      },
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  final FeederService feederService;
  final SettingsService settingsService;

  const MainNavigationShell({super.key, required this.feederService, required this.settingsService});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.schedule_outlined, selected: Icons.schedule, label: 'Schedules'),
    (icon: Icons.history_outlined, selected: Icons.history, label: 'History & Logs'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screens = [
      DashboardScreen(feederService: widget.feederService, settingsService: widget.settingsService),
      SchedulesScreen(feederService: widget.feederService),
      HistoryScreen(feederService: widget.feederService),
      SettingsScreen(feederService: widget.feederService, settingsService: widget.settingsService),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 720;

        final currentScreenWidget = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_currentIndex),
            child: screens[_currentIndex],
          ),
        );

        if (isWideScreen) {
          // Desktop / Tablet layout with side NavigationRail
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: AppLogo(size: 42, borderWidth: 2.2),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected, color: c.brand),
                        label: Text(d.label),
                      ),
                  ],
                ),
                VerticalDivider(thickness: 1, width: 1, color: c.border),
                Expanded(child: currentScreenWidget),
              ],
            ),
          );
        }

        // Mobile layout with bottom NavigationBar
        return Scaffold(
          body: currentScreenWidget,
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: c.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, -2),
                ),
              ],
              border: Border(
                top: BorderSide(color: c.border.withValues(alpha: 0.6), width: 0.8),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected, color: c.brand),
                    label: d.label,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
