import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../models/telemetry.dart';

class DashboardScreen extends StatefulWidget {
  final FeederService feederService;

  const DashboardScreen({super.key, required this.feederService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _selectedPortionGrams = 150.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.feederService,
      builder: (context, _) {
        final telemetry = widget.feederService.telemetry;
        final nextSch = widget.feederService.nextSchedule;
        final isDispensing = widget.feederService.isDispensing;

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
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Chip(
                  avatar: CircleAvatar(
                    backgroundColor: isDispensing
                        ? Colors.orange
                        : (telemetry.isOnline ? Colors.green : Colors.red),
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
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Status Banner
                if (isDispensing)
                  _buildDispensingBanner(telemetry)
                else if (telemetry.feedLevelPercent < 20)
                  _buildWarningBanner('Low Feed Warning: Hopper below 20% capacity.', Colors.amber.shade800)
                else if (telemetry.batteryPercent < 20)
                  _buildWarningBanner('Low Battery Warning: Battery below 20%.', Colors.red.shade700),

                const SizedBox(height: 12),

                // Hopper Feed Level Card
                _buildHopperCard(telemetry),

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

                const SizedBox(height: 24),

                // Manual Feeding Section
                _buildManualFeedSection(isDispensing),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWarningBanner(String message, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispensingBanner(FeederTelemetry telemetry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              const Text(
                'Dispensing in Progress...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
              ),
              const Spacer(),
              Text(
                'Scale: ${telemetry.currentWeightGrams.toStringAsFixed(1)}g',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_selectedPortionGrams > 0)
                ? (telemetry.currentWeightGrams / _selectedPortionGrams).clamp(0.0, 1.0)
                : null,
            backgroundColor: Colors.blue.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildHopperCard(FeederTelemetry telemetry) {
    final pct = telemetry.feedLevelPercent;
    final color = pct > 40 ? Colors.teal : (pct > 20 ? Colors.amber.shade700 : Colors.red);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Feed Hopper Level',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pct / 100.0).clamp(0.0, 1.0),
                minHeight: 18,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Capacity: ~5.0 kg',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  'Sensor: Ultrasonic HC-SR04',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildNextScheduleCard(dynamic nextSch) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade50,
          child: Icon(Icons.alarm, color: Colors.teal.shade700),
        ),
        title: const Text('Next Automated Feeding', style: TextStyle(fontSize: 13, color: Colors.grey)),
        subtitle: Text(
          nextSch != null ? '${nextSch.label} at ${nextSch.timeFormatted}' : 'No active schedules',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        trailing: nextSch != null
            ? Chip(
                label: Text('${nextSch.targetGrams.toInt()}g'),
                backgroundColor: Colors.teal.shade50,
                labelStyle: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.bold),
              )
            : null,
      ),
    );
  }

  Widget _buildManualFeedSection(bool isDispensing) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.teal.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual Feed Trigger',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Select portion weight to dispense immediately:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [50.0, 100.0, 150.0, 200.0].map((grams) {
                final isSelected = _selectedPortionGrams == grams;
                return ChoiceChip(
                  label: Text('${grams.toInt()}g'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedPortionGrams = grams);
                  },
                  selectedColor: Colors.teal,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isDispensing ? null : () => _confirmManualFeed(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  isDispensing ? 'Dispensing Feed...' : 'DISPENSE ${_selectedPortionGrams.toInt()}g NOW',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        title: const Text('Confirm Feeding'),
        content: Text('Dispense ${_selectedPortionGrams.toInt()} grams of feed now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.feederService.triggerManualFeed(_selectedPortionGrams);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Confirm & Dispense'),
          ),
        ],
      ),
    );
  }
}
