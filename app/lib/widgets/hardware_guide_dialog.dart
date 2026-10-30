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
                        'ESP32 DevKit V1 • 12V Solar • FreeRTOS Firmware',
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
          title: 'Critical Electrical Step: Check 5V Before Connecting ESP32',
          message:
              'Adjust the brass screw on the LM2596 buck converter using a multimeter until it reads exactly 5.0V. Never plug 12V directly into the ESP32 VIN or servo, or the board will be permanently damaged.',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '1. Power & Solar Subsystem Assembly'),
        _buildGuideTile(
          context,
          icon: Icons.solar_power_rounded,
          title: '12V Solar Panel to Charge Controller',
          desc:
              'Connect the monocrystalline solar panel to the Solar Charge Controller input. Connect the 12V Lead-Acid or LiFePO4 battery to the battery terminals. Verify the charge controller status LED illuminates.',
        ),
        _buildGuideTile(
          context,
          icon: Icons.power_rounded,
          title: 'Common Ground Rule',
          desc:
              'All components (ESP32, Servo, HX711, HC-SR04, Buck Converter, and Battery) MUST share a common Ground (GND). Separated grounds will cause severe servo jitter and fluctuating sensor readings.',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '2. Dispenser & Actuator Assembly'),
        _buildGuideTile(
          context,
          icon: Icons.precision_manufacturing_rounded,
          title: 'Dispensing Gate & MG996R High-Torque Servo',
          desc:
              'Mount the servo to the hopper output slide (0° closed, 90° open). Power the servo directly from the 5V buck converter power rail with a 1000µF 16V capacitor across 5V and GND to suppress brownout resets.',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '3. Sensor Calibration & Bring-Up'),
        _buildGuideTile(
          context,
          icon: Icons.scale_rounded,
          title: 'HX711 Load Cell Weighing Tray',
          desc:
              'Mount the feed tray onto the load cell bar. Ensure the tray does NOT touch the coop frame. In the mobile app Settings, tap "Tare Scale (0.0g)". Test with a known 500g bottle to verify portion accuracy.',
        ),
        _buildGuideTile(
          context,
          icon: Icons.sensors_rounded,
          title: 'HC-SR04 Ultrasonic Hopper Depth Sensor',
          desc:
              'Mount the sensor inside the top lid facing perpendicular down to pellets. Measure the physical height: empty hopper = 30 cm, full hopper = 5 cm. Ensure a 1kΩ/2kΩ divider is installed on the ECHO pin to protect ESP32 3.3V logic.',
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
          title: 'Decoupled Hardware Integration Layer',
          message:
              'The mobile application communicates through the FeederHardwareAdapter. You can select between Firebase Realtime Cloud and Direct Wi-Fi HTTP (SoftAP) at any time in Settings.',
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context, '1. Communication Transports'),
        _buildTransportCard(
          context,
          badge: 'CLOUD 24/7',
          badgeColor: c.brand,
          title: 'Firebase Realtime Database (ESP32 Cloud)',
          desc:
              'The ESP32 connects to 2.4 GHz farm Wi-Fi and pushes telemetry to Firebase every 2–10 seconds. Allows you to monitor feed levels and trigger dispenses from anywhere across mobile LTE/4G.',
        ),
        const SizedBox(height: 10),
        _buildTransportCard(
          context,
          badge: 'OFF-GRID',
          badgeColor: c.solar,
          title: 'Local Farm Wi-Fi HTTP (SoftAP)',
          desc:
              'For remote farms without internet. The ESP32 broadcasts a local hotspot (SSID: "PoultryFeeder-AP"). Connect your phone directly to Wi-Fi at http://192.168.4.1 for zero-internet controls.',
        ),
        const SizedBox(height: 18),
        _buildSectionTitle(context, '2. Backend Data Contracts & Queues'),
        _buildDataContractPod(
          context,
          title: 'Telemetry Stream (/feeder/telemetry)',
          desc:
              'ESP32 periodically publishes: feedLevelPercent (HC-SR04), batteryVolts (GPIO 34 ADC), currentWeightGrams (HX711), status ("idle", "dispensing", "lowFeed"), and isSolarCharging.',
        ),
        const SizedBox(height: 8),
        _buildDataContractPod(
          context,
          title: 'Command Ingestion Queue (/feeder/command)',
          desc:
              'When you tap "DISPENSE NOW", the app pushes {action: "DISPENSE", durationSeconds: 5, targetGrams: 100}. The ESP32 listens via WebSocket stream, executes the servo gate, and records actual grams.',
        ),
        const SizedBox(height: 8),
        _buildDataContractPod(
          context,
          title: 'Offline Fail-Safe Routine (DS3231 RTC)',
          desc:
              'Feeding schedules configured in the app are synchronized to the ESP32\'s non-volatile EEPROM. Even if the farm Wi-Fi or phone goes offline, the DS3231 battery-backed clock triggers scheduled feeds automatically.',
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
        _buildSectionTitle(context, 'Step-by-Step Machine Commissioning'),
        const SizedBox(height: 6),
        _buildChecklistStep(
          context,
          step: '1',
          title: 'Power Verification & Multimeter Check',
          desc:
              'Turn on battery switch. Use digital multimeter on buck converter output to confirm strictly 5.0V. Inspect Solar Charge Controller indicator LED.',
        ),
        _buildChecklistStep(
          context,
          step: '2',
          title: 'Flash ESP32 Firmware',
          desc:
              'Open the Arduino sketch in /firmware. Update your 2.4 GHz Wi-Fi SSID, password, and Firebase database credentials in config.h. Flash via USB at 115200 baud.',
        ),
        _buildChecklistStep(
          context,
          step: '3',
          title: 'Select Transport in Mobile App',
          desc:
              'Open Settings › Feeder Device & Hardware › Hardware Transport. Select "Firebase Realtime Cloud" (or Local Wi-Fi HTTP if off-grid). Confirm green "ONLINE" chip appears on Dashboard.',
        ),
        _buildChecklistStep(
          context,
          step: '4',
          title: 'Zero / Tare the Scale & Test Dispense',
          desc:
              'Ensure feed tray is empty and clear of obstructions. Tap "Zero / Tare Scale Sensor" in Settings. Then from Dashboard, trigger a short 2-second test feed to verify gate opens and closes smoothly.',
        ),
        _buildChecklistStep(
          context,
          step: '5',
          title: 'Fill Hopper & Program Routines',
          desc:
              'Fill hopper with poultry feed pellets. Confirm Hopper Level on Dashboard reads near 100%. Open Feeding Schedules tab and set your automated feeding times (e.g. 7:00 AM, 12:00 PM, 4:30 PM).',
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
      ('Servo PWM (Gate)', 'GPIO 13', '5V Buck Rail & GND', 'MG996R high-torque metal gear servo'),
      ('HX711 DOUT (Data)', 'GPIO 16', '5V & GND', 'Load cell scale amplifier output'),
      ('HX711 SCK (Clock)', 'GPIO 17', '5V & GND', 'Serial clock signal from ESP32'),
      ('HC-SR04 TRIG', 'GPIO 5', '5V & GND', 'Ultrasonic trigger pulse'),
      ('HC-SR04 ECHO', 'GPIO 18', '3.3V safe (divider)', 'Requires 1kΩ/2kΩ divider before ESP32'),
      ('DS3231 SDA (I2C)', 'GPIO 21', '3.3V & GND', 'Real-Time Clock data (CR2032 backed)'),
      ('DS3231 SCL (I2C)', 'GPIO 22', '3.3V & GND', 'Real-Time Clock I2C clock'),
      ('Battery ADC', 'GPIO 34', 'Analog Input', 'Midpoint of 40kΩ & 10kΩ divider on 12V battery'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNoticeBox(
          context,
          icon: Icons.info_outline_rounded,
          color: c.info,
          title: 'Target Controller: ESP32 DevKit V1 (30-Pin)',
          message:
              'All GPIO assignments are pre-configured in the mobile app\'s data contracts and the /firmware source files. Refer to the table below during soldering and breadboarding.',
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
                            color: c.brandSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            row.$2,
                            style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: c.brand),
                          ),
                        ),
                      ),
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
