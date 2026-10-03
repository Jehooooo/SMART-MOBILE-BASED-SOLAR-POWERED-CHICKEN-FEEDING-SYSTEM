import 'package:flutter/material.dart';
import 'services/feeder_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/history_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartChickenFeederApp());
}

class SmartChickenFeederApp extends StatefulWidget {
  const SmartChickenFeederApp({super.key});

  @override
  State<SmartChickenFeederApp> createState() => _SmartChickenFeederAppState();
}

class _SmartChickenFeederAppState extends State<SmartChickenFeederApp> {
  late final FeederService _feederService;

  @override
  void initState() {
    super.initState();
    _feederService = FeederService();
  }

  @override
  void dispose() {
    _feederService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Poultry Feeder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E), // Natural agricultural teal
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Crisp clean slate background
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0.5,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
      home: MainNavigationShell(feederService: _feederService),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  final FeederService feederService;

  const MainNavigationShell({super.key, required this.feederService});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(feederService: widget.feederService),
      SchedulesScreen(feederService: widget.feederService),
      HistoryScreen(feederService: widget.feederService),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        indicatorColor: const Color(0xFFCCFBF1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Color(0xFF0F766E)),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule, color: Color(0xFF0F766E)),
            label: 'Schedules',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: Color(0xFF0F766E)),
            label: 'History & Logs',
          ),
        ],
      ),
    );
  }
}
