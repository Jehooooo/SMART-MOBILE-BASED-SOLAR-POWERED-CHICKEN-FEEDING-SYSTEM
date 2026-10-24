import 'dart:async';
import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/glass_components.dart';

/// Interactive hardware bring-up and calibration screen.
///
/// Enables fabricators, evaluators, and farm operators to test and calibrate
/// each physical subsystem independently:
/// 1. Load Cell (HX711): Zero tare and known-weight calibration.
/// 2. Ultrasonic Sensor (HC-SR04): Live distance readout & empty/full limits.
/// 3. Dispenser Gate (MG996R Servo): Direct position sweep (0°, 45°, 90°, 2s pulse).
/// 4. Solar & Battery: Live voltage, charging status, and cut-off check.
class DiagnosticsScreen extends StatefulWidget {
  final FeederService feederService;
  final bool enableAutoRefresh;

  const DiagnosticsScreen({
    super.key,
    required this.feederService,
    this.enableAutoRefresh = true,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  double _selectedCalWeight = 500.0;
  bool _isActionRunning = false;
  String _lastActionStatus = '';
  Timer? _refreshTimer;

  // Local calibration limits
  final double _hopperEmptyCm = 30.0;
  final double _hopperFullCm = 5.0;

  @override
  void initState() {
    super.initState();
    // Refresh telemetry periodically if auto-refresh enabled
    if (widget.enableAutoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) {
          widget.feederService.refreshTelemetry();
        }
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _executeAction(String label, Future<bool> Function() action) async {
    setState(() {
      _isActionRunning = true;
      _lastActionStatus = 'Executing $label...';
    });

    final success = await action();

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _lastActionStatus = success
            ? '$label completed successfully'
            : '$label failed — check hardware connection';
      });

      final c = context.colors;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lastActionStatus),
          backgroundColor: success ? c.brand : c.danger,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.feederService,
      builder: (context, _) {
        final c = context.colors;
        final telemetry = widget.feederService.telemetry;
        final isOnline = widget.feederService.isConnected;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Hardware Diagnostics & Calibration',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Telemetry',
                onPressed: () => widget.feederService.refreshTelemetry(),
              ),
            ],
          ),
          body: Column(
            children: [
              ConnectionBanner(feederService: widget.feederService),
              if (_lastActionStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: LiquidGlassContainer(
                    borderRadius: BorderRadius.circular(14),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          _lastActionStatus.contains('failed')
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: _lastActionStatus.contains('failed') ? c.danger : c.brand,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lastActionStatus,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _lastActionStatus.contains('failed') ? c.danger : c.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 110.0),
                  children: [
                    // System Status Overview Badge
                    _buildOverviewCard(c, telemetry, isOnline),

                    const SizedBox(height: 18),

                    // Section 1: Load Cell & Weighing Tray Calibration
                    _buildLoadCellCard(c, telemetry, isOnline),

                    const SizedBox(height: 18),

                    // Section 2: Ultrasonic Feed Depth & Hopper Calibration
                    _buildUltrasonicCard(c, telemetry, isOnline),

                    const SizedBox(height: 18),

                    // Section 3: Dispenser Gate Servo Actuator Test
                    _buildServoCard(c, isOnline),

                    const SizedBox(height: 18),

                    // Section 4: Solar Subsystem & 12V Battery Check
                    _buildSolarBatteryCard(c, telemetry),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewCard(AppColors c, dynamic telemetry, bool isOnline) {
    return LiquidGlassCard(
      glowBorderColor: isOnline ? c.brand.withValues(alpha: 0.3) : c.danger.withValues(alpha: 0.2),
      padding: const EdgeInsets.all(18.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.brand.withValues(alpha: 0.2)),
            ),
            child: Icon(Icons.tune_rounded, color: c.brand, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Subsystem Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOnline ? c.brand : c.danger,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline ? c.brand : c.danger).withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        isOnline ? 'HARDWARE READY' : 'OFFLINE',
                        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.feederService.isMock && !isOnline) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => widget.feederService.setSimulatedOffline(false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.brandSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.brand),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, size: 12, color: c.brand),
                              const SizedBox(width: 4),
                              Text(
                                'Enable Simulator',
                                style: TextStyle(fontSize: 10, color: c.brand, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Step-by-step verification tools for machine assembly and Chapter IV testing.',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadCellCard(AppColors c, dynamic telemetry, bool isOnline) {
    final currentWeight = (telemetry.currentWeightGrams as num?)?.toDouble() ?? 0.0;

    return LiquidGlassCard(
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
                      color: c.brandSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.scale_rounded, color: c.brand, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Load Cell & Scale (HX711)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: const Text(
                  'GPIO 16, 17',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Live weight gauge readout
          LiquidGlassContainer(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Weight Readout',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${currentWeight.toStringAsFixed(1)} g',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: c.brand,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: currentWeight.abs() < 1.0 ? c.brandSoft : c.manualSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (currentWeight.abs() < 1.0 ? c.brand : c.warning).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        currentWeight.abs() < 1.0 ? 'ZERO STABLE' : 'LOADED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: currentWeight.abs() < 1.0 ? c.brand : c.warning,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tolerance: ±1.5g',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          Text(
            '2-Point Calibration Procedure:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary),
          ),
          const SizedBox(height: 10),

          // Step 1: Zero Tare
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step 1: Empty Weighing Tray',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Clear tray of all feed, then zero the scale.',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction('Tare Scale', () => widget.feederService.tareScale()),
                icon: const Icon(Icons.exposure_zero_rounded, size: 16),
                label: const Text('Tare (0.0g)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.onBrand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          Divider(height: 24, color: c.border.withValues(alpha: 0.4)),

          // Step 2: Known Weight Factor Calibration
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Step 2: Place Known Reference Weight',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                'Place an unopened 500 mL water bottle (500g) or test weight on the tray.',
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ...[100.0, 200.0, 500.0, 1000.0].map((w) {
                    final isSelected = _selectedCalWeight == w;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ChoiceChip(
                        label: Text('${w.toInt()}g'),
                        selected: isSelected,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedCalWeight = w);
                        },
                      ),
                    );
                  }),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isActionRunning
                        ? null
                        : () => _executeAction(
                              'Calibrate to ${_selectedCalWeight.toInt()}g',
                              () => widget.feederService.calibrateScale(_selectedCalWeight),
                            ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Save Factor'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.onBrand,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUltrasonicCard(AppColors c, dynamic telemetry, bool isOnline) {
    final feedLevel = (telemetry.feedLevelPercent as num?)?.toDouble() ?? 0.0;
    // Estimated distance based on calibration formula: cm = empty - (pct/100 * (empty - full))
    final estimatedCm = _hopperEmptyCm - (feedLevel / 100.0 * (_hopperEmptyCm - _hopperFullCm));

    return LiquidGlassCard(
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
                      color: c.brandSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.sensors_rounded, color: c.brand, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Hopper Depth (HC-SR04)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: const Text(
                  'TRIG 5, ECHO 18',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Live depth & visual hopper tank
          Row(
            children: [
              // Visual tank gauge
              Container(
                width: 52,
                height: 104,
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border.withValues(alpha: 0.8)),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      height: (104 * (feedLevel / 100.0)).clamp(0.0, 104.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            feedLevel < 20 ? c.danger : c.brand,
                            (feedLevel < 20 ? c.danger : c.brand).withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Fill Level:', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                    Row(
                      children: [
                        Text(
                          '${feedLevel.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: feedLevel < 20 ? c.danger : c.brand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(~${estimatedCm.toStringAsFixed(1)} cm depth)',
                          style: TextStyle(fontSize: 12, color: c.textMuted, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (feedLevel / 100.0).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: c.track,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          feedLevel < 20 ? c.danger : c.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Text(
            'Sensor Depth Thresholds (config.h):',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HOPPER_EMPTY_CM', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text('${_hopperEmptyCm.toStringAsFixed(0)} cm (Bottom floor)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HOPPER_FULL_CM', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text('${_hopperFullCm.toStringAsFixed(0)} cm (Near lid)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          if (widget.feederService.isMock)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                widget.feederService.refillHopper();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Simulated hopper refilled to 100%')),
                );
              },
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Reset / Refill Hopper (100%)'),
            ),
        ],
      ),
    );
  }

  Widget _buildServoCard(AppColors c, bool isOnline) {
    return LiquidGlassCard(
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
                      color: c.brandSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.settings_input_component_rounded, color: c.brand, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Dispenser Gate Servo (MG996R)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: const Text(
                  'PWM GPIO 13',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tests physical gate movement without binding. Keep hands clear of auger outlet.',
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Close Gate (0°)',
                          () => widget.feederService.testServoGate(0),
                        ),
                icon: const Icon(Icons.lock_outline_rounded, size: 16),
                label: const Text('Close (0°)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.surface.withValues(alpha: 0.8),
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Half Open Gate (45°)',
                          () => widget.feederService.testServoGate(45),
                        ),
                icon: const Icon(Icons.change_history_rounded, size: 16),
                label: const Text('Half (45°)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.surface.withValues(alpha: 0.8),
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Full Open Gate (90°)',
                          () => widget.feederService.testServoGate(90),
                        ),
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Full Open (90°)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.surface.withValues(alpha: 0.8),
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Pulse Dispense Cycle (2s)',
                          () => widget.feederService.triggerManualFeed(durationSeconds: 2),
                        ),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Pulse Test (2s)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.onBrand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSolarBatteryCard(AppColors c, dynamic telemetry) {
    final vbat = (telemetry.batteryVolts as num?)?.toDouble() ?? 12.0;
    final batPct = (telemetry.batteryPercent as num?)?.toInt() ?? 50;
    final isCharging = telemetry.isSolarCharging == true || vbat > 12.6;

    return LiquidGlassCard(
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
                      color: c.brandSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.solar_power_outlined, color: c.solar, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Solar & 12V Battery (GPIO 34)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCharging ? c.brandSoft : c.surfaceMuted.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCharging ? c.brand.withValues(alpha: 0.3) : c.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCharging ? Icons.wb_sunny_rounded : Icons.battery_charging_full_rounded,
                      size: 14,
                      color: isCharging ? c.solar : c.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCharging ? 'CHARGING' : 'BATTERY ONLY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isCharging ? c.brand : c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Battery Voltage', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        '${vbat.toStringAsFixed(2)} V',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: vbat < 11.5 ? c.danger : c.textPrimary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Charge Capacity', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        '$batPct%',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: batPct < 20 ? c.danger : c.brand,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            'Divider Ratio: 5.0x (40kΩ / 10kΩ). Cut-off threshold: 11.5V (prevents battery deep-discharge).',
            style: TextStyle(fontSize: 11, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}
