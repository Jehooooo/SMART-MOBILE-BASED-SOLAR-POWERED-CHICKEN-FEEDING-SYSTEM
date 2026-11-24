import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'glass_components.dart';

/// Interactive, comprehensive guide for physical machine bring-up and backend configuration.
void showHardwareGuideDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const _HardwareGuideModal(),
  );
}

class _HardwareGuideModal extends StatefulWidget {
  const _HardwareGuideModal();

  @override
  State<_HardwareGuideModal> createState() => _HardwareGuideModalState();
}

class _HardwareGuideModalState extends State<_HardwareGuideModal> {
  int _selectedTab = 0; // 0: Setup, 1: Backend, 2: Checklist, 3: Pinout

  final _tabs = const [
    (label: 'Machine Setup', icon: Icons.build_circle_outlined),
    (label: 'Backend & Cloud', icon: Icons.cloud_sync_outlined),
    (label: 'Checklist', icon: Icons.checklist_rounded),
    (label: 'Wiring & Pinout', icon: Icons.cable_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 500;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: media.size.height * 0.88,
        ),
        child: LiquidGlassContainer(
          borderRadius: BorderRadius.circular(24),
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
                child: Row(
                  children: [
                    const AppLogo(size: 40, borderWidth: 2.0),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Machine & Backend Guide',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Physical bring-up, sensor calibration & cloud data flow',
                            style: TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                    LiquidGlassIconButton(
                      size: 34,
                      icon: Icon(Icons.close_rounded, color: c.textMuted, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Tab Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_tabs.length, (idx) {
                      final isSelected = _selectedTab == idx;
                      final tab = _tabs[idx];
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: LiquidGlassChip(
                          label: tab.label,
                          icon: Icon(
                            tab.icon,
                            size: 16,
                            color: isSelected ? (isDark ? Colors.white : c.brand) : c.textSecondary,
                          ),
                          isSelected: isSelected,
                          onSelected: (val) {
                            if (val) setState(() => _selectedTab = idx);
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ),

              Divider(height: 18, color: c.border.withValues(alpha: 0.4)),

              // Tab Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: _buildTabContent(context, _selectedTab),
                ),
              ),

              // Footer Action
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.4))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ESP32 38-Pin • Dual Buck 7.4V/5V • DS3231 RTC • 12V Solar',
                        style: TextStyle(fontSize: 11, color: c.textMuted, fontWeight: FontWeight.w500),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.brand,
                        foregroundColor: c.onBrand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, int tabIndex) {
    switch (tabIndex) {
      case 0:
        return _buildSetupTab(context);
      case 1:
        return _buildBackendTab(context);
      case 2:
        return _buildChecklistTab(context);
      case 3:
        return _buildPinoutTab(context);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------
  // TAB 1: MACHINE PHYSICAL SETUP
  // ---------------------------------------------------------
  Widget _buildSetupTab(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNoticeBox(
          context,
          icon: Icons.electric_bolt_rounded,
          color: c.warning,
          title: 'Critical Electrical Step: Verify Both Buck Converters First',
          message:
              'Before powering the controller, confirm with a multimeter: Right LM2596S Buck = 5.0V DC (ESP32 V5/VIN) and Left LM2596S Buck = 7.4V DC (DS-S020A-C 30kg Servo). Never feed 12V into ESP32 or 5V into the DS3231 RTC (3V3 only).',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '1. Solar & Dual-Buck Power Subsystem'),
        _buildGuideTile(
          context,
          icon: Icons.solar_power_rounded,
          title: '12V Solar Panel, PWM Controller & 3S Lithium Pack',
          desc:
              'Connect the 12V solar panel and ZENOVA 12V 12Ah 3S Lithium battery (8.4V–12.6V with built-in BMS) to the PWM Solar Charge Controller (configured to 3S Lithium 12.6V profile). Two isolated LM2596S bucks step 12V down to 7.4V (servo) and 5.0V (ESP32) to prevent brownout resets.',
        ),
        _buildGuideTile(
          context,
          icon: Icons.power_rounded,
          title: 'Common Ground Rule',
          desc:
              'All modules (ESP32, DS-S020A-C Servo, HX711, DS3231 RTC, both LM2596S bucks, and 12V battery) MUST share one common Ground (GND). Floating grounds cause servo jitter and unstable sensor signals.',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '2. Dispenser Gate & High-Torque Actuator'),
        _buildGuideTile(
          context,
          icon: Icons.precision_manufacturing_rounded,
          title: 'DS-S020A-C 30kg Digital Servo (GPIO 18)',
          desc:
              'Driven with continuous 16-bit 50 Hz PWM on GPIO 18 and powered from the dedicated 7.4V Left LM2596S buck rail. Calibrated gate geometry: 30° actively held Closed directly under the hopper pipe, 0° Full Open using smooth 5° step ramping (14 ms/step).',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '3. Real-Time Clock, Scale & Timed Output'),
        _buildGuideTile(
          context,
          icon: Icons.schedule_rounded,
          title: 'ZS-042 DS3231 I2C RTC + CR2032 (GPIO 25 / 26 @ 3V3)',
          desc:
              'Wired to SDA = GPIO 25, SCL = GPIO 26, VCC = 3V3 (never 5V), and GND. Keeps exact Philippine Standard Time (UTC+8) offline for autonomous schedules and drives the Daylight Solar indicator (6:00 AM–5:59 PM Charging, Nighttime Idle).',
        ),
        _buildGuideTile(
          context,
          icon: Icons.scale_rounded,
          title: 'HX711 Load Cell (GPIO 23 / 22 @ 3V3) & Time-Based Estimation',
          desc:
              'Wired to DOUT = GPIO 23 and SCK = GPIO 22 on 3V3. While the physical load cell is bypassed/uncalibrated, the app displays bench-tested weight ranges: 1s (550g - 600g), 2s (1kg - 1.1kg), 3s (1.1kg - 1.3kg), 4s (1.6kg - 1.9kg), and 5s (1.6kg - 2.3kg).',
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // TAB 2: BACKEND PROCESSES & DATA FLOW
  // ---------------------------------------------------------
  Widget _buildBackendTab(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNoticeBox(
          context,
          icon: Icons.cloud_done_rounded,
          color: c.brand,
          title: 'Decoupled Transport & Offline Simulation Layer',
          message:
              'The app switches seamlessly between Firebase Realtime Cloud and Direct Wi-Fi HTTP (SoftAP 192.168.4.1) in Settings, and also includes a frontend-only Offline Simulation / Test Mode to preview the UI without touching hardware or Firebase.',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '1. Communication Modes'),
        _buildTransportCard(
          context,
          badge: 'CLOUD 24/7',
          badgeColor: c.brand,
          title: 'Firebase Realtime Database (asia-southeast1)',
          desc:
              'The ESP32 automatically scans nearby 2.4 GHz networks/client hotspots (NVS + 4 configured slots), joins the strongest RSSI signal, syncs NTP time to DS3231, pushes /telemetry every 10s, polls /commands/dispense every 1.5s, and syncs /schedules every 30s.',
        ),
        const SizedBox(height: 10),
        _buildTransportCard(
          context,
          badge: 'OFF-GRID',
          badgeColor: c.solar,
          title: 'Direct Wi-Fi HTTP (SoftAP 192.168.4.1)',
          desc:
              'The ESP32 runs simultaneous WIFI_AP_STA mode and always broadcasts "SmartFeeder-AP" (Password: "chickens123", Ch 11). Connect directly to http://192.168.4.1 for zero-internet feeding, diagnostics, and wireless 2.4 GHz Wi-Fi provisioning.',
        ),
        const SizedBox(height: 10),
        _buildTransportCard(
          context,
          badge: 'PREVIEW',
          badgeColor: c.infoStrong,
          title: 'Offline Simulation / Test Mode (Frontend Only)',
          desc:
              'Toggle from Settings or tap "Simulate" on the offline banner to test kg/g formatting, manual dispensing, schedules, logs, CSV/Excel exports, and 1-second chicken cluck alerts completely locally with zero ESP32 or Firebase changes.',
        ),
        const SizedBox(height: 18),
        _buildSectionTitle(context, '2. Backend Data Contracts & Safety Flow'),
        _buildDataContractPod(
          context,
          title: 'Telemetry Stream (/telemetry)',
          desc:
              'ESP32 publishes lastHeartbeat, isSolarCharging (daylight 6 AM–6 PM UTC+8 from DS3231), status ("idle", "dispensing", "error"), currentWeightGrams (HX711), and nominal defaults for bypassed sensors (HC-SR04 & Battery ADC).',
        ),
        const SizedBox(height: 8),
        _buildDataContractPod(
          context,
          title: 'Pre-Actuation Command Consumption (/commands/dispense & /stop)',
          desc:
              'When you tap "DISPENSE NOW", the phone fires a notification + 1s chicken cluck and writes /commands/dispense. The ESP32 DELETES the command and locks its ID in NVS flash BEFORE moving the gate (30° → 0° → 30°), then logs completion to /logs.',
        ),
        const SizedBox(height: 8),
        _buildDataContractPod(
          context,
          title: 'Offline Fail-Safe Routines (/schedules + DS3231 + NVS)',
          desc:
              'Up to 16 schedules are cached in ESP32 NVS flash. Every 5 seconds—online or completely offline—the ESP32 checks DS3231 UTC+8 time, locks the minute slot in NVS (lastSchSlot) to prevent double feeds, and dispenses automatically.',
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // TAB 3: COMMISSIONING CHECKLIST
  // ---------------------------------------------------------
  Widget _buildChecklistTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Step-by-Step Machine & Demo Setup'),
        const SizedBox(height: 6),
        _buildChecklistStep(
          context,
          step: '1',
          title: 'Dual Buck & Solar Power Check',
          desc:
              'Switch on the ZENOVA 12V 3S Lithium pack. Confirm PWM Solar Controller shows 12.6V 3S Lithium mode and verify buck outputs with a multimeter: Right Buck = 5.0V (ESP32), Left Buck = 7.4V (30kg Servo).',
        ),
        _buildChecklistStep(
          context,
          step: '2',
          title: 'Start 2.4 GHz Hotspot / Router & Verify Auto-Connect',
          desc:
              'Turn on your configured 2.4 GHz Wi-Fi or client phone hotspot (on iPhone, enable "Maximize Compatibility"). Power the ESP32; it locks the gate closed at 30° on boot and auto-connects to the strongest saved 2.4 GHz signal. Or connect to "SmartFeeder-AP" (chickens123) to provision Wi-Fi.',
        ),
        _buildChecklistStep(
          context,
          step: '3',
          title: 'Verify Online Status (or Use Offline Simulation)',
          desc:
              'Open Settings › Hardware Transport and confirm "Firebase Realtime Cloud" (or "Direct Wi-Fi HTTP" off-grid). Confirm the green "Online" badge appears on Dashboard—or tap "Simulate" to test UI flows offline.',
        ),
        _buildChecklistStep(
          context,
          step: '4',
          title: 'Run a Quick 1s (550g - 600g) Gate & Audio Test',
          desc:
              'From Dashboard, select 1s (550g - 600g) and tap DISPENSE 1s NOW. Confirm the servo smoothly sweeps 30° → 0° → 30° on the exact second and your phone plays the 1-second chicken cluck notification.',
        ),
        _buildChecklistStep(
          context,
          step: '5',
          title: 'Program Schedules & Inspect Estimated Logs',
          desc:
              'Add daily routines in the Schedules tab: 1s (550g - 600g), 2s (1kg - 1.1kg), 3s (1.1kg - 1.3kg), 4s (1.6kg - 1.9kg), or 5s (1.6kg - 2.3kg). Open History & Logs to verify matching Target/Dispensed ranges and export CSV or Excel reports.',
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // TAB 4: WIRING & PINOUT TABLE
  // ---------------------------------------------------------
  Widget _buildPinoutTab(BuildContext context) {
    final c = context.colors;
    final pinoutRows = [
      ('Servo PWM (DS-S020A-C 30kg)', 'GPIO 18', '7.4V Left Buck & Common GND', true),
      ('HX711 DT (Data)', 'GPIO 23', '3V3 & GND', true),
      ('HX711 SCK (Clock)', 'GPIO 22', '3V3 & GND', true),
      ('DS3231 RTC SDA (I2C)', 'GPIO 25', '3V3 & GND (Never 5V)', true),
      ('DS3231 RTC SCL (I2C)', 'GPIO 26', '3V3 & GND (Never 5V)', true),
      ('ESP32 Logic Power', 'V5 / GND', '5.0V Right Buck & Common GND', true),
      ('HC-SR04 Ultrasonic', 'Bypassed', 'Reserved GPIO 5 / 19 (Not Connected)', false),
      ('Battery Voltage ADC', 'Bypassed', 'Reserved GPIO 34 (Not Connected)', false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNoticeBox(
          context,
          icon: Icons.info_outline_rounded,
          color: c.info,
          title: 'Target Controller: ESP32 Dual-Core 38-Pin (Yellow Header)',
          message:
              'All active GPIO assignments match the finalized 38-Pin Yellow Header wiring and firmware/include/config.h flags (HAS_RTC_DS3231 = 1, SERVO_CLOSED_DEG = 30, SERVO_OPEN_DEG = 0).',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'ESP32 Hardware Pin Connections'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: c.surfaceMuted.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('Module / Function', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.textPrimary)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('ESP32 Pin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.brand)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('Power Rail', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.textSecondary)),
                    ),
                  ],
                ),
              ),
              ...pinoutRows.asMap().entries.map((entry) {
                final idx = entry.key;
                final row = entry.value;
                final isEven = idx % 2 == 0;
                final isActive = row.$4;
                return Container(
                  color: isEven ? c.surface.withValues(alpha: 0.5) : c.surfaceMuted.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(row.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive ? c.brandSoft : c.surfaceMuted,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isActive ? c.brand.withValues(alpha: 0.25) : c.border.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            row.$2,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isActive ? c.brand : c.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 3,
                        child: Text(row.$3, style: TextStyle(fontSize: 11, color: c.textMuted)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // HELPER WIDGETS
  // ---------------------------------------------------------
  Widget _buildSectionTitle(BuildContext context, String title) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildNoticeBox(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: c.brand, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportCard(
    BuildContext context, {
    required String badge,
    required Color badgeColor,
    required String title,
    required String desc,
  }) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildDataContractPod(
    BuildContext context, {
    required String title,
    required String desc,
  }) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, fontFamily: 'monospace', color: c.brand),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistStep(
    BuildContext context, {
    required String step,
    required String title,
    required String desc,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brand,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.brand.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              step,
              style: TextStyle(color: c.onBrand, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
