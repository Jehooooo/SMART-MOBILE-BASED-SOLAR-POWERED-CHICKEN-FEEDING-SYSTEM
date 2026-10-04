import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../models/telemetry.dart';
import '../models/schedule.dart';

class DashboardScreen extends StatefulWidget {
  final FeederService feederService;

  const DashboardScreen({super.key, required this.feederService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _selectedPortionGrams = 150.0;

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
    const totalCapacityGrams = 5000.0; // 5 kg hopper
    final remainingGrams = (feedPercent / 100.0) * totalCapacityGrams;
    if (dailyTarget <= 0) return '~${(remainingGrams / 1000.0).toStringAsFixed(1)} kg available';
    final days = remainingGrams / dailyTarget;
    return '~${days.toStringAsFixed(1)} days left';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.feederService,
      builder: (context, _) {
        final telemetry = widget.feederService.telemetry;
        final nextSch = widget.feederService.nextSchedule;
        final isDispensing = widget.feederService.isDispensing;
        final dailyTarget = widget.feederService.totalDailyTargetGrams;

        return Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Chicken Feeder',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  'Solar-Powered • Automated Dispenser',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: Color(0xFF0F766E)),
                tooltip: 'System & Hardware Info',
                onPressed: () => _showSystemInfoDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Sync Feeder Telemetry',
                onPressed: () async {
                  await widget.feederService.refreshTelemetry();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Telemetry refreshed from hardware controller'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Tooltip(
                  message: telemetry.isOnline
                      ? 'Feeder is online and connected via 2.4GHz Wi-Fi'
                      : 'Feeder is offline. Check solar battery and Wi-Fi signal.',
                  child: Chip(
                    avatar: CircleAvatar(
                      backgroundColor: isDispensing
                          ? Colors.orange
                          : (telemetry.isOnline ? const Color(0xFF10B981) : Colors.red),
                      radius: 5,
                    ),
                    label: Text(
                      isDispensing ? 'Dispensing' : (telemetry.isOnline ? 'Online' : 'Offline'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: Colors.grey.shade100,
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => widget.feederService.refreshTelemetry(),
            color: const Color(0xFF0F766E),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 768;

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
                            if (isDispensing)
                              _buildDispensingBanner(telemetry)
                            else if (telemetry.feedLevelPercent < 20)
                              _buildWarningBanner(
                                'Low Feed Warning: Hopper below 20% capacity. Refill feed pellets to ensure regular feeding routines.',
                                Colors.amber.shade800,
                              )
                            else if (telemetry.batteryPercent < 20)
                              _buildWarningBanner(
                                'Low Battery Warning: Battery below 20%. Verify solar panel orientation and sun exposure.',
                                Colors.red.shade700,
                              ),
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
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildMetricTile(
                                              icon: Icons.solar_power,
                                              iconColor: Colors.amber.shade700,
                                              title: 'Solar System',
                                              value: telemetry.isSolarCharging ? 'Charging' : 'Idle',
                                              subtitle: '12V Solar Panel',
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildMetricTile(
                                              icon: Icons.battery_charging_full,
                                              iconColor: telemetry.batteryPercent > 30 ? Colors.green : Colors.red,
                                              title: 'Battery Level',
                                              value: '${telemetry.batteryPercent}%',
                                              subtitle: '${telemetry.batteryVolts.toStringAsFixed(1)} Volts',
                                            ),
                                          ),
                                        ],
                                      ),
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
                                      _buildManualFeedSection(isDispensing, telemetry),
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
                      if (isDispensing)
                        _buildDispensingBanner(telemetry)
                      else if (telemetry.feedLevelPercent < 20)
                        _buildWarningBanner(
                          'Low Feed Warning: Hopper below 20% capacity. Refill feed pellets to ensure regular feeding routines.',
                          Colors.amber.shade800,
                        )
                      else if (telemetry.batteryPercent < 20)
                        _buildWarningBanner(
                          'Low Battery Warning: Battery below 20%. Verify solar panel orientation and sun exposure.',
                          Colors.red.shade700,
                        ),

                      const SizedBox(height: 8),

                      // Hopper Feed Level Card
                      _buildHopperCard(telemetry, dailyTarget),

                      const SizedBox(height: 16),

                      // Solar & Battery Metrics Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.solar_power,
                              iconColor: Colors.amber.shade700,
                              title: 'Solar System',
                              value: telemetry.isSolarCharging ? 'Charging' : 'Idle',
                              subtitle: '12V Solar Panel',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.battery_charging_full,
                              iconColor: telemetry.batteryPercent > 30 ? Colors.green : Colors.red,
                              title: 'Battery Level',
                              value: '${telemetry.batteryPercent}%',
                              subtitle: '${telemetry.batteryVolts.toStringAsFixed(1)} Volts',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Next Scheduled Feeding Card
                      _buildNextScheduleCard(nextSch),

                      const SizedBox(height: 20),

                      // Manual Feeding Section
                      _buildManualFeedSection(isDispensing, telemetry),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
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
    final progress = (_selectedPortionGrams > 0)
        ? (telemetry.currentWeightGrams / _selectedPortionGrams).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 10),
              const Text(
                'Dispensing in Progress...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E40AF)),
              ),
              const Spacer(),
              Text(
                '${telemetry.currentWeightGrams.toStringAsFixed(1)}g / ${_selectedPortionGrams.toInt()}g',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E40AF)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFDBEAFE),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Motor active • Scale monitoring',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
              TextButton.icon(
                onPressed: () => widget.feederService.cancelDispensing(),
                icon: const Icon(Icons.stop_circle, size: 16, color: Colors.red),
                label: const Text('Emergency Stop', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
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
    final pct = telemetry.feedLevelPercent;
    final color = pct > 40 ? const Color(0xFF0F766E) : (pct > 20 ? Colors.amber.shade700 : Colors.red.shade700);
    final remainingKg = ((pct / 100.0) * 5.0).clamp(0.0, 5.0);
    final daysSupplyText = _getHopperEstimatedDays(pct, dailyTarget);

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory_2_outlined, color: color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Feed Hopper Level',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pct / 100.0).clamp(0.0, 1.0),
                minHeight: 18,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 6,
                  child: Text(
                    '~${remainingKg.toStringAsFixed(2)} kg remaining (of 5.0 kg)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 4,
                  child: Text(
                    daysSupplyText,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.teal.shade800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Telemetry Source: HC-SR04 Ultrasonic Sensor',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildNextScheduleCard(FeedingSchedule? nextSch) {
    final countdown = _getTimeUntilNextFeed(nextSch);

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFCCFBF1),
              radius: 22,
              child: const Icon(Icons.alarm_on_rounded, color: Color(0xFF0F766E), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Next Automated Feeding',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                        ),
                      ),
                      if (nextSch != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            countdown,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    nextSch != null ? '${nextSch.label} at ${nextSch.timeFormatted}' : 'No active automated schedules',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ),
            if (nextSch != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${nextSch.targetGrams.toInt()}g',
                  style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualFeedSection(bool isDispensing, FeederTelemetry telemetry) {
    final bool isHopperEmpty = telemetry.feedLevelPercent < 5;
    final bool isOffline = !telemetry.isOnline;
    final bool canDispense = !isDispensing && !isHopperEmpty && !isOffline;

    final portionOptions = [
      {'grams': 50.0, 'name': '50g', 'desc': 'Snack'},
      {'grams': 100.0, 'name': '100g', 'desc': 'Half'},
      {'grams': 150.0, 'name': '150g', 'desc': 'Standard'},
      {'grams': 200.0, 'name': '200g', 'desc': 'Full'},
    ];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF99F6E4), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Manual Feed Trigger',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF99F6E4)),
                  ),
                  child: Text(
                    'Selected: ${_selectedPortionGrams.toInt()}g',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select standard flock portion or fine-tune with the slider below:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),

            // Portion Preset Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: portionOptions.map((opt) {
                final grams = opt['grams'] as double;
                final isSelected = _selectedPortionGrams == grams;
                return ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(opt['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(opt['desc'] as String, style: TextStyle(fontSize: 10, color: isSelected ? Colors.white70 : Colors.grey.shade600)),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: isDispensing ? null : (selected) {
                    if (selected) setState(() => _selectedPortionGrams = grams);
                  },
                  selectedColor: const Color(0xFF0F766E),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF0F172A),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // Fine-tune portion slider
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.tune_rounded, size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 6),
                        Text('Fine-tune Portion:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                    Text('${_selectedPortionGrams.toInt()}g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F766E))),
                  ],
                ),
                Slider(
                  value: _selectedPortionGrams.clamp(20.0, 400.0),
                  min: 20.0,
                  max: 400.0,
                  divisions: 38,
                  activeColor: const Color(0xFF0F766E),
                  onChanged: isDispensing ? null : (val) => setState(() => _selectedPortionGrams = val.roundToDouble()),
                ),
              ],
            ),

            if (isHopperEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Dispense blocked: Hopper is empty. Refill feed first.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 6),

            // Action Button (or Emergency Cancel if dispensing)
            if (isDispensing)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => widget.feederService.cancelDispensing(),
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                  label: const Text(
                    'CANCEL / EMERGENCY STOP',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    backgroundColor: Colors.red.shade50,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: canDispense ? () => _confirmManualFeed(context) : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'DISPENSE ${_selectedPortionGrams.toInt()}g NOW',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmManualFeed(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.touch_app, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Confirm Manual Feed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to dispense ${_selectedPortionGrams.toInt()} grams of poultry feed directly to the feeding trough.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFF0F766E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The auger motor will activate and verify target weight with the load cell scale.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
            onPressed: () {
              Navigator.pop(ctx);
              widget.feederService.triggerManualFeed(_selectedPortionGrams);
            },
            icon: const Icon(Icons.check),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm & Dispense'),
          ),
        ],
      ),
    );
  }

  void _showSystemInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('System & Hardware Guide'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGuideItem(
                title: 'Feed Level Sensor (HC-SR04)',
                desc: 'Ultrasonic sensor mounted inside the hopper lid. Measures feed depth down to 5 kg capacity in real time.',
                icon: Icons.sensors,
              ),
              const Divider(height: 18),
              _buildGuideItem(
                title: 'Solar & Power Subsystem',
                desc: '12V Monocrystalline solar panel charging a deep-cycle battery through a solar charge controller to ensure 24/7 off-grid operation.',
                icon: Icons.solar_power,
              ),
              const Divider(height: 18),
              _buildGuideItem(
                title: 'Dispenser & Scale (HX711)',
                desc: 'High-torque auger driven by a 12V motor paired with an HX711 load cell amplifier to deliver ±2g portion accuracy.',
                icon: Icons.scale,
              ),
              const Divider(height: 18),
              _buildGuideItem(
                title: 'Automated Scheduling',
                desc: 'Configurable feeding routines that execute automatically even during temporary mobile app disconnection.',
                icon: Icons.schedule,
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem({required String title, required String desc, required IconData icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF0F766E)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}
