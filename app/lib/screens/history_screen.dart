import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../models/feeding_log.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/skeleton.dart';

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
        final c = context.colors;
        final allLogs = widget.feederService.history;
        final isLoading = widget.feederService.isInitialLoading;

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
                icon: Icon(Icons.download_rounded, color: c.brand),
                tooltip: 'Export CSV Dataset',
                onPressed: () => _showExportCsvModal(context),
              ),
            ],
          ),
          body: Column(
            children: [
              ConnectionBanner(feederService: widget.feederService),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: isLoading
                      ? const ListSkeleton(key: ValueKey('history-skeleton'))
                      : Center(
                          key: const ValueKey('history-content'),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 850),
                            child: allLogs.isEmpty
                                ? _buildEmptyState()
                                : ListView(
                                    padding: const EdgeInsets.all(16.0),
                                    children: [
                                      // Research Metrics Summary Card
                                      Card(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: c.brandBorder),
                                        ),
                                        color: c.brandSurface,
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.analytics_outlined, color: c.brand, size: 20),
                                                        const SizedBox(width: 8),
                                                        Flexible(
                                                          child: Text(
                                                            'Performance Metrics',
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight: FontWeight.bold,
                                                              color: c.brand,
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
                                                      color: c.brandSoft,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'Chapter IV Data',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: c.brand,
                                                      ),
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
                                          Text(
                                            'Filter Logs:',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: c.textSecondary,
                                            ),
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
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: c.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            'Latest first',
                                            style: TextStyle(fontSize: 12, color: c.textMuted),
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
                                              style: TextStyle(color: c.textMuted, fontSize: 14),
                                            ),
                                          ),
                                        )
                                      else
                                        ...filteredLogs.map((log) => _buildLogCard(log)),
                                    ],
                                  ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final c = context.colors;
    final isSelected = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedFilter = filterKey);
      },
      selectedColor: c.brand,
      backgroundColor: c.surface,
      side: BorderSide(color: isSelected ? c.brand : c.border),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? c.onBrand : c.textPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Widget _buildEmptyState() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_toggle_off, size: 56, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              'No Feeding Logs Yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Dispense feed manually from the Dashboard or wait for your scheduled routines to trigger.',
              style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    final c = context.colors;
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: c.textMuted, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildLogCard(FeedingLog log) {
    final c = context.colors;
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
    final formattedDate = dateFormat.format(log.timestamp);
    final relativeTime = _formatRelativeTime(log.timestamp);
    final errorDiff = log.errorGrams;
    final isOver = errorDiff >= 0;
    final isScheduled = log.triggerType.startsWith('Schedule');
    final isSuccess = log.isSuccess;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isScheduled ? c.brandSoft : c.manualSoft,
                  child: Icon(
                    isScheduled ? Icons.alarm : Icons.touch_app,
                    size: 14,
                    color: isScheduled ? c.brand : c.manual,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedDate,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.textPrimary),
                      ),
                      Text(
                        relativeTime,
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSuccess ? c.surfaceMuted : c.dangerSoft,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isSuccess ? c.border : c.dangerBorder),
                  ),
                  child: Text(
                    log.triggerType,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSuccess ? c.textSecondary : c.danger,
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
                      Text('Target', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        '${log.targetGrams.toStringAsFixed(1)} g',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.textPrimary),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dispensed', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        '${log.actualGrams.toStringAsFixed(1)} g',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.brand),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Variance', style: TextStyle(fontSize: 11, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        '${isOver ? '+' : ''}${errorDiff.toStringAsFixed(1)} g (${log.accuracyPercent.toStringAsFixed(1)}%)',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: errorDiff.abs() <= 3.0 ? c.success : c.warning,
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
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt, size: 14, color: c.solar),
                  const SizedBox(width: 4),
                  Text(
                    '${log.batteryVolts.toStringAsFixed(1)}V',
                    style: TextStyle(fontSize: 11, color: c.textMuted, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.inventory_2_outlined, size: 14, color: c.brand),
                  const SizedBox(width: 4),
                  Text(
                    '${log.feedLevelPercent.toStringAsFixed(0)}% hopper',
                    style: TextStyle(fontSize: 11, color: c.textMuted, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Icon(Icons.timer_outlined, size: 14, color: c.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    '${log.durationSeconds}s duration',
                    style: TextStyle(fontSize: 11, color: c.textMuted),
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
    final c = context.colors;
    final csvData = widget.feederService.exportCsv();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.table_chart_outlined, color: c.brand),
            const SizedBox(width: 8),
            const Text('Export Feeding Logs (CSV)'),
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
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  csvData,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: c.textSecondary),
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
                SnackBar(
                  content: const Text('CSV copied to clipboard! Paste directly into Excel or Google Sheets.'),
                  backgroundColor: c.brand,
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy CSV Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.onBrand,
            ),
          ),
        ],
      ),
    );
  }
}
