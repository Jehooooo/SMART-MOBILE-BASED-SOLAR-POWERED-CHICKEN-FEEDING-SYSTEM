class ExportResult {
  final bool success;
  final String filePath;
  final bool isWeb;
  final String message;

  const ExportResult({
    required this.success,
    required this.filePath,
    required this.isWeb,
    required this.message,
  });
}
