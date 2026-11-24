import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../services/settings_service.dart';
import '../services/hardware/hardware_adapter.dart';
import '../services/hardware/firebase_hardware_adapter.dart';
import '../services/hardware/rest_hardware_adapter.dart';
import '../utils/feed_portions.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_components.dart';
import '../widgets/hardware_guide_dialog.dart';
import 'diagnostics_screen.dart';

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
                            '${_settings.hopperCapacityKg.toStringAsFixed(1)} kg',
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
                                    color: c.brandSoft,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: c.brand.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.hub_outlined,
                                    size: 18,
                                    color: c.brand,
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
                                    color: (_feeder.isOfflineSimulationMode ? c.info : c.brand)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (_feeder.isOfflineSimulationMode ? c.info : c.brand)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _feeder.isOfflineSimulationMode ? 'SIMULATION' : 'LIVE HW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _feeder.isOfflineSimulationMode ? c.infoStrong : c.brand,
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
                                      value: HardwareTransportType.firebaseCloud,
                                      child: Text('Firebase Realtime Cloud (ESP32)'),
                                    ),
                                    DropdownMenuItem(
                                      value: HardwareTransportType.localRestHttp,
                                      child: Text('Direct Wi-Fi HTTP (SoftAP 192.168.4.1)'),
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
                            const SizedBox(height: 12),
                            LiquidGlassButton(
                              width: double.infinity,
                              height: 42,
                              isSecondary: true,
                              icon: const Icon(Icons.wifi_protected_setup_rounded, size: 18),
                              onPressed: () => _showProvisionWifiDialog(context),
                              child: const Text('Configure Feeder 2.4 GHz Wi-Fi (SoftAP)'),
                            ),
                            Divider(height: 24, color: c.border.withValues(alpha: 0.4)),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: c.info.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: c.info.withValues(alpha: 0.25)),
                                ),
                                child: Icon(Icons.science_outlined, color: c.infoStrong, size: 20),
                              ),
                              title: Text(
                                'Offline Simulation / Test Mode',
                                style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                              ),
                              subtitle: Text(
                                _feeder.isOfflineSimulationMode
                                    ? 'Active: testing kg/g display, manual feed, schedules & logs locally (zero hardware or Firebase changes).'
                                    : 'Preview and test the updated app completely offline without connecting to the ESP32 or modifying Firebase.',
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                              value: _feeder.isOfflineSimulationMode,
                              onChanged: (enabled) {
                                _feeder.setOfflineSimulationMode(enabled);
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        enabled
                                            ? 'Offline Simulation Mode enabled — test safely offline.'
                                            : 'Offline Simulation Mode turned off — restored live state.',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Portion Estimation & Notifications Section
                  _buildSectionHeader('Portion Estimation & Notifications', Icons.notifications_active_outlined),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: c.brandSoft,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.brand.withValues(alpha: 0.25)),
                              ),
                              child: Icon(Icons.timer_outlined, size: 18, color: c.brand),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Time-Based Portion Estimation',
                                style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Active bench-tested feed output ranges based on dispenser gate open duration:',
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [1, 2, 3, 4, 5].map((sec) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: c.surfaceMuted.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c.border.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                '${sec}s (${FeedPortions.formatRangeForDuration(sec)})',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.brand),
                              ),
                            );
                          }).toList(),
                        ),
                        Divider(height: 26, color: c.border.withValues(alpha: 0.4)),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.volume_up_rounded, color: c.brand, size: 20),
                          ),
                          title: Text(
                            'Test Feed Notification & Sound',
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                          ),
                          subtitle: Text(
                            'Fires a sample phone notification and plays the 1-second chicken cluck audio.',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                          trailing: LiquidGlassButton(
                            isSecondary: true,
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onPressed: () async {
                              await _feeder.alertService.notifyDispenseTriggered(
                                durationSeconds: 1,
                                targetGrams: FeedPortions.gramsForDuration(1),
                                triggerLabel: 'Notification Test',
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('Test notification & 1-second chicken cluck triggered.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                            },
                            child: const Text('Test Alert'),
                          ),
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
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.brandSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.tune_rounded, color: c.brand, size: 20),
                          ),
                          title: Text(
                            'Servo Gate & Controller Diagnostics',
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                          ),
                          subtitle: Text(
                            'Test DS-S020A-C gate angles (30° closed / 0° open), check DS3231 solar window, and verify ESP32 link.',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                          trailing: LiquidGlassButton(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DiagnosticsScreen(feederService: _feeder),
                                ),
                              );
                            },
                            child: const Text('Open Suite'),
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
                            'Step-by-step physical bring-up, time-based estimation, pinout & backend cloud flow.',
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
          'This will restore default feeder naming and 5.0 kg hopper capacity. Your custom feeding schedules and logs will remain untouched.',
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
      case HardwareTransportType.firebaseCloud:
        newAdapter = FirebaseHardwareAdapter();
        break;
      case HardwareTransportType.localRestHttp:
        newAdapter = RestHardwareAdapter();
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

  Future<void> _showProvisionWifiDialog(BuildContext context) async {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final existing = await RestHardwareAdapter.querySoftApWifiStatus();
    if (existing != null && existing['staSsid'] is String) {
      ssidCtrl.text = existing['staSsid'] as String;
    }
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return LiquidGlassDialog(
              maxWidth: 440,
              title: const Text('Feeder 2.4 GHz Wi-Fi Setup', style: TextStyle(fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Connect this phone to Wi-Fi "SmartFeeder-AP" (password: chickens123).\n'
                    '2. Enter the farm/home 2.4 GHz Wi-Fi credentials below to link the ESP32 to Firebase Cloud.',
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                  if (existing != null && existing['staConnected'] == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Current Feeder Link: Connected to ${existing['staSsid']} (${existing['staIp']})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.brand),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: ssidCtrl,
                    decoration: const InputDecoration(
                      labelText: '2.4 GHz Wi-Fi Name (SSID)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Wi-Fi Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                LiquidGlassButton(
                  isSecondary: true,
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                LiquidGlassButton(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onPressed: saving
                      ? null
                      : () async {
                          if (ssidCtrl.text.trim().isEmpty) return;
                          setDialogState(() => saving = true);
                          final res = await RestHardwareAdapter.provisionSoftApWifi(
                            ssid: ssidCtrl.text.trim(),
                            password: passCtrl.text,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          final connected = res != null && res['staConnected'] == true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                res == null
                                    ? 'Could not reach 192.168.4.1. Connect phone to SmartFeeder-AP first.'
                                    : connected
                                        ? 'Feeder connected to "${res['staSsid']}" (${res['staIp']})! Switch back to your Wi-Fi/LTE for Cloud mode.'
                                        : 'Saved "${ssidCtrl.text.trim()}" to ESP32 NVS. Verifying 2.4 GHz router link...',
                              ),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        },
                  child: Text(saving ? 'Connecting...' : 'Save & Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
