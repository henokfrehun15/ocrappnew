import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class FileHandler {
  final ImagePicker _picker = ImagePicker();
  static final DateFormat _dateFormat = DateFormat('yyyyMMdd_HHmmss');
  pw.Font? _amharicFont;

  Future<void> _loadFont() async {
    if (_amharicFont != null) return; // Already loaded
    try {
      final fontData =
          await rootBundle.load('assets/fonts/AbyssinicaSIL-Regular.ttf');
      _amharicFont = pw.Font.ttf(fontData);
    } catch (e) {
      _amharicFont = pw.Font.courier(); // Fallback
    }
  }

  Future<File?> pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source);
      return picked != null ? File(picked.path) : null;
    } on PlatformException catch (e) {
      throw Exception('Image picker error: ${e.message}');
    }
  }

  Future<void> saveToHistory(String text, List<String> history) async {
    if (text.isEmpty) return;
    final newHistory = [text, ...history.take(99)];
    await saveHistory(newHistory);
  }

  Future<void> saveHistory(List<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scanHistory', history);
  }

  Future<List<String>> loadScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('scanHistory') ?? [];
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return true;
    }
    return true;
  }

  Future<Directory?> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final List<String> paths = [
        '/storage/emulated/0/Download',
        '/sdcard/Download',
        '/storage/emulated/0/Downloads',
      ];

      for (final path in paths) {
        final dir = Directory(path);
        if (await dir.exists()) return dir;
      }
      return await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    return null;
  }

  Future<File> _saveFile(String content, String extension,
      {bool useDownloads = true}) async {
    if (!await _requestStoragePermission()) {
      throw Exception('Storage permission denied');
    }

    final Directory dir = useDownloads
        ? (await _getDownloadsDirectory()) ??
            await getApplicationDocumentsDirectory()
        : await getApplicationDocumentsDirectory();

    final timestamp = _dateFormat.format(DateTime.now());
    final filename = 'Amharic_OCR_$timestamp.$extension';
    final file = File('${dir.path}/$filename');

    if (extension == 'pdf') {
      await _loadFont(); // Ensure font is loaded
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                text: 'Amharic OCR Result',
                level: 0,
                textStyle: pw.TextStyle(
                  fontSize: 24,
                  font: _amharicFont,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                content,
                style: pw.TextStyle(
                  fontSize: 16,
                  font: _amharicFont,
                ),
              ),
            ],
          ),
        ),
      );
      await file.writeAsBytes(await pdf.save());
    } else {
      await file.writeAsString(content);
    }
    return file;
  }

  Future<File> savePDF(String text, {bool useDownloads = true}) async {
    await _loadFont(); // Ensure font is loaded
    final pdf = pw.Document();

    // Split text into manageable chunks (500 chars per page)
    final chunks = _splitTextIntoChunks(text, 1250);

    for (var i = 0; i < chunks.length; i++) {
      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (i == 0) // Only show header on first page
                  pw.Header(
                    level: 0,
                    text: 'Amharic OCR Result',
                    textStyle: pw.TextStyle(
                      fontSize: 24,
                      font: _amharicFont,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                pw.SizedBox(height: 20),
                pw.Text(
                  chunks[i],
                  style: pw.TextStyle(
                    fontSize: 14, // Slightly smaller font for more content
                    font: _amharicFont,
                    lineSpacing: 5,
                  ),
                ),
                if (chunks.length > 1) // Add page numbers if multiple pages
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Page ${i + 1} of ${chunks.length}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        font: _amharicFont,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    final dir = useDownloads
        ? (await _getDownloadsDirectory()) ??
            await getApplicationDocumentsDirectory()
        : await getApplicationDocumentsDirectory();

    final timestamp = _dateFormat.format(DateTime.now());
    final file = File('${dir.path}/Amharic_OCR_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  List<String> _splitTextIntoChunks(String text, int maxChars) {
    final words = text.split(' ');
    final chunks = <String>[];
    var currentChunk = '';

    for (final word in words) {
      if ((currentChunk + word).length > maxChars) {
        chunks.add(currentChunk.trim());
        currentChunk = '';
      }
      currentChunk += '$word ';
    }

    if (currentChunk.trim().isNotEmpty) {
      chunks.add(currentChunk.trim());
    }

    return chunks;
  }

  Future<File> saveTextFile(String text, {bool useDownloads = true}) async {
    return await _saveFile(text, 'txt', useDownloads: useDownloads);
  }

  Future<void> copyToClipboard(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> shareFile(File file, {String? subject}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject ?? 'Amharic OCR Result',
    );
  }
}

extension FileHandlerExtensions on String {
  String get first50Chars => length > 50 ? '${substring(0, 50)}...' : this;
  String get safeFilename => replaceAll(RegExp(r'[^\w-]'), '_');
}
