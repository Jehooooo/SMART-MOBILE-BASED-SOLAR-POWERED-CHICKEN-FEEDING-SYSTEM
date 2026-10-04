import 'package:flutter/material.dart';
import '../services/feeder_service.dart';
import '../models/schedule.dart';

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
        final schedules = widget.feederService.schedules;
        final activeCount = widget.feederService.activeScheduleCount;
        final totalGrams = widget.feederService.totalDailyTargetGrams;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Feeding Schedules',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: schedules.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                      padding: const EdgeInsets.all(16.0),
                      children: [
                        // Summary Banner
                        _buildSummaryBanner(activeCount, totalGrams),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Configured Routines (${schedules.length})',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              'Tap card to edit',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                        const SizedBox(height: 70), // Spacing for FAB
                      ],
                    ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showScheduleDialog(context),
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_alarm),
            label: const Text('Add Schedule'),
          ),
        );
      },
    );
  }

  Widget _buildSummaryBanner(int activeCount, double totalDailyGrams) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFCCFBF1)),
      ),
      color: const Color(0xFFF0FDFA),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFCCFBF1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF0F766E), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$activeCount Active Daily ${activeCount == 1 ? 'Routine' : 'Routines'}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Total daily flock ration: ${totalDailyGrams.toInt()} grams',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0F766E), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Text(
                activeCount > 0 ? 'Active' : 'Paused',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: activeCount > 0 ? const Color(0xFF0F766E) : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.alarm_off, size: 56, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Feeding Schedules Set',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the "+ Add Schedule" button below to set up automated poultry feeding times.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(FeedingSchedule schedule, int index) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showScheduleDialog(context, existing: schedule),
      child: Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: schedule.isEnabled ? const Color(0xFFCCFBF1) : Colors.grey.shade100,
                child: Icon(
                  Icons.access_time_filled,
                  color: schedule.isEnabled ? const Color(0xFF0F766E) : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.timeFormatted,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: schedule.isEnabled ? const Color(0xFF0F172A) : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                              color: schedule.isEnabled ? const Color(0xFF475569) : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: schedule.isEnabled ? const Color(0xFFCCFBF1) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${schedule.targetGrams.toInt()}g',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: schedule.isEnabled ? const Color(0xFF0F766E) : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: schedule.isEnabled ? 'Pause schedule' : 'Enable schedule',
                child: Switch(
                  value: schedule.isEnabled,
                  activeThumbColor: const Color(0xFF0F766E),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    widget.feederService.toggleSchedule(schedule.id, val);
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.grey.shade500, size: 22),
                tooltip: 'Delete schedule',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () => _confirmDelete(schedule, index),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(FeedingSchedule schedule, int originalIndex) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Remove "${schedule.label}" at ${schedule.timeFormatted}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
                      textColor: const Color(0xFF99F6E4),
                      onPressed: () {
                        widget.feederService.insertScheduleAt(originalIndex, schedule);
                      },
                    ),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showScheduleDialog(BuildContext context, {FeedingSchedule? existing}) {
    final isEditing = existing != null;
    TimeOfDay selectedTime = isEditing
        ? TimeOfDay(hour: existing.hour, minute: existing.minute)
        : const TimeOfDay(hour: 7, minute: 0);

    final labelCtrl = TextEditingController(text: isEditing ? existing.label : 'Routine Feed');
    final gramsCtrl = TextEditingController(text: isEditing ? existing.targetGrams.toInt().toString() : '150');
    String? validationError;

    final presetLabels = ['Morning Feeding', 'Midday Feeding', 'Afternoon Feeding', 'Evening Snack'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(isEditing ? Icons.edit_calendar : Icons.alarm_add, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(isEditing ? 'Edit Feeding Schedule' : 'New Feeding Schedule'),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            validationError!,
                            style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.w600),
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
                const SizedBox(height: 8),

                // Quick label presets
                Wrap(
                  spacing: 6,
                  children: presetLabels.map((preset) {
                    return ActionChip(
                      label: Text(preset, style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setDialogState(() {
                          labelCtrl.text = preset;
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  leading: const Icon(Icons.schedule, color: Color(0xFF0F766E)),
                  title: const Text('Dispensing Time', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  trailing: OutlinedButton(
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(color: Color(0xFF0F766E)),
                    ),
                    child: Text(selectedTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: gramsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Portion (grams)',
                    hintText: 'e.g. 150',
                    suffixText: 'g',
                    helperText: 'Recommended portion: 50g - 400g per feeding',
                  ),
                  onChanged: (_) {
                    if (validationError != null) {
                      setDialogState(() => validationError = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final grams = double.tryParse(gramsCtrl.text.trim());
                if (grams == null || grams < 20 || grams > 500) {
                  setDialogState(() {
                    validationError = 'Please enter a valid portion between 20g and 500g.';
                  });
                  return;
                }

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
                    targetGrams: grams,
                  );
                  widget.feederService.updateSchedule(updated);
                } else {
                  final newSchedule = FeedingSchedule(
                    id: 'sch_${DateTime.now().millisecondsSinceEpoch}',
                    label: label,
                    hour: selectedTime.hour,
                    minute: selectedTime.minute,
                    targetGrams: grams,
                    isEnabled: true,
                  );
                  widget.feederService.addSchedule(newSchedule);
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              child: Text(isEditing ? 'Save Changes' : 'Save Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
