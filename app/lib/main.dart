import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/feeder_service.dart';
import 'services/settings_service.dart';
import 'services/hardware/hardware_adapter.dart';
import 'services/hardware/firebase_hardware_adapter.dart';
import 'services/hardware/rest_hardware_adapter.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/app_logo.dart';
import 'widgets/glass_components.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SmartChickenFeederApp.initializeFirebaseBackend();
  final settings = await SettingsService.load();
  final feederService = FeederService(
    adapter: SmartChickenFeederApp.resolveAdapter(settings.hardwareTransport),
    lowFeedThreshold: settings.lowFeedThreshold,
    lowBatteryThreshold: settings.lowBatteryThreshold,
  );
  await feederService.loadLocalData();
  runApp(SmartChickenFeederApp(
    settingsService: settings,
    feederService: feederService,
  ));
}

class SmartChickenFeederApp extends StatefulWidget {
  final SettingsService settingsService;

  /// Optional injected service (used by widget tests to control timing).
  final FeederService? feederService;

  const SmartChickenFeederApp({super.key, required this.settingsService, this.feederService});

  /// Initializes Firebase Core and Anonymous/Session Auth on supported platforms.
  /// Reports missing native configuration clearly via diagnostic logs and falls back
  /// gracefully to the cross-platform REST synchronization engine when unavailable.
  static Future<bool> initializeFirebaseBackend() async {
    if (Firebase.apps.isNotEmpty) return true;

    const envApiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const envAppId = String.fromEnvironment('FIREBASE_APP_ID');
    const envMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const envProjectId = String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'smart-chicken-feeder-33bec',
    );
    const envDatabaseUrl = String.fromEnvironment(
      'FIREBASE_DATABASE_URL',
      defaultValue: FeederService.defaultDatabaseUrl,
    );

    final supportsNativeFirebase = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (!supportsNativeFirebase) {
      debugPrint(
        '[FirebaseInit] Desktop platform (${defaultTargetPlatform.name}) uses authenticated REST RTDB engine.',
      );
      return false;
    }

    try {
      if (envApiKey.isNotEmpty && envAppId.isNotEmpty && envMessagingSenderId.isNotEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: envApiKey,
            appId: envAppId,
            messagingSenderId: envMessagingSenderId,
            projectId: envProjectId,
            databaseURL: envDatabaseUrl,
          ),
        );
      } else if (!kIsWeb) {
        await Firebase.initializeApp();
      } else {
        debugPrint(
          '[FirebaseInit] Web FirebaseOptions not passed via --dart-define; using REST RTDB fallback.',
        );
        return false;
      }

      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
      } catch (authErr) {
        debugPrint(
          '[FirebaseInit] Anonymous sign-in unavailable ($authErr). Enable Anonymous Auth in Firebase Console before enforcing strict RTDB rules.',
        );
      }
      return true;
    } catch (e) {
      debugPrint(
        '[FirebaseInit] Native Firebase initialization skipped ($e). Falling back to REST RTDB adapter.',
      );
      return false;
    }
  }

  static FeederHardwareAdapter resolveAdapter(HardwareTransportType type) {
    switch (type) {
      case HardwareTransportType.firebaseCloud:
        return FirebaseHardwareAdapter();
      case HardwareTransportType.localRestHttp:
        return RestHardwareAdapter();
    }
  }

  @override
  State<SmartChickenFeederApp> createState() => _SmartChickenFeederAppState();
}

class _SmartChickenFeederAppState extends State<SmartChickenFeederApp> {
  late final FeederService _feederService;

  void _syncSettingsThresholds() {
    _feederService.updateAlertThresholds(
      lowFeedThreshold: widget.settingsService.lowFeedThreshold,
      lowBatteryThreshold: widget.settingsService.lowBatteryThreshold,
    );
  }

  @override
  void initState() {
    super.initState();
    _feederService = widget.feederService ??
        FeederService(
          adapter: SmartChickenFeederApp.resolveAdapter(widget.settingsService.hardwareTransport),
          lowFeedThreshold: widget.settingsService.lowFeedThreshold,
          lowBatteryThreshold: widget.settingsService.lowBatteryThreshold,
        );
    _syncSettingsThresholds();
    widget.settingsService.addListener(_syncSettingsThresholds);
  }

  @override
  void dispose() {
    widget.settingsService.removeListener(_syncSettingsThresholds);
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
          // Desktop / Tablet layout with side Liquid Glass NavigationRail
          return LiquidBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Row(
                children: [
                  LiquidGlassContainer(
                    margin: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    borderRadius: BorderRadius.circular(30),
                    blurSigma: 24,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: NavigationRail(
                      backgroundColor: Colors.transparent,
                      selectedIndex: _currentIndex,
                      onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
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
                  ),
                  Expanded(child: currentScreenWidget),
                ],
              ),
            ),
          );
        }

        // Mobile / Compact layout with iOS-Inspired Floating Navigation Dock
        return LiquidBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(
                  child: currentScreenWidget,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: IOSFloatingNavigationBar(
                      selectedIndex: _currentIndex,
                      onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
                      destinations: _destinations,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
