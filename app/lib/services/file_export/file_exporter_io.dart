import 'dart:convert';
import 'dart:io';
import 'file_export_models.dart';

Future<ExportResult> exportFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  try {
    Directory? targetDir;

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final dl = Directory('$userProfile\\Downloads');
        if (dl.existsSync()) {
          targetDir = dl;
        } else {
          final docs = Directory('$userProfile\\Documents');
          if (docs.existsSync()) targetDir = docs;
        }
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final dl = Directory('$home/Downloads');
        if (dl.existsSync()) targetDir = dl;
      }
    } else if (Platform.isAndroid) {
      final dl = Directory('/storage/emulated/0/Download');
      if (dl.existsSync()) {
        targetDir = dl;
      } else {
        final docs = Directory('/storage/emulated/0/Documents');
        if (docs.existsSync()) targetDir = docs;
      }
    }

    targetDir ??= Directory.current;

    final file = File('${targetDir.path}${Platform.pathSeparator}$fileName');
    // Prepend UTF-8 BOM (\uFEFF) so Microsoft Excel automatically recognizes UTF-8 encoding and column separation
    final utf8Payload = content.startsWith('\uFEFF') ? content : '\uFEFF$content';
    final bytes = utf8.encode(utf8Payload);
    await file.writeAsBytes(bytes, flush: true);

    return ExportResult(
      success: true,
      filePath: file.path,
      isWeb: false,
      message: 'File saved to Downloads:\n${file.path}',
    );
  } catch (e) {
    return ExportResult(
      success: false,
      filePath: '',
      isWeb: false,
      message: 'Failed to save file: $e',
    );
  }
}

Future<void> openFileLocation(String filePath) async {
  if (filePath.isEmpty) return;
  try {
    if (Platform.isWindows) {
      // Highlights file in Windows File Explorer
      await Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      final dir = File(filePath).parent.path;
      await Process.run('xdg-open', [dir]);
    }
  } catch (_) {}
}

Future<void> openFileWithDefaultApp(String filePath) async {
  if (filePath.isEmpty) return;
  try {
    if (Platform.isWindows) {
      // Starts file with default associated app (Microsoft Excel)
      await Process.run('cmd', ['/c', 'start', '', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [filePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [filePath]);
    }
  } catch (_) {}
}
