import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../models/feeding_log.dart';

class HistoryScreen extends StatelessWidget {
  final FeederService feederService;

  const HistoryScreen({super.key, required this.feederService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feederService,
      builder: (context, _) {
        final logs = feederService.history;

        final totalFeedings = logs.length;
        final totalGrams = logs.fold<double>(0.0, (acc, item) => acc + item.actualGrams);
        final avgAccuracy = totalFeedings > 0
            ? logs.fold<double>(0.0, (acc, item) => acc + item.accuracyPercent) / totalFeedings
            : 0.0;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Feeding Logs & Analytics',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Export CSV Data',
                onPressed: () => _showExportCsvModal(context),
              ),
            ],
          ),
          body: logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No Feeding Logs Yet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Dispense feed manually or wait for scheduled feeds.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    // Research Metrics Card
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Colors.teal.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Performance Metrics',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Chapter IV Data',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
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

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dispensing Records',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${logs.length} entries',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    ...logs.map((log) => _buildLogCard(log)),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildLogCard(FeedingLog log) {
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
    final formattedDate = dateFormat.format(log.timestamp);
    final errorDiff = log.errorGrams;
    final isOver = errorDiff >= 0;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  log.triggerType == 'Schedule' ? Icons.alarm : Icons.touch_app,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  formattedDate,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    log.triggerType,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Target Portion', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text('${log.targetGrams.toStringAsFixed(1)} g', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Actual Dispensed', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(
                      '${log.actualGrams.toStringAsFixed(1)} g',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Accuracy Variance', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(
                      '${isOver ? '+' : ''}${errorDiff.toStringAsFixed(1)} g (${log.accuracyPercent.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: errorDiff.abs() <= 3.0 ? Colors.green.shade700 : Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExportCsvModal(BuildContext context) {
    final csvData = feederService.exportCsv();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Feeding Logs (CSV)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Research dataset ready for export to Excel, SPSS, or Google Sheets:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              width: double.maxFinite,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                child: Text(
                  csvData,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
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
                  content: Text('CSV copied to clipboard! Paste directly into Excel/Sheets.'),
                  backgroundColor: Colors.teal,
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy CSV Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
