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

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Feeding Schedules',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: schedules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alarm_off, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No Feeding Schedules Set',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap the "+" button below to create an automated feeding routine.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: schedules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = schedules[index];
                    return _buildScheduleCard(item);
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddScheduleDialog(context),
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_alarm),
            label: const Text('Add Schedule'),
          ),
        );
      },
    );
  }

  Widget _buildScheduleCard(FeedingSchedule schedule) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: schedule.isEnabled ? Colors.teal.shade50 : Colors.grey.shade100,
              child: Icon(
                Icons.access_time_filled,
                color: schedule.isEnabled ? Colors.teal.shade700 : Colors.grey.shade400,
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
                      fontWeight: FontWeight.bold,
                      color: schedule.isEnabled ? Colors.black87 : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        schedule.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${schedule.targetGrams.toInt()}g',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: schedule.isEnabled,
              activeThumbColor: Colors.teal.shade700,
              onChanged: (val) {
                widget.feederService.toggleSchedule(schedule.id, val);
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.grey.shade500, size: 22),
              onPressed: () => _confirmDelete(schedule),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(FeedingSchedule schedule) {
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
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddScheduleDialog(BuildContext context) {
    TimeOfDay selectedTime = const TimeOfDay(hour: 7, minute: 0);
    final labelCtrl = TextEditingController(text: 'Routine Feed');
    final gramsCtrl = TextEditingController(text: '150');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Feeding Schedule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Label',
                    hintText: 'e.g. Morning Feeding',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule, color: Colors.teal),
                  title: const Text('Dispensing Time'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    child: Text(selectedTime.format(context)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: gramsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Portion (grams)',
                    suffixText: 'g',
                    border: OutlineInputBorder(),
                  ),
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
                final grams = double.tryParse(gramsCtrl.text) ?? 150.0;
                final newSchedule = FeedingSchedule(
                  id: 'sch_${DateTime.now().millisecondsSinceEpoch}',
                  label: labelCtrl.text.trim().isEmpty ? 'Routine Feed' : labelCtrl.text.trim(),
                  hour: selectedTime.hour,
                  minute: selectedTime.minute,
                  targetGrams: grams,
                  isEnabled: true,
                );
                widget.feederService.addSchedule(newSchedule);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
