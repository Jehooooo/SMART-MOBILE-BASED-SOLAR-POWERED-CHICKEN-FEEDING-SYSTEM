import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../services/settings_service.dart';
import '../services/hardware/hardware_adapter.dart';
import '../services/hardware/mock_hardware_adapter.dart';
import '../services/hardware/firebase_hardware_adapter.dart';
import '../services/hardware/rest_hardware_adapter.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_components.dart';
import '../widgets/hardware_guide_dialog.dart';

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
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Settings & Preferences',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 110.0),
                children: [
                  // Appearance Section
                  _buildSectionHeader('Appearance', Icons.palette_outlined),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'App Theme',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.brandSoft,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.brand.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                _themeLabel(_settings.themeMode),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: c.brand,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose between light, dark, or follow your phone\'s system appearance.',
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: c.surfaceMuted.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: c.border.withValues(alpha: 0.4)),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: SizedBox(
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
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Feeder Identity Section
                  _buildSectionHeader('Feeder Device & Hardware', Icons.memory),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.drive_file_rename_outline, color: c.brand, size: 20),
                          ),
                          title: Text(
                            'Feeder Name',
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                          ),
                          subtitle: Text(_settings.feederName, style: TextStyle(color: c.textMuted)),
                          trailing: LiquidGlassButton(
                            isSecondary: true,
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onPressed: () => _showEditFeederNameDialog(context),
                            child: const Text('Edit'),
                          ),
                        ),
                        Divider(height: 24, color: c.border.withValues(alpha: 0.4)),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.inventory_2_outlined, color: c.brand, size: 20),
                          ),
                          title: Text(
                            'Hopper Total Capacity',
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
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
                        Divider(height: 24, color: c.border.withValues(alpha: 0.4)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _feeder.isMock ? c.manualSoft : c.brandSoft,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: (_feeder.isMock ? c.warning : c.brand).withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Icon(
                                    _feeder.isMock ? Icons.developer_mode : Icons.hub_outlined,
                                    size: 18,
                                    color: _feeder.isMock ? c.warning : c.brand,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Hardware Transport',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _feeder.isMock
                                        ? c.warning.withValues(alpha: 0.15)
                                        : c.brand.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (_feeder.isMock ? c.warning : c.brand).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _feeder.isMock ? 'SIMULATOR' : 'LIVE HW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _feeder.isMock ? c.warning : c.brand,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _feeder.hardwareSourceLabel,
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.surfaceMuted.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: c.border.withValues(alpha: 0.6)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<HardwareTransportType>(
                                  isExpanded: true,
                                  value: _feeder.transportType,
                                  items: const [
                                    DropdownMenuItem(
                                      value: HardwareTransportType.mockSimulator,
                                      child: Text('Mock Simulator (Off-Grid Emulation)'),
                                    ),
                                    DropdownMenuItem(
                                      value: HardwareTransportType.firebaseCloud,
                                      child: Text('Firebase Realtime Cloud (ESP32)'),
                                    ),
                                    DropdownMenuItem(
                                      value: HardwareTransportType.localRestHttp,
                                      child: Text('Local Farm Wi-Fi HTTP (SoftAP)'),
                                    ),
                                    DropdownMenuItem(
                                      value: HardwareTransportType.bluetoothLowEnergy,
                                      child: Text('Bluetooth Low Energy (Direct BLE)'),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null && val != _feeder.transportType) {
                                      _switchHardwareTransport(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Alert Thresholds Section
                  _buildSectionHeader('Safety & Alert Thresholds', Icons.notifications_active_outlined),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: c.warning.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: c.warning.withValues(alpha: 0.25)),
                                    ),
                                    child: Icon(Icons.inventory_2_outlined, size: 18, color: c.warning),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'Low Feed Warning Level',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.warning.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '< ${_settings.lowFeedThreshold.toInt()}%',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.warning),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
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

                        Divider(height: 28, color: c.border.withValues(alpha: 0.4)),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: c.dangerSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: c.dangerBorder),
                                    ),
                                    child: Icon(Icons.battery_alert_rounded, size: 18, color: c.danger),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'Low Solar Battery Warning',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.dangerSoft,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.dangerBorder),
                              ),
                              child: Text(
                                '< ${_settings.lowBatteryThreshold.toInt()}%',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.danger),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
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

                  const SizedBox(height: 22),

                  // Diagnostics & Testing Section
                  _buildSectionHeader('System Diagnostics & Testing', Icons.biotech_outlined),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_feeder.isMock) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _feeder.isSimulatingOffline ? c.dangerSoft : c.brandSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (_feeder.isSimulatingOffline ? c.danger : c.brand).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                _feeder.isSimulatingOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                                color: _feeder.isSimulatingOffline ? c.danger : c.brand,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Simulate Offline Connection',
                              style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              _feeder.isSimulatingOffline
                                  ? 'Feeder is offline by default in development. Turn OFF to test simulated online telemetry.'
                                  : 'Simulated online connection active. Turn ON to return to development offline mode.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            value: _feeder.isSimulatingOffline,
                            onChanged: (val) {
                              _feeder.setSimulatedOffline(val);
                            },
                          ),
                          Divider(height: 20, color: c.border.withValues(alpha: 0.4)),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _feeder.isSimulatingMotorJam ? c.dangerSoft : c.manualSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (_feeder.isSimulatingMotorJam ? c.danger : c.warning).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                Icons.lock_clock_rounded,
                                color: _feeder.isSimulatingMotorJam ? c.danger : c.warning,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Simulate Motor Jam (Servo Stall)',
                              style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Simulates auger physical blockage during dispensing cycle.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            value: _feeder.isSimulatingMotorJam,
                            onChanged: (val) {
                              _feeder.setSimulatedMotorJam(val);
                            },
                          ),
                          Divider(height: 20, color: c.border.withValues(alpha: 0.4)),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _feeder.isSimulatingSensorError ? c.dangerSoft : c.infoSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (_feeder.isSimulatingSensorError ? c.danger : c.info).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: _feeder.isSimulatingSensorError ? c.danger : c.info,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Simulate Sensor Failure',
                              style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Simulates HC-SR04 ultrasonic echo loss or HX711 disconnection.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            value: _feeder.isSimulatingSensorError,
                            onChanged: (val) {
                              _feeder.setSimulatedSensorError(val);
                            },
                          ),
                        ] else ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.brandSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                              ),
                              child: Icon(Icons.scale_rounded, color: c.brand, size: 20),
                            ),
                            title: Text(
                              'Zero / Tare Scale Sensor',
                              style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                            ),
                            subtitle: Text(
                              'Sends hardware calibration command to HX711 load cell.',
                              style: TextStyle(fontSize: 12, color: c.textMuted),
                            ),
                            trailing: LiquidGlassButton(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              onPressed: () async {
                                final ok = await _feeder.tareScale();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Tare command sent to hardware successfully.'
                                          : 'Failed to send tare command. Check connection.'),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Tare (0.0g)'),
                            ),
                          ),
                        ],
                        Divider(height: 24, color: c.border.withValues(alpha: 0.4)),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.school_outlined, color: c.brand, size: 20),
                          ),
                          title: Text(
                            'Replay First-Run Onboarding',
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                          ),
                          subtitle: Text(
                            'Launch the walkthrough guide for farm staff training.',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                          trailing: LiquidGlassButton(
                            isSecondary: true,
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onPressed: () {
                              _settings.setOnboardingComplete(false);
                            },
                            child: const Text('Replay'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Help & About Section
                  _buildSectionHeader('Help & Support', Icons.help_outline),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.menu_book_outlined, color: c.brand, size: 20),
                          ),
                          title: Text(
                            'Machine Setup & Integration Guide',
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                          ),
                          subtitle: Text(
                            'Step-by-step physical bring-up, sensor calibration, pinout & backend cloud flow.',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showHardwareGuideDialog(context),
                        ),
                        Divider(height: 20, color: c.border.withValues(alpha: 0.4)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: LiquidGlassButton(
                            isDanger: true,
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            onPressed: () => _confirmResetDefaults(context),
                            icon: const Icon(Icons.restore, size: 16),
                            child: const Text('Reset Feeder Settings to Default'),
                          ),
                        ),
                      ],
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
      padding: const EdgeInsets.only(left: 4.0, bottom: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.brand.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 16, color: c.brand),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.2,
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
      builder: (ctx) => LiquidGlassDialog(
        title: const Text('Edit Feeder Name', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Feeder Name',
            hintText: 'e.g. Coop #1 Broiler Feeder',
          ),
        ),
        actions: [
          LiquidGlassButton(
            isSecondary: true,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          LiquidGlassButton(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      builder: (ctx) => LiquidGlassDialog(
        title: const Text('Reset Feeder Defaults?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'This will restore default feeder naming, 5.0 kg hopper capacity, and 20% alert thresholds. Your custom feeding schedules and logs will remain untouched.',
        ),
        actions: [
          LiquidGlassButton(
            isSecondary: true,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          LiquidGlassButton(
            isDanger: true,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  void _switchHardwareTransport(HardwareTransportType type) {
    FeederHardwareAdapter newAdapter;
    switch (type) {
      case HardwareTransportType.mockSimulator:
        newAdapter = MockHardwareAdapter(simulateOffline: false);
        break;
      case HardwareTransportType.firebaseCloud:
        newAdapter = FirebaseHardwareAdapter();
        break;
      case HardwareTransportType.localRestHttp:
        newAdapter = RestHardwareAdapter();
        break;
      case HardwareTransportType.bluetoothLowEnergy:
        newAdapter = MockHardwareAdapter(
          simulateOffline: false,
          sourceLabel: 'Bluetooth Low Energy (Direct BLE)',
          transportType: HardwareTransportType.bluetoothLowEnergy,
        );
        break;
    }
    _settings.setHardwareTransport(type);
    _feeder.switchAdapter(newAdapter);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Hardware transport switched to ${newAdapter.hardwareSourceLabel}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
