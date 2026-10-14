import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';

class SettingsScreen extends StatefulWidget {
  final FeederService feederService;
  final SettingsService settingsService;

  const SettingsScreen({
    super.key,
    required this.feederService,
    required this.settingsService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _settings => widget.settingsService;
  FeederService get _feeder => widget.feederService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_settings, _feeder]),
      builder: (context, _) {
        final c = context.colors;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Settings & Preferences',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Appearance Section
                  _buildSectionHeader('Appearance', Icons.palette_outlined),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'App Theme',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: c.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _themeLabel(_settings.themeMode),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.brand,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose between light, dark, or follow your phone\'s system appearance.',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto, size: 18),
                                  label: Text('System'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode_outlined, size: 18),
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode_outlined, size: 18),
                                  label: Text('Dark'),
                                ),
                              ],
                              selected: {_settings.themeMode},
                              onSelectionChanged: (selected) {
                                _settings.setThemeMode(selected.first);
                              },
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Feeder Identity Section
                  _buildSectionHeader('Feeder Device & Hardware', Icons.memory),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: c.brandSoft,
                              child: Icon(Icons.drive_file_rename_outline, color: c.brand),
                            ),
                            title: Text(
                              'Feeder Name',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                            ),
                            subtitle: Text(_settings.feederName, style: TextStyle(color: c.textMuted)),
                            trailing: OutlinedButton(
                              onPressed: () => _showEditFeederNameDialog(context),
                              child: const Text('Edit'),
                            ),
                          ),
                          const Divider(height: 20),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: c.brandSoft,
                              child: Icon(Icons.inventory_2_outlined, color: c.brand),
                            ),
                            title: Text(
                              'Hopper Total Capacity',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              '${_settings.hopperCapacityKg.toStringAsFixed(1)} kg (${(_settings.hopperCapacityKg * 1000).toInt()} grams)',
                              style: TextStyle(color: c.textMuted),
                            ),
                            trailing: DropdownButton<double>(
                              value: _settings.hopperCapacityKg,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 3.0, child: Text('3.0 kg')),
                                DropdownMenuItem(value: 5.0, child: Text('5.0 kg (Std)')),
                                DropdownMenuItem(value: 10.0, child: Text('10.0 kg')),
                                DropdownMenuItem(value: 15.0, child: Text('15.0 kg')),
                              ],
                              onChanged: (val) {
                                if (val != null) _settings.setHopperCapacityKg(val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Alert Thresholds Section
                  _buildSectionHeader('Safety & Alert Thresholds', Icons.notifications_active_outlined),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.inventory_2, size: 18, color: c.warning),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Low Feed Warning Level',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.warning.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Trigger below ${_settings.lowFeedThreshold.toInt()}%',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.warning),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _settings.lowFeedThreshold,
                            min: 10.0,
                            max: 40.0,
                            divisions: 6,
                            activeColor: c.warning,
                            inactiveColor: c.track,
                            label: '${_settings.lowFeedThreshold.toInt()}%',
                            onChanged: (val) => _settings.setLowFeedThreshold(val),
                          ),
                          Text(
                            'Displays a refill banner on Dashboard when ultrasonic level drops below this percentage.',
                            style: TextStyle(fontSize: 11, color: c.textMuted),
                          ),

                          const Divider(height: 24),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.battery_alert, size: 18, color: c.danger),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Low Solar Battery Warning',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.danger.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Trigger below ${_settings.lowBatteryThreshold.toInt()}%',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.danger),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _settings.lowBatteryThreshold,
                            min: 10.0,
                            max: 35.0,
                            divisions: 5,
                            activeColor: c.danger,
                            inactiveColor: c.track,
                            label: '${_settings.lowBatteryThreshold.toInt()}%',
                            onChanged: (val) => _settings.setLowBatteryThreshold(val),
                          ),
                          Text(
                            'Warns operator to inspect solar panel orientation or battery storage health.',
                            style: TextStyle(fontSize: 11, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Diagnostics & Testing Section
                  _buildSectionHeader('Diagnostics & Farm Simulation', Icons.biotech_outlined),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: CircleAvatar(
                              backgroundColor: _feeder.isSimulatingOffline ? c.dangerSoft : c.brandSoft,
                              child: Icon(
                                _feeder.isSimulatingOffline ? Icons.cloud_off : Icons.cloud_done,
                                color: _feeder.isSimulatingOffline ? c.danger : c.brand,
                              ),
                            ),
                            title: Text(
                              'Simulate Offline Connection',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Test app recovery, offline banners, and disabled states without turning off hardware.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            value: _feeder.isSimulatingOffline,
                            onChanged: (val) {
                              _feeder.setSimulatedOffline(val);
                            },
                          ),
                          const Divider(height: 20),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: c.brandSoft,
                              child: Icon(Icons.school_outlined, color: c.brand),
                            ),
                            title: Text(
                              'Replay First-Run Onboarding',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Launch the walkthrough guide for farm staff training.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            trailing: OutlinedButton(
                              onPressed: () {
                                _settings.setOnboardingComplete(false);
                              },
                              child: const Text('Replay'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Help & About Section
                  _buildSectionHeader('Help & Research Info', Icons.help_outline),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: c.brandSoft,
                              child: Icon(Icons.menu_book_outlined, color: c.brand),
                            ),
                            title: Text(
                              'System & Hardware Guide',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Ultrasonic sensor, solar panel, load cell calibration details.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showHardwareGuideDialog(context),
                          ),
                          const Divider(height: 20),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: c.brandSoft,
                              child: Icon(Icons.info_outline, color: c.brand),
                            ),
                            title: Text(
                              'Smart Poultry Feeder System',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Version $kAppVersion (Build $kAppBuild)\nResearch Project • Capstone Study',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                          ),
                          const Divider(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _confirmResetDefaults(context),
                              icon: Icon(Icons.restore, color: c.danger, size: 18),
                              label: Text(
                                'Reset Feeder Settings to Default',
                                style: TextStyle(color: c.danger, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.brand),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follows System';
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
    }
  }

  void _showEditFeederNameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: _settings.feederName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Feeder Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Feeder Name',
            hintText: 'e.g. Coop #1 Broiler Feeder',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _settings.setFeederName(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmResetDefaults(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Feeder Defaults?'),
        content: const Text(
          'This will restore default feeder naming, 5.0 kg hopper capacity, and 20% alert thresholds. Your custom feeding schedules and logs will remain untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _settings.resetFeederDefaults();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Feeder settings restored to default')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
