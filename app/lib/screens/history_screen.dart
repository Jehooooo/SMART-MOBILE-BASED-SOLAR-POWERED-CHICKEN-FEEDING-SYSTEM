import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../models/feeding_log.dart';

class HistoryScreen extends StatefulWidget {
  final FeederService feederService;

  const HistoryScreen({super.key, required this.feederService});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter = 'All'; // 'All', 'Schedule', 'Manual'

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.feederService,
      builder: (context, _) {
        final allLogs = widget.feederService.history;

        // Apply selected filter
        final filteredLogs = _selectedFilter == 'All'
            ? allLogs
            : allLogs.where((l) => l.triggerType.startsWith(_selectedFilter)).toList();

        final totalFeedings = allLogs.length;
        final totalGrams = allLogs.fold<double>(0.0, (acc, item) => acc + item.actualGrams);
        final avgAccuracy = totalFeedings > 0
            ? allLogs.fold<double>(0.0, (acc, item) => acc + item.accuracyPercent) / totalFeedings
            : 0.0;

        final scheduleCount = allLogs.where((l) => l.triggerType.startsWith('Schedule')).length;
        final manualCount = allLogs.where((l) => l.triggerType.startsWith('Manual')).length;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Feeding Logs & Analytics',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded, color: Color(0xFF0F766E)),
                tooltip: 'Export CSV Dataset',
                onPressed: () => _showExportCsvModal(context),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: allLogs.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                      padding: const EdgeInsets.all(16.0),
                      children: [
                        // Research Metrics Summary Card
                        Card(
                          elevation: 0.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFF99F6E4)),
                          ),
                          color: const Color(0xFFF0FDFA),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Flexible(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.analytics_outlined, color: Color(0xFF0F766E), size: 20),
                                          SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Performance Metrics',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFCCFBF1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Chapter IV Data',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildSummaryItem('Total Feeds', '$totalFeedings'),
                                    _buildSummaryItem('Avg Accuracy', '${avgAccuracy.toStringAsFixed(1)}%'),
                                    _buildSummaryItem(
                                      'Total Dispensed',
                                      totalGrams >= 1000
                                          ? '${(totalGrams / 1000).toStringAsFixed(2)} kg'
                                          : '${totalGrams.toStringAsFixed(0)} g',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Filter Chips Row
                        Row(
                          children: [
                            const Text(
                              'Filter Logs:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterChip('All', 'All (${allLogs.length})'),
                                    const SizedBox(width: 6),
                                    _buildFilterChip('Schedule', 'Scheduled ($scheduleCount)'),
                                    const SizedBox(width: 6),
                                    _buildFilterChip('Manual', 'Manual ($manualCount)'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Dispensing Records (${filteredLogs.length})',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              'Latest first',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        if (filteredLogs.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                            child: Center(
                              child: Text(
                                'No logs match "$_selectedFilter" filter.',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ),
                          )
                        else
                          ...filteredLogs.map((log) => _buildLogCard(log)),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedFilter = filterKey);
      },
      selectedColor: const Color(0xFF0F766E),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : const Color(0xFF0F172A),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              child: Icon(Icons.history_toggle_off, size: 56, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Feeding Logs Yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              'Dispense feed manually from the Dashboard or wait for your scheduled routines to trigger.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildLogCard(FeedingLog log) {
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
    final formattedDate = dateFormat.format(log.timestamp);
    final relativeTime = _formatRelativeTime(log.timestamp);
    final errorDiff = log.errorGrams;
    final isOver = errorDiff >= 0;
    final isScheduled = log.triggerType.startsWith('Schedule');
    final isSuccess = log.isSuccess;

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isScheduled ? const Color(0xFFCCFBF1) : const Color(0xFFFEF3C7),
                  child: Icon(
                    isScheduled ? Icons.alarm : Icons.touch_app,
                    size: 14,
                    color: isScheduled ? const Color(0xFF0F766E) : const Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedDate,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        relativeTime,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSuccess ? const Color(0xFFF1F5F9) : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isSuccess ? const Color(0xFFE2E8F0) : Colors.red.shade200),
                  ),
                  child: Text(
                    log.triggerType,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSuccess ? const Color(0xFF334155) : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Target', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text('${log.targetGrams.toStringAsFixed(1)} g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Dispensed', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(
                        '${log.actualGrams.toStringAsFixed(1)} g',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F766E)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Variance', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(
                        '${isOver ? '+' : ''}${errorDiff.toStringAsFixed(1)} g (${log.accuracyPercent.toStringAsFixed(1)}%)',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: errorDiff.abs() <= 3.0 ? const Color(0xFF059669) : Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Hardware snapshot footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 4),
                  Text(
                    '${log.batteryVolts.toStringAsFixed(1)}V',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF0F766E)),
                  const SizedBox(width: 4),
                  Text(
                    '${log.feedLevelPercent.toStringAsFixed(0)}% hopper',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    '${log.durationSeconds}s duration',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportCsvModal(BuildContext context) {
    final csvData = widget.feederService.exportCsv();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.table_chart_outlined, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Export Feeding Logs (CSV)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Research dataset formatted for Chapter IV empirical analysis (Excel, SPSS, Google Sheets):',
              style: TextStyle(fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              width: double.maxFinite,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  csvData,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvData));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CSV copied to clipboard! Paste directly into Excel or Google Sheets.'),
                  backgroundColor: Color(0xFF0F766E),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy CSV Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
