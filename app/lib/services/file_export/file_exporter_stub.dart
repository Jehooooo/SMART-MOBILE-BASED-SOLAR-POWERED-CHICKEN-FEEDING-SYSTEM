import 'file_export_models.dart';

Future<ExportResult> exportFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  throw UnsupportedError('Platform does not support file export.');
}

Future<void> openFileLocation(String filePath) async {}

Future<void> openFileWithDefaultApp(String filePath) async {}
