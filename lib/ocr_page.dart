import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'file_handler.dart';
import 'ocr_processor.dart';
import 'about_page.dart';
import 'crop_screen.dart';
import 'app_language.dart';

class OCRPage extends StatefulWidget {
  const OCRPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<OCRPage> createState() => _OCRPageState();
}

class _OCRPageState extends State<OCRPage> {
  File? _image;
  String _result = "";
  bool _isProcessing = false;
  double _progress = 0.0; // Added
  bool _showScanButton = false;
  bool _isFullScreen = false;
  bool _isEditing = false;
  bool _showSaveButtons = false;
  bool _hasScannedText = false;
  double _recognizedTextSize = 12.0;
  AppLanguage _language = AppLanguage.english;
  final TextEditingController _textEditingController = TextEditingController();
  List<String> _scanHistory = [];

  final OCRProcessor _ocrProcessor = OCRProcessor();
  final FileHandler _fileHandler = FileHandler();

  final Map<AppLanguage, Map<String, String>> _strings = {
    AppLanguage.english: {
      'app_title': 'Amharic and Awngi OCR',
      'no_text': 'No text recognized yet.',
      'recognized_text': 'Recognized Text:',
      'theme_dark': 'Dark mode',
      'theme_light': 'Light mode',
      'text_size': 'Text size',
      'gallery': 'Gallery',
      'camera': 'Camera',
      'scan': 'Scan',
      'processing': 'Processing...',
      'scanning': 'Scanning... {percent}%',
      'edit_text': 'Edit Text',
      'view_history': 'View History',
      'copy_clipboard': 'Copy to Clipboard',
      'about': 'About',
      'copy_text_tooltip': 'Copy text',
      'scan_history': 'Scan History',
      'delete_title': 'Delete?',
      'delete_confirm': 'Are you sure you want to delete this entry?',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'close': 'Close',
      'edit_hint': 'Edit your recognized text here...',
      'save_changes': 'Save Changes',
      'changes_saved': 'Changes saved!',
      'save_as_pdf': 'Save as PDF',
      'save_as_text': 'Save as Text',
      'share_prompt': 'Would you like to share the file now?',
      'no': 'No',
      'share': 'Share',
      'file_saved_downloads': 'File saved to Downloads!',
      'storage_permission_required': 'Storage permission required',
      'text_copied': 'Text copied to clipboard!',
      'image_ready': 'Image cropped and ready for scanning.',
      'error_init': 'Error initializing models: {error}',
      'error_pick_crop': 'Error picking or cropping image: {error}',
      'error_generic': 'Error: {error}',
      'error_saving_file': 'Error saving file: {error}',
      'saved_success': '{type} Saved Successfully',
      'share_subject': 'Amharic OCR {type} Result',
      'type_pdf': 'PDF',
      'type_text': 'Text',
      'lang_english': 'English',
      'lang_amharic': 'Amharic',
    },
    AppLanguage.amharic: {
      'app_title': 'አማርኛ እና አዊኛ OCR',
      'no_text': 'እስካሁን ጽሑፍ አልተገኘም።',
      'recognized_text': 'የተገኘ ጽሑፍ:',
      'theme_dark': 'ጨለማ ሁነታ',
      'theme_light': 'ብሩህ ሁነታ',
      'text_size': 'የጽሑፍ መጠን',
      'gallery': 'ጋለሪ',
      'camera': 'ካሜራ',
      'scan': 'ስካን',
      'processing': 'በሂደት ላይ...',
      'scanning': 'በስካን ላይ... {percent}%',
      'edit_text': 'ጽሑፍ አስተካክል',
      'view_history': 'ታሪክ አሳይ',
      'copy_clipboard': 'ወደ ክሊፕቦርድ ቅዳ',
      'about': 'ስለ መተግበሪያ',
      'copy_text_tooltip': 'ጽሑፍ ቅዳ',
      'scan_history': 'የስካን ታሪክ',
      'delete_title': 'ይሰርዙ?',
      'delete_confirm': 'ይህን ግቤት መሰረዝ ትፈልጋላችሁ?',
      'cancel': 'አቋርጥ',
      'delete': 'ሰርዝ',
      'close': 'ዝጋ',
      'edit_hint': 'የተለየውን ጽሑፍ እዚህ አስተካክሉ...',
      'save_changes': 'ለውጦችን አስቀምጥ',
      'changes_saved': 'ለውጦች ተቀምጠዋል!',
      'save_as_pdf': 'እንደ PDF አስቀምጥ',
      'save_as_text': 'እንደ ጽሑፍ አስቀምጥ',
      'share_prompt': 'ፋይሉን አሁን ማጋራት ትፈልጋላችሁ?',
      'no': 'አይ',
      'share': 'አጋራ',
      'file_saved_downloads': 'ፋይሉ ወደ Downloads ተቀምጧል!',
      'storage_permission_required': 'የማከማቻ ፈቃድ ያስፈልጋል',
      'text_copied': 'ጽሑፉ ወደ ክሊፕቦርድ ተቀድቷል!',
      'image_ready': 'ምስሉ ተቆርጧል እና ለስካን ዝግጁ ነው።',
      'error_init': 'ሞዴሎችን ማስጀመር ላይ ስህተት: {error}',
      'error_pick_crop': 'ምስል ማምረጥ/መቆረጥ ላይ ስህተት: {error}',
      'error_generic': 'ስህተት: {error}',
      'error_saving_file': 'ፋይል ማስቀመጥ ላይ ስህተት: {error}',
      'saved_success': '{type} በተሳካ ሁኔታ ተቀምጧል',
      'share_subject': 'የአማርኛ OCR {type} ውጤት',
      'type_pdf': 'PDF',
      'type_text': 'ጽሑፍ',
      'lang_english': 'እንግሊዝኛ',
      'lang_amharic': 'አማርኛ',
    },
  };

  String _t(String key, {Map<String, String>? values}) {
    var value =
        _strings[_language]?[key] ?? _strings[AppLanguage.english]?[key] ?? key;
    if (values != null) {
      values.forEach((placeholder, replacement) {
        value = value.replaceAll('{$placeholder}', replacement);
      });
    }
    return value;
  }

  String _fileTypeLabel(String type) {
    switch (type) {
      case 'pdf':
        return _t('type_pdf');
      case 'txt':
        return _t('type_text');
      default:
        return type.toUpperCase();
    }
  }

  void _setLanguage(AppLanguage value) {
    if (value == _language) return;
    final previousLanguage = _language;
    final previousNoText = _strings[previousLanguage]?['no_text'];
    final previousImageReady = _strings[previousLanguage]?['image_ready'];

    setState(() {
      _language = value;
      if (_result == previousNoText) {
        _result = _t('no_text');
      } else if (_result == previousImageReady) {
        _result = _t('image_ready');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _result = _t('no_text');
    _initializeModels();
    _loadScanHistory();
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  Future<void> _initializeModels() async {
    _setProgress(true, 0.0);
    try {
      await _ocrProcessor.initialize();
    } catch (e) {
      _result = _t('error_init', values: {'error': e.toString()});
    } finally {
      _setProgress(false);
    }
  }

  void _setProgress(bool isProcessing, [double progress = 0.0]) {
    setState(() {
      _isProcessing = isProcessing;
      _progress = progress;
    });
  }

  Future<void> _loadScanHistory() async {
    _scanHistory = await _fileHandler.loadScanHistory();
    setState(() {});
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final image = await _fileHandler.pickImage(source);
      if (image != null) {
        final croppedFile = await Navigator.push<File?>(
          context,
          MaterialPageRoute(
            builder: (_) => CropYourImageScreen(imageFile: image),
          ),
        );

        if (croppedFile != null) {
          setState(() {
            _image = croppedFile;
            _showScanButton = true;
            _showSaveButtons = false;
            _result = _t('image_ready');
          });
        }
      }
    } catch (e) {
      setState(
        () => _result = _t('error_pick_crop', values: {'error': e.toString()}),
      );
    }
  }

  Future<void> startScanning() async {
    if (_image == null) return;

    _setProgress(true, 0.1);
    _showScanButton = false;
    _result = "";
    _hasScannedText = false;

    try {
      // Show initial progress
      _setProgress(true, 0.2);

      final recognizedText = await _ocrProcessor.recognizeText(_image!);

      _setProgress(true, 0.9);
      await Future.delayed(
        const Duration(milliseconds: 200),
      ); // Give UI time to catch up

      setState(() {
        _result = recognizedText;
        _showSaveButtons = true;
        _hasScannedText = true;
      });

      await _fileHandler.saveToHistory(recognizedText, _scanHistory);
      await _loadScanHistory();
    } catch (e) {
      setState(
        () => _result = _t('error_generic', values: {'error': e.toString()}),
      );
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      _setProgress(false);
    }
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _textEditingController.text = _result;
    });
  }

  void _saveEditedText() {
    setState(() {
      _result = _textEditingController.text;
      _isEditing = false;
    });
    _fileHandler.saveToHistory(_result, _scanHistory);
    Fluttertoast.showToast(msg: _t('changes_saved'));
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

  Future<void> _saveFile(String type) async {
    setState(() => _isProcessing = true);
    try {
      if (await Permission.storage.request().isGranted) {
        // First save the file
        final file =
            type == 'pdf'
                ? await _fileHandler.savePDF(_result)
                : await _fileHandler.saveTextFile(_result);

        // Then ask if user wants to share
        final shouldShare = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(
                  _t('saved_success', values: {'type': _fileTypeLabel(type)}),
                ),
                content: Text(_t('share_prompt')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(_t('no')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(_t('share')),
                  ),
                ],
              ),
        );

        if (shouldShare == true) {
          await Share.shareXFiles(
            [XFile(file.path)],
            subject: _t(
              'share_subject',
              values: {'type': _fileTypeLabel(type)},
            ),
          );
        }

        Fluttertoast.showToast(
          msg: _t('file_saved_downloads'),
          toastLength: Toast.LENGTH_SHORT,
        );
      } else {
        Fluttertoast.showToast(
          msg: _t('storage_permission_required'),
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: _t('error_saving_file', values: {'error': e.toString()}),
        backgroundColor: Colors.red,
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _copyToClipboard() async {
    await _fileHandler.copyToClipboard(_result);
    Fluttertoast.showToast(msg: _t('text_copied'));
  }

  Future<void> _showHistory() async {
    await _loadScanHistory();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(_t('scan_history')),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _scanHistory.length,
                itemBuilder:
                    (context, index) => ListTile(
                      title: Text(_scanHistory[index].first50Chars),
                      onTap: () {
                        setState(() {
                          _result = _scanHistory[index];
                          _showSaveButtons =
                              true; // Show save buttons when selecting from history
                        });
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder:
                                (ctx) => AlertDialog(
                                  title: Text(_t('delete_title')),
                                  content: Text(_t('delete_confirm')),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(ctx, false),
                                      child: Text(_t('cancel')),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(_t('delete')),
                                    ),
                                  ],
                                ),
                          );

                          if (confirm == true) {
                            _scanHistory.removeAt(index);
                            await _fileHandler.saveHistory(_scanHistory);
                            Navigator.pop(context); // Close the history dialog
                            _showHistory(); // Reopen updated history
                          }
                        },
                      ),
                    ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_t('close')),
              ),
            ],
          ),
    );
  }

  Widget _buildEditView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textEditingController,
              maxLines: null,
              expands: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: _t('edit_hint'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _cancelEditing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 171, 164, 164),
                ),
                child: Text(_t('cancel')),
              ),
              ElevatedButton(
                onPressed: _saveEditedText,
                child: Text(_t('save_changes')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileExportButtons() {
    if (!_showSaveButtons)
      return const SizedBox.shrink(); // Only show when there's scanned text

    return Column(
      children: [
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          label: Text(
            _t('save_as_pdf'),
            style: const TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 76, 99, 121),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => _saveFile('pdf'),
        ),
        const SizedBox(height: 15),
        ElevatedButton.icon(
          icon: const Icon(Icons.text_snippet, color: Colors.white),
          label: Text(
            _t('save_as_text'),
            style: const TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 76, 99, 121),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => _saveFile('txt'),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        const SizedBox(height: 8),
        Text(
          _progress > 0
              ? _t(
                'scanning',
                values: {'percent': (_progress * 100).round().toString()},
              )
              : _t('processing'),
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildMainContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pick Image buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed:
                      _isProcessing
                          ? null
                          : () => pickImage(ImageSource.gallery),
                  child: Text(
                    _t('gallery'),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed:
                      _isProcessing
                          ? null
                          : () => pickImage(ImageSource.camera),
                  child: Text(
                    _t('camera'),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Image preview
            if (_image != null)
              Column(
                children: [
                  GestureDetector(
                    onTap: _toggleFullScreen,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_image!, height: 200),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_showScanButton)
                    ElevatedButton(
                      onPressed: startScanning,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 76, 99, 121),
                      ),
                      child: Text(
                        _t('scan'),
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 20),

            // Progress bar
            if (_isProcessing) _buildProgressBar(),

            // Result display
            if (!_isProcessing && _result.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _t('recognized_text'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_hasScannedText)
                            IconButton(
                              icon: const Icon(Icons.content_copy),
                              onPressed: _copyToClipboard,
                              tooltip: _t('copy_text_tooltip'),
                            ),
                        ],
                      ),
                      if (_hasScannedText) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(_t('text_size')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Slider(
                                value: _recognizedTextSize,
                                min: 10,
                                max: 32,
                                divisions: 11,
                                label: _recognizedTextSize.round().toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _recognizedTextSize = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      SelectableText(
                        _result,
                        style: TextStyle(
                          fontSize: _recognizedTextSize,
                          fontFamily: "AbyssinicaSIL",
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            _buildFileExportButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenImage() {
    return Stack(
      children: [
        GestureDetector(
          onTap: _toggleFullScreen,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 1,
            maxScale: 4,
            child: Center(child: Image.file(_image!)),
          ),
        ),
        Positioned(
          top: 40,
          left: 20,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
            onPressed: _toggleFullScreen,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar:
          _isFullScreen
              ? null
              : AppBar(
                title: Text(_t('app_title')),
                centerTitle: true,
                leading:
                    Navigator.canPop(context)
                        ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        )
                        : null,
                actions: [
                  IconButton(
                    tooltip: isDarkMode ? _t('theme_light') : _t('theme_dark'),
                    icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
                    onPressed: () {
                      final nextMode =
                          isDarkMode ? ThemeMode.light : ThemeMode.dark;
                      widget.onThemeModeChanged(nextMode);
                    },
                  ),
                  PopupMenuButton<AppLanguage>(
                    icon: const Icon(Icons.language),
                    initialValue: _language,
                    itemBuilder:
                        (context) => [
                          PopupMenuItem(
                            value: AppLanguage.english,
                            child: Text(_t('lang_english')),
                          ),
                          PopupMenuItem(
                            value: AppLanguage.amharic,
                            child: Text(_t('lang_amharic')),
                          ),
                        ],
                    onSelected: _setLanguage,
                  ),
                  PopupMenuButton<String>(
                    itemBuilder:
                        (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(_t('edit_text')),
                          ),
                          PopupMenuItem(
                            value: 'history',
                            child: Text(_t('view_history')),
                          ),
                          PopupMenuItem(
                            value: 'copy',
                            child: Text(_t('copy_clipboard')),
                          ),
                          PopupMenuItem(
                            value: 'about',
                            child: Text(_t('about')),
                          ),
                        ],
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _startEditing();
                          break;
                        case 'history':
                          _showHistory();
                          break;
                        case 'copy':
                          _copyToClipboard();
                          break;
                        case 'about':
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => AboutPage(language: _language),
                            ),
                          );
                          break;
                      }
                    },
                  ),
                ],
              ),
      body:
          _isFullScreen
              ? _buildFullScreenImage()
              : _isEditing
              ? _buildEditView()
              : _buildMainContent(),
    );
  }
}
