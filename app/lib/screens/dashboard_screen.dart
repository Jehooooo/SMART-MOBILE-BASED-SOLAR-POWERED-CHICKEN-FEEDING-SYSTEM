import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../services/settings_service.dart';
import '../models/telemetry.dart';
import '../models/schedule.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/skeleton.dart';
import '../widgets/hardware_guide_dialog.dart';
import '../widgets/app_logo.dart';

export '../widgets/hardware_guide_dialog.dart' show showHardwareGuideDialog;

class DashboardScreen extends StatefulWidget {
  final FeederService feederService;
  final SettingsService settingsService;

  const DashboardScreen({super.key, required this.feederService, required this.settingsService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedDurationSeconds = 5;

  SettingsService get _settings => widget.settingsService;

  String _getTimeUntilNextFeed(FeedingSchedule? nextSch) {
    if (nextSch == null) return 'No active schedule';
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, nextSch.hour, nextSch.minute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    final diff = target.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours == 0) {
      return 'in $minutes min${minutes == 1 ? '' : 's'}';
    }
    return 'in ${hours}h ${minutes}m';
  }

  String _getHopperEstimatedDays(double feedPercent, double dailyTarget) {
    final totalCapacityGrams = _settings.hopperCapacityKg * 1000.0; // Hopper capacity from Settings
    final remainingGrams = (feedPercent / 100.0) * totalCapacityGrams;
    if (dailyTarget <= 0) return '~${(remainingGrams / 1000.0).toStringAsFixed(1)} kg available';
    final days = remainingGrams / dailyTarget;
    return '~${days.toStringAsFixed(1)} days left';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.feederService, _settings]),
      builder: (context, _) {
        final c = context.colors;
        final telemetry = widget.feederService.telemetry;
        final nextSch = widget.feederService.nextSchedule;
        final isDispensing = widget.feederService.isDispensing;
        final dailyTarget = widget.feederService.totalDailyTargetGrams;
        final connection = widget.feederService.connection;
        final isLoading = widget.feederService.isInitialLoading;
        final isOnline = widget.feederService.isConnected && telemetry.isOnline;

        final String chipLabel;
        final Color chipDot;
        if (isDispensing) {
          chipLabel = 'Dispensing';
          chipDot = c.manual;
        } else if (connection == FeederConnection.connecting) {
          chipLabel = 'Connecting';
          chipDot = c.info;
        } else if (isOnline) {
          chipLabel = 'Online';
          chipDot = c.success;
        } else {
          chipLabel = 'Offline';
          chipDot = c.danger;
        }

        return Scaffold(
          appBar: AppBar(
            leadingWidth: 54,
            leading: const Padding(
              padding: EdgeInsets.only(left: 14.0),
              child: Center(
                child: AppLogo(size: 34, borderWidth: 1.8),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Chicken Feeder',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${_settings.feederName} • Solar-Powered',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: widget.feederService.isMock
                          ? 'Operating in simulated mock mode for pre-fabrication testing'
                          : 'Connected to physical ESP32 hardware',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.feederService.isMock ? c.manualSoft : c.brandSoft,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.feederService.isMock ? c.manual.withValues(alpha: 0.4) : c.brandBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          widget.feederService.isMock ? 'SIMULATOR' : 'LIVE HW',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: widget.feederService.isMock ? c.manual : c.brand,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.info_outline, color: c.brand),
                tooltip: 'System & Hardware Info',
                onPressed: () => showHardwareGuideDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Sync Feeder Telemetry',
                onPressed: isLoading
                    ? null
                    : () async {
                        final ok = await widget.feederService.refreshTelemetry();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'Telemetry refreshed from hardware controller'
                                  : 'Could not reach the feeder. Showing last known data.'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Tooltip(
                  message: isOnline
                      ? (widget.feederService.isMock
                          ? 'Simulator: Online emulation active'
                          : 'Feeder is online and connected via 2.4GHz Wi-Fi')
                      : (widget.feederService.isMock
                          ? 'Feeder is offline (Development Default). Tap to toggle online simulation.'
                          : 'Feeder is offline. Check solar battery and Wi-Fi signal.'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: widget.feederService.isMock
                        ? () => _showSimulatorConnectionSheet(context)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.border.withValues(alpha: 0.8)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: chipDot,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: chipDot.withValues(alpha: 0.45),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            chipLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              ConnectionBanner(feederService: widget.feederService),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isLoading
                      ? const DashboardSkeleton(key: ValueKey('dash-skeleton'))
                      : KeyedSubtree(
                          key: const ValueKey('dash-content'),
                          child: _buildContent(telemetry, nextSch, isDispensing, dailyTarget, isOnline),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(
    FeederTelemetry telemetry,
    FeedingSchedule? nextSch,
    bool isDispensing,
    double dailyTarget,
    bool isOnline,
  ) {
    final c = context.colors;
    return RefreshIndicator(
      onRefresh: () => widget.feederService.refreshTelemetry(),
      color: c.brand,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 768;

          final metricsRow = Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.solar_power,
                  iconColor: c.solar,
                  title: 'Solar System',
                  value: telemetry.isSolarCharging ? 'Charging' : 'Idle',
                  subtitle: '12V Solar Panel',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.battery_charging_full,
                  iconColor: telemetry.batteryPercent > _settings.lowBatteryThreshold + 10 ? c.success : c.danger,
                  title: 'Battery Level',
                  value: '${telemetry.batteryPercent}%',
                  subtitle: '${telemetry.batteryVolts.toStringAsFixed(1)} Volts',
                ),
              ),
            ],
          );

          if (isWide) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._buildStatusBanners(telemetry, isDispensing),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                _buildHopperCard(telemetry, dailyTarget),
                                const SizedBox(height: 16),
                                metricsRow,
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                _buildNextScheduleCard(nextSch),
                                const SizedBox(height: 16),
                                _buildManualFeedSection(isDispensing, telemetry, isOnline),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Mobile Single Column View
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Status Alert Banners
                ..._buildStatusBanners(telemetry, isDispensing),

                const SizedBox(height: 8),

                // Hopper Feed Level Card
                _buildHopperCard(telemetry, dailyTarget),

                const SizedBox(height: 16),

                // Solar & Battery Metrics Row
                metricsRow,

                const SizedBox(height: 16),

                // Next Scheduled Feeding Card
                _buildNextScheduleCard(nextSch),

                const SizedBox(height: 20),

                // Manual Feeding Section
                _buildManualFeedSection(isDispensing, telemetry, isOnline),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildStatusBanners(FeederTelemetry telemetry, bool isDispensing) {
    final c = context.colors;
    final lowFeed = _settings.lowFeedThreshold;
    final lowBattery = _settings.lowBatteryThreshold;
    if (isDispensing) return [_buildDispensingBanner(telemetry)];
    if (telemetry.feedLevelPercent < lowFeed) {
      return [
        _buildWarningBanner(
          'Low Feed Warning: Hopper below ${lowFeed.toInt()}% capacity. Refill feed pellets to ensure regular feeding routines.',
          c.warning,
        ),
      ];
    }
    if (telemetry.batteryPercent < lowBattery) {
      return [
        _buildWarningBanner(
          'Low Battery Warning: Battery below ${lowBattery.toInt()}%. Verify solar panel orientation and sun exposure.',
          c.danger,
        ),
      ];
    }
    return const [];
  }

  Widget _buildWarningBanner(String message, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispensingBanner(FeederTelemetry telemetry) {
    final c = context.colors;
    final estimatedTargetGrams = _selectedDurationSeconds * 20.0;
    final progress = (estimatedTargetGrams > 0)
        ? (telemetry.currentWeightGrams / estimatedTargetGrams).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.infoSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.infoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: c.info),
              ),
              const SizedBox(width: 10),
              Text(
                'Dispensing in Progress...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.infoStrong),
              ),
              const Spacer(),
              Text(
                '${telemetry.currentWeightGrams.toStringAsFixed(1)}g / ~${estimatedTargetGrams.toInt()}g (${_selectedDurationSeconds}s)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.infoStrong),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: c.infoBorder.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation<Color>(c.info),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Motor active • Scale monitoring',
                style: TextStyle(fontSize: 12, color: c.info),
              ),
              TextButton.icon(
                onPressed: () => widget.feederService.cancelDispensing(),
                icon: Icon(Icons.stop_circle, size: 16, color: c.danger),
                label: Text('Emergency Stop', style: TextStyle(color: c.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHopperCard(FeederTelemetry telemetry, double dailyTarget) {
    final c = context.colors;
    final pct = telemetry.feedLevelPercent;
    final lowFeed = _settings.lowFeedThreshold;
    final capacityKg = _settings.hopperCapacityKg;
    final color = pct > lowFeed * 2 ? c.brand : (pct > lowFeed ? c.warning : c.danger);
    final remainingKg = ((pct / 100.0) * capacityKg).clamp(0.0, capacityKg);
    final daysSupplyText = _getHopperEstimatedDays(pct, dailyTarget);

    return Card(
      child: Padding(
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.inventory_2_outlined, color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Feed Hopper Level',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              'Telemetry Source: HC-SR04 Ultrasonic Sensor',
                              style: TextStyle(fontSize: 11, color: c.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (pct / 100.0).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 16,
                  backgroundColor: c.track,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.border.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    '~${remainingKg.toStringAsFixed(2)} kg remaining (of ${capacityKg.toStringAsFixed(1)} kg)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    daysSupplyText,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.brand),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.textPrimary),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextScheduleCard(FeedingSchedule? nextSch) {
    final c = context.colors;
    final countdown = _getTimeUntilNextFeed(nextSch);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.alarm_on_rounded, color: c.brand, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Next Automated Feeding',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMuted),
                        ),
                      ),
                      if (nextSch != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.brandSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: c.brandBorder.withValues(alpha: 0.8)),
                          ),
                          child: Text(
                            countdown,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.brand),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nextSch != null ? '${nextSch.label} at ${nextSch.timeFormatted}' : 'No active automated schedules',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.textPrimary),
                  ),
                ],
              ),
            ),
            if (nextSch != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${nextSch.targetGrams.toInt()}g',
                  style: TextStyle(color: c.brand, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualFeedSection(bool isDispensing, FeederTelemetry telemetry, bool isOnline) {
    final c = context.colors;
    final bool isHopperEmpty = telemetry.feedLevelPercent < 5;
    final bool isOffline = !isOnline;
    final bool canDispense = !isDispensing && !isHopperEmpty && !isOffline;

    final durationOptions = [
      {'seconds': 3, 'name': '3s', 'desc': 'Quick (~60g)'},
      {'seconds': 5, 'name': '5s', 'desc': 'Half (~100g)'},
      {'seconds': 10, 'name': '10s', 'desc': 'Standard (~200g)'},
      {'seconds': 15, 'name': '15s', 'desc': 'Full (~300g)'},
    ];

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.brandBorder.withValues(alpha: 0.8), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Manual Feed Trigger',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.brandSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.brandBorder.withValues(alpha: 0.8)),
                  ),
                  child: Text(
                    'Selected: ${_selectedDurationSeconds}s (~${_selectedDurationSeconds * 20}g)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.brand),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select standard feed duration or fine-tune with the slider below:',
              style: TextStyle(fontSize: 13, color: c.textMuted),
            ),
            const SizedBox(height: 14),

            // Duration Preset Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: durationOptions.map((opt) {
                final seconds = opt['seconds'] as int;
                final isSelected = _selectedDurationSeconds == seconds;
                return ChoiceChip(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(opt['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        opt['desc'] as String,
                        style: TextStyle(fontSize: 10, color: isSelected ? c.onBrand.withValues(alpha: 0.85) : c.textMuted),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: isDispensing ? null : (selected) {
                    if (selected) setState(() => _selectedDurationSeconds = seconds);
                  },
                  selectedColor: c.brand,
                  backgroundColor: c.surfaceMuted,
                  side: BorderSide(color: isSelected ? c.brand : c.border.withValues(alpha: 0.7)),
                  labelStyle: TextStyle(
                    color: isSelected ? c.onBrand : c.textPrimary,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // Fine-tune duration slider
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 16, color: c.textMuted),
                        const SizedBox(width: 6),
                        Text('Fine-tune Duration:', style: TextStyle(fontSize: 12, color: c.textMuted)),
                      ],
                    ),
                    Text('${_selectedDurationSeconds}s (~${_selectedDurationSeconds * 20}g)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: c.brand)),
                  ],
                ),
                Slider(
                  value: _selectedDurationSeconds.toDouble().clamp(1.0, 30.0),
                  min: 1.0,
                  max: 30.0,
                  divisions: 29,
                  activeColor: c.brand,
                  inactiveColor: c.track,
                  label: '${_selectedDurationSeconds}s',
                  onChanged: isDispensing ? null : (val) => setState(() => _selectedDurationSeconds = val.round()),
                ),
              ],
            ),

            if (isHopperEmpty)
              _buildBlockedReason(Icons.error_outline, 'Dispense blocked: Hopper is empty. Refill feed first.', c.danger)
            else if (isOffline && !isDispensing) ...[
              _buildBlockedReason(
                Icons.cloud_off_rounded,
                'Manual feeding is unavailable while the feeder is offline.',
                c.danger,
              ),
              if (widget.feederService.isMock)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => widget.feederService.setSimulatedOffline(false),
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text(
                        'Enable Online Simulator (Click to Test Dispensing)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.brand,
                        foregroundColor: c.onBrand,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 6),

            // Action Button (or Emergency Cancel if dispensing)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isDispensing
                  ? SizedBox(
                      key: const ValueKey('cancel'),
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => widget.feederService.cancelDispensing(),
                        icon: Icon(Icons.stop_circle_outlined, color: c.danger),
                        label: Text(
                          'CANCEL / EMERGENCY STOP',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.danger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.danger, width: 1.5),
                          backgroundColor: c.dangerSoft,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    )
                  : SizedBox(
                      key: const ValueKey('dispense'),
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: canDispense ? () => _confirmManualFeed(context) : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          'DISPENSE ${_selectedDurationSeconds}s NOW',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.brand,
                          foregroundColor: c.onBrand,
                          disabledBackgroundColor: c.track,
                          disabledForegroundColor: c.textMuted,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedReason(IconData icon, String message, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmManualFeed(BuildContext context) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.touch_app, color: c.brand),
            const SizedBox(width: 8),
            const Text('Confirm Manual Feed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to run the feeder dispenser for $_selectedDurationSeconds seconds directly into the feeding trough.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: c.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The dispenser gate/auger motor will run for $_selectedDurationSeconds seconds (dispenses approx. ${_selectedDurationSeconds * 20}g).',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: c.brand,
                  content: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Transmitting dispense command (${_selectedDurationSeconds}s) to feeder...',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
              final success = await widget.feederService.triggerManualFeed(
                durationSeconds: _selectedDurationSeconds,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: success ? c.brand : c.danger,
                    content: Text(
                      success
                          ? 'Dispense command executed successfully! Scale weight and feeding log updated.'
                          : 'Dispense failed or feeder is offline. Check hardware connection.',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirm & Dispense'),
          ),
        ],
      ),
    );
  }

  void _showSimulatorConnectionSheet(BuildContext context) {
    final c = context.colors;
    final feeder = widget.feederService;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isSimOffline = feeder.isSimulatingOffline;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isSimOffline ? c.dangerSoft : c.brandSoft,
                          child: Icon(
                            isSimOffline ? Icons.cloud_off : Icons.cloud_done,
                            color: isSimOffline ? c.danger : c.brand,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hardware Simulator',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.textPrimary),
                              ),
                              Text(
                                isSimOffline
                                    ? 'Offline (Development Default)'
                                    : 'Simulating Live Hardware Connection',
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Because the physical feeder is still in development, the app defaults to Offline. You can toggle simulated online telemetry below to test dispensing.',
                      style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Simulate Online Feeder',
                        style: TextStyle(fontWeight: FontWeight.bold, color: c.textPrimary),
                      ),
                      subtitle: Text(
                        isSimOffline
                            ? 'Toggle ON to test dispensing and live telemetry'
                            : 'Toggle OFF to return to offline development default',
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                      value: !isSimOffline,
                      onChanged: (val) {
                        feeder.setSimulatedOffline(!val);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
