import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../utils/feed_portions.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/glass_components.dart';

/// Interactive controller, gate servo, and time-estimation diagnostics screen.
///
/// Focuses strictly on the active hardware subsystems:
/// 1. Live ESP32 controller link & transport heartbeat.
/// 2. DS-S020A-C 30kg Servo Gate actuation checks (30° closed / 0° open & timed pulses).
/// 3. DS3231 RTC daylight solar status & bench-tested time-based portion ranges.
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
  bool _isActionRunning = false;
  String _lastActionStatus = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
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
            : '$label failed — check controller connection';
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
        final isOnline = widget.feederService.isDeviceOnline;
        final isSim = widget.feederService.isOfflineSimulationMode;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Controller & Gate Diagnostics',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            actions: [
              LiquidGlassIconButton(
                size: 38,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Telemetry',
                onPressed: () => widget.feederService.refreshTelemetry(),
              ),
              const SizedBox(width: 8),
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
                    _buildOverviewCard(c, telemetry, isOnline, isSim),
                    const SizedBox(height: 18),
                    _buildServoCard(c, isOnline),
                    const SizedBox(height: 18),
                    _buildSolarAndEstimationCard(c, telemetry),
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

  Widget _buildOverviewCard(AppColors c, dynamic telemetry, bool isOnline, bool isSim) {
    final hb = telemetry.lastHeartbeat as DateTime?;
    final hbText = hb != null ? DateFormat('MMM d, h:mm:ss a').format(hb) : 'Awaiting heartbeat';
    final badgeText = isSim
        ? 'SIMULATION'
        : (isOnline ? 'HARDWARE READY' : 'OFFLINE');
    final badgeColor = isSim ? c.info : (isOnline ? c.brand : c.danger);

    return LiquidGlassCard(
      glowBorderColor: badgeColor.withValues(alpha: 0.3),
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
            child: Icon(Icons.memory_rounded, color: c.brand, size: 24),
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
                        'ESP32 Controller Status',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.feederService.hardwareSourceLabel} • Last heartbeat: $hbText',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
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
              Expanded(
                child: Row(
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
                    Flexible(
                      child: Text(
                        'Dispenser Gate Servo (DS-S020A-C 30kg)',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: const Text(
                  'GPIO 18 • 7.4V',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Calibrated geometry: 30° holds gate firmly Closed under hopper pipe; 0° opens gate fully. Bench angles auto-close back to 30° after 10 seconds.',
            style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.35),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LiquidGlassButton(
                isSecondary: true,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Close Gate (30°)',
                          () => widget.feederService.testServoGate(30),
                        ),
                icon: const Icon(Icons.lock_outline_rounded, size: 16),
                child: const Text('Close Gate (30°)'),
              ),
              LiquidGlassButton(
                isSecondary: true,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Open Gate (0°)',
                          () => widget.feederService.testServoGate(0),
                        ),
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                child: const Text('Open Gate (0°)'),
              ),
              LiquidGlassButton(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                onPressed: _isActionRunning
                    ? null
                    : () => _executeAction(
                          'Pulse 1s (${FeedPortions.formatRangeForDuration(1)})',
                          () => widget.feederService.triggerManualFeed(durationSeconds: 1),
                        ),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                child: Text('Pulse 1s (${FeedPortions.formatRangeForDuration(1)})'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSolarAndEstimationCard(AppColors c, dynamic telemetry) {
    final hour = DateTime.now().hour;
    final isDaylight = widget.feederService.isMock
        ? telemetry.isSolarCharging == true
        : (hour >= 6 && hour < 18);

    return LiquidGlassCard(
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
                        color: c.brandSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.brand.withValues(alpha: 0.2)),
                      ),
                      child: Icon(Icons.timer_outlined, color: c.brand, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'DS3231 Clock & Time-Based Estimation',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDaylight ? c.brandSoft : c.surfaceMuted.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDaylight ? c.brand.withValues(alpha: 0.3) : c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDaylight ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                      size: 14,
                      color: isDaylight ? c.solar : c.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDaylight ? 'SOLAR CHARGING' : 'SOLAR IDLE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDaylight ? c.brand : c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Physical weighing scale, ultrasonic depth, and battery ADC sensors are bypassed. Feed output is estimated directly from calibrated gate open duration:',
            style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [1, 2, 3, 4, 5].map((sec) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.surfaceMuted.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${sec}s → ${FeedPortions.formatRangeForDuration(sec)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
