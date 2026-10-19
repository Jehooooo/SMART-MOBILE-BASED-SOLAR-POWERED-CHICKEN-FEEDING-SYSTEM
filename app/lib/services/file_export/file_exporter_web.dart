// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'file_export_models.dart';

Future<ExportResult> exportFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  try {
    final utf8Payload = content.startsWith('\uFEFF') ? content : '\uFEFF$content';
    final bytes = utf8.encode(utf8Payload);
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);

    return ExportResult(
      success: true,
      filePath: fileName,
      isWeb: true,
      message: 'File "$fileName" downloaded via browser.',
    );
  } catch (e) {
    return ExportResult(
      success: false,
      filePath: '',
      isWeb: true,
      message: 'Failed to download file: $e',
    );
  }
}

Future<void> openFileLocation(String filePath) async {}

Future<void> openFileWithDefaultApp(String filePath) async {}
