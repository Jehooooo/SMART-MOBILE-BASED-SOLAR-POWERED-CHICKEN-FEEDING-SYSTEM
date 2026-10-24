import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../services/file_export/file_exporter.dart';
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
                icon: const Icon(Icons.sync_rounded),
                tooltip: 'Sync with Firebase',
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Syncing logs with Firebase...'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  await widget.feederService.refreshLogsFromCloud();
                },
              ),
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
                                ? RefreshIndicator(
                                    onRefresh: () => widget.feederService.refreshLogsFromCloud(),
                                    child: SingleChildScrollView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      child: _buildEmptyState(),
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: () => widget.feederService.refreshLogsFromCloud(),
                                    child: ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.all(16.0),
                                      children: [
                                        // Research Metrics Summary Card
                                      Card(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(18),
                                          side: BorderSide(color: c.brandBorder.withValues(alpha: 0.8)),
                                        ),
                                        color: c.brandSurface,
                                        child: Padding(
                                          padding: const EdgeInsets.all(18.0),
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
                                                        Container(
                                                          padding: const EdgeInsets.all(8),
                                                          decoration: BoxDecoration(
                                                            color: c.brandSoft,
                                                            borderRadius: BorderRadius.circular(10),
                                                          ),
                                                          child: Icon(Icons.analytics_outlined, color: c.brand, size: 20),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        Flexible(
                                                          child: Text(
                                                            'Performance Metrics',
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w800,
                                                              letterSpacing: -0.2,
                                                              color: c.textPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: c.surface,
                                                      borderRadius: BorderRadius.circular(20),
                                                      border: Border.all(color: c.brandBorder.withValues(alpha: 0.6)),
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
                                              const SizedBox(height: 16),
                                              Row(
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

                                      const SizedBox(height: 18),

                                      // Filter Chips Row
                                      Row(
                                        children: [
                                          Text(
                                            'Filter Logs:',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
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
                                                  const SizedBox(width: 8),
                                                  _buildFilterChip('Schedule', 'Scheduled ($scheduleCount)'),
                                                  const SizedBox(width: 8),
                                                  _buildFilterChip('Manual', 'Manual ($manualCount)'),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 14),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Dispensing Records (${filteredLogs.length})',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
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
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected ? c.brand : c.border.withValues(alpha: 0.8),
        ),
      ),
      selectedColor: c.brand,
      backgroundColor: c.surface,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        color: isSelected ? c.onBrand : c.textSecondary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.history_toggle_off, size: 52, color: c.textMuted),
            ),
            const SizedBox(height: 18),
            Text(
              'No Feeding Logs Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary),
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
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: c.textMuted, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border.withValues(alpha: 0.7)),
      ),
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
                    color: isScheduled ? c.brandSoft : c.manualSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isScheduled ? Icons.alarm_rounded : Icons.touch_app_rounded,
                    size: 16,
                    color: isScheduled ? c.brand : c.manual,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedDate,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.textPrimary),
                      ),
                      Text(
                        relativeTime,
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSuccess ? c.surfaceMuted : c.dangerSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSuccess ? c.border : c.dangerBorder),
                  ),
                  child: Text(
                    log.triggerType,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSuccess ? c.textSecondary : c.danger,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Target', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        '${log.targetGrams.toStringAsFixed(1)} g',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c.textPrimary),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dispensed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        '${log.actualGrams.toStringAsFixed(1)} g',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c.brand),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Variance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (errorDiff.abs() <= 3.0 ? c.success : c.warning).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${isOver ? '+' : ''}${errorDiff.toStringAsFixed(1)} g (${log.accuracyPercent.toStringAsFixed(1)}%)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: errorDiff.abs() <= 3.0 ? c.success : c.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Hardware snapshot footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: c.solar),
                  const SizedBox(width: 4),
                  Text(
                    '${log.batteryVolts.toStringAsFixed(1)}V',
                    style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 14),
                  Icon(Icons.inventory_2_outlined, size: 14, color: c.brand),
                  const SizedBox(width: 4),
                  Text(
                    '${log.feedLevelPercent.toStringAsFixed(0)}% hopper',
                    style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600),
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
    final logCount = widget.feederService.history.length;
    bool isExporting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> handleExport() async {
            setDialogState(() {
              isExporting = true;
            });

            final now = DateTime.now();
            final timestampStr = DateFormat('yyyyMMdd_HHmmss').format(now);
            final fileName = 'feeding_logs_$timestampStr.csv';
            const mimeType = 'text/csv;charset=utf-8';

            final result = await FileExporter.downloadTextFile(
              fileName: fileName,
              content: csvData,
              mimeType: mimeType,
            );

            setDialogState(() {
              isExporting = false;
            });

            if (!context.mounted) return;

            if (result.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result.isWeb
                        ? 'Downloaded $fileName to your browser.'
                        : 'Successfully saved $fileName!',
                  ),
                  backgroundColor: c.brand,
                  duration: const Duration(seconds: 4),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Export failed: ${result.message}'),
                  backgroundColor: c.danger,
                ),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.table_chart_outlined, color: c.brand, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Export Feeding Logs',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      Text(
                        '$logCount records ready to export',
                        style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Feeding logs dataset in CSV format:',
                    style: TextStyle(fontSize: 13, height: 1.3),
                  ),
                  const SizedBox(height: 10),

                  // Data Preview Box
                  Container(
                    height: 140,
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border.withValues(alpha: 0.8)),
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
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: TextStyle(color: c.textMuted)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: csvData));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('CSV copied to clipboard! Paste directly into Excel or Google Sheets.'),
                          backgroundColor: c.brand,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isExporting ? null : () => handleExport(),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.onBrand,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
