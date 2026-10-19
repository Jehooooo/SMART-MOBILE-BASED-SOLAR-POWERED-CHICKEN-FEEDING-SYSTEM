import 'file_export_models.dart';
import 'file_exporter_stub.dart'
    if (dart.library.html) 'file_exporter_web.dart'
    if (dart.library.io) 'file_exporter_io.dart';

export 'file_export_models.dart';

class FileExporter {
  /// Exports text content (such as CSV or TSV) to the user's Downloads directory
  /// or triggers a native browser download on Web.
  static Future<ExportResult> downloadTextFile({
    required String fileName,
    required String content,
    String mimeType = 'text/csv;charset=utf-8',
  }) {
    return exportFile(
      fileName: fileName,
      content: content,
      mimeType: mimeType,
    );
  }

  /// Reveals the downloaded file in the native file explorer (Windows Explorer, Finder).
  static Future<void> showInFolder(String filePath) {
    return openFileLocation(filePath);
  }

  /// Opens the file directly using the system default application (e.g. Microsoft Excel).
  static Future<void> openFile(String filePath) {
    return openFileWithDefaultApp(filePath);
  }
}
