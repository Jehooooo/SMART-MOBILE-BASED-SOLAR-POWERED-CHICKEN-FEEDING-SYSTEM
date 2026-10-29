import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../models/schedule.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/skeleton.dart';
import '../widgets/glass_components.dart';

class SchedulesScreen extends StatefulWidget {
  final FeederService feederService;

  const SchedulesScreen({super.key, required this.feederService});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.feederService,
      builder: (context, _) {
        final c = context.colors;
        final schedules = widget.feederService.schedules;
        final activeCount = widget.feederService.activeScheduleCount;
        final totalGrams = widget.feederService.totalDailyTargetGrams;
        final totalSeconds = widget.feederService.totalDailyDurationSeconds;
        final isLoading = widget.feederService.isInitialLoading;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Feeding Schedules',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              LiquidGlassIconButton(
                size: 38,
                icon: const Icon(Icons.sync_rounded),
                tooltip: 'Sync with Firebase',
                onPressed: () async {
                  final ok = await widget.feederService.refreshSchedulesFromCloud();
                  if (!context.mounted) return;
                  final msg = ok
                      ? (widget.feederService.isMock
                          ? 'Schedules verified in local simulator cache.'
                          : 'Schedules synchronized from Firebase.')
                      : (widget.feederService.lastErrorMessage ??
                          'Could not sync schedules from Firebase. Showing cached schedules.');
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        backgroundColor: ok ? c.brand : c.danger,
                        content: Text(msg),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              ConnectionBanner(feederService: widget.feederService),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: isLoading
                      ? const ListSkeleton(key: ValueKey('sched-skeleton'))
                      : Center(
                          key: const ValueKey('sched-content'),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 850),
                            child: schedules.isEmpty
                                ? RefreshIndicator(
                                    onRefresh: () => widget.feederService.refreshSchedulesFromCloud(),
                                    child: SingleChildScrollView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      child: _buildEmptyState(),
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: () => widget.feederService.refreshSchedulesFromCloud(),
                                    child: ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 110.0),
                                      children: [
                                        // Summary Banner
                                        _buildSummaryBanner(activeCount, totalSeconds, totalGrams),
                                        const SizedBox(height: 16),

                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Configured Routines (${schedules.length})',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'Tap card to edit',
                                              style: TextStyle(fontSize: 12, color: c.textMuted),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        ...schedules.asMap().entries.map((entry) {
                                          final index = entry.key;
                                          final item = entry.value;
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 10.0),
                                            child: _buildScheduleCard(item, index),
                                          );
                                        }),
                                        const SizedBox(height: 20),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                ),
              ),
            ],
          ),
          floatingActionButton: Builder(
            builder: (context) {
              final isWide = MediaQuery.of(context).size.width >= 720;
              return Padding(
                padding: EdgeInsets.only(bottom: isWide ? 0.0 : 78.0),
                child: LiquidGlassButton(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  onPressed: () => _showScheduleDialog(context),
                  icon: const Icon(Icons.add_alarm, size: 20),
                  child: const Text('Add Schedule'),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSummaryBanner(int activeCount, int totalDailySeconds, double totalDailyGrams) {
    final c = context.colors;
    return LiquidGlassCard(
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.all(18.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.brandBorder.withValues(alpha: 0.6), width: 1),
            ),
            child: Icon(Icons.calendar_month_rounded, color: c.brand, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$activeCount Active Daily ${activeCount == 1 ? 'Routine' : 'Routines'}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  'Total daily flock runtime: ${totalDailySeconds}s (~${totalDailyGrams.toInt()}g)',
                  style: TextStyle(fontSize: 13, color: c.brand, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.brandBorder.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeCount > 0 ? c.brand : c.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  activeCount > 0 ? 'Active' : 'Paused',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: activeCount > 0 ? c.brand : c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: LiquidGlassCard(
          borderRadius: BorderRadius.circular(26),
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.alarm_off, size: 52, color: c.textMuted),
              ),
              const SizedBox(height: 18),
              Text(
                'No Feeding Schedules Set',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the "+ Add Schedule" button below to set up automated poultry feeding times.',
                style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(FeedingSchedule schedule, int index) {
    final c = context.colors;
    return LiquidGlassCard(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(14.0),
      glowBorderColor: schedule.isEnabled ? c.brandBorder.withValues(alpha: 0.5) : null,
      onTap: () => _showScheduleDialog(context, existing: schedule),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: schedule.isEnabled ? c.brandSoft : c.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.access_time_filled_rounded,
              color: schedule.isEnabled ? c.brand : c.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.timeFormatted,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: schedule.isEnabled ? c.textPrimary : c.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        schedule.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: schedule.isEnabled ? c.textSecondary : c.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: schedule.isEnabled ? c.brandSoft : c.track,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${schedule.durationSeconds}s (~${schedule.targetGrams.toInt()}g)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: schedule.isEnabled ? c.brand : c.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          LiquidGlassIconButton(
            size: 34,
            icon: Icon(
              Icons.play_circle_outline_rounded,
              color: schedule.isEnabled ? c.brand : c.textMuted,
              size: 20,
            ),
            tooltip: 'Test run routine now',
            onPressed: () async {
              final ok = await widget.feederService.triggerSchedule(schedule);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Executing "${schedule.label}" (${schedule.targetGrams.toInt()}g)...'
                        : 'Could not trigger feeding. Feeder is busy or offline.'),
                    backgroundColor: ok ? c.brand : c.danger,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: schedule.isEnabled ? 'Pause schedule' : 'Enable schedule',
            child: Switch(
              value: schedule.isEnabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                widget.feederService.toggleSchedule(schedule.id, val);
              },
            ),
          ),
          const SizedBox(width: 4),
          LiquidGlassIconButton(
            size: 34,
            icon: Icon(Icons.delete_outline, color: c.danger, size: 18),
            tooltip: 'Delete schedule',
            onPressed: () => _confirmDelete(schedule, index),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(FeedingSchedule schedule, int originalIndex) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => LiquidGlassDialog(
        maxWidth: 400,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.dangerSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, color: c.danger, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Delete Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text('Remove "${schedule.label}" at ${schedule.timeFormatted}?'),
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
              Navigator.pop(ctx);
              widget.feederService.deleteSchedule(schedule.id);
              if (mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${schedule.label}" (${schedule.timeFormatted})'),
                    action: SnackBarAction(
                      label: 'UNDO',
                      textColor: c.brandBorder,
                      onPressed: () {
                        widget.feederService.insertScheduleAt(originalIndex, schedule);
                      },
                    ),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showScheduleDialog(BuildContext context, {FeedingSchedule? existing}) {
    final c = context.colors;
    final isEditing = existing != null;
    TimeOfDay selectedTime = isEditing
        ? TimeOfDay(hour: existing.hour, minute: existing.minute)
        : const TimeOfDay(hour: 7, minute: 0);

    final labelCtrl = TextEditingController(text: isEditing ? existing.label : 'Routine Feed');
    final durationCtrl = TextEditingController(
      text: isEditing ? existing.durationSeconds.toString() : '5',
    );
    String? validationError;

    final presetLabels = ['Morning Feeding', 'Midday Feeding', 'Afternoon Feeding', 'Evening Snack'];
    final presetDurations = [3, 5, 10, 15];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => LiquidGlassDialog(
          maxWidth: 480,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(isEditing ? Icons.edit_calendar_rounded : Icons.alarm_add_rounded, color: c.brand, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEditing ? 'Edit Feeding Schedule' : 'New Feeding Schedule',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (validationError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.dangerSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.dangerBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: c.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            validationError!,
                            style: TextStyle(color: c.danger, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Label',
                    hintText: 'e.g. Morning Feeding',
                  ),
                ),
                const SizedBox(height: 10),

                // Quick label presets
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presetLabels.map((preset) {
                    final isSel = labelCtrl.text == preset;
                    return LiquidGlassChip(
                      label: preset,
                      isSelected: isSel,
                      onSelected: (_) {
                        setDialogState(() {
                          labelCtrl.text = preset;
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.brandSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.schedule_rounded, color: c.brand, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Dispensing Time',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      LiquidGlassButton(
                        isSecondary: true,
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedTime = picked;
                              validationError = null;
                            });
                          }
                        },
                        child: Text(selectedTime.format(context)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dispense Duration (seconds)',
                    hintText: 'e.g. 5',
                    suffixText: 'sec',
                    helperText: 'Recommended runtime: 1s - 30s (~20g/sec output)',
                  ),
                  onChanged: (_) {
                    if (validationError != null) {
                      setDialogState(() => validationError = null);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presetDurations.map((sec) {
                    final isSel = durationCtrl.text == sec.toString();
                    return LiquidGlassChip(
                      label: '${sec}s (~${sec * 20}g)',
                      isSelected: isSel,
                      onSelected: (_) {
                        setDialogState(() {
                          durationCtrl.text = sec.toString();
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
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
                final duration = int.tryParse(durationCtrl.text.trim());
                if (duration == null || duration < 1 || duration > 60) {
                  setDialogState(() {
                    validationError = 'Please enter a valid runtime between 1s and 60s.';
                  });
                  return;
                }
                final grams = duration * 20.0;

                // Check for duplicate time (ignoring itself if editing)
                final isDuplicate = widget.feederService.schedules.any(
                  (s) => s.id != existing?.id && s.hour == selectedTime.hour && s.minute == selectedTime.minute,
                );

                if (isDuplicate) {
                  setDialogState(() {
                    validationError = 'A schedule already exists at ${selectedTime.format(context)}. Please choose a different time.';
                  });
                  return;
                }

                final label = labelCtrl.text.trim().isEmpty ? 'Routine Feed' : labelCtrl.text.trim();

                if (isEditing) {
                  final updated = existing.copyWith(
                    label: label,
                    hour: selectedTime.hour,
                    minute: selectedTime.minute,
                    durationSeconds: duration,
                    targetGrams: grams,
                  );
                  widget.feederService.updateSchedule(updated);
                } else {
                  final newSchedule = FeedingSchedule(
                    id: 'sch_${DateTime.now().millisecondsSinceEpoch}',
                    label: label,
                    hour: selectedTime.hour,
                    minute: selectedTime.minute,
                    durationSeconds: duration,
                    targetGrams: grams,
                    isEnabled: true,
                  );
                  widget.feederService.addSchedule(newSchedule);
                }
                Navigator.pop(ctx);
              },
              child: Text(isEditing ? 'Save Changes' : 'Save Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
