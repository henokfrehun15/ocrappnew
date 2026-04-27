import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CropYourImageScreen extends StatefulWidget {
  final File imageFile;

  const CropYourImageScreen({super.key, required this.imageFile});

  @override
  State<CropYourImageScreen> createState() => _CropYourImageScreenState();
}

class _CropYourImageScreenState extends State<CropYourImageScreen> {
  final CropController _controller = CropController();
  late Uint8List _originalBytes;
  late Uint8List _imageBytes;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      final prepared =
          decoded == null
              ? bytes
              : Uint8List.fromList(
                img.encodeJpg(img.bakeOrientation(decoded), quality: 95),
              );

      if (!mounted) return;
      setState(() {
        _originalBytes = Uint8List.fromList(prepared);
        _imageBytes = Uint8List.fromList(prepared);
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _updateImageBytes(
    img.Image Function(img.Image image) transform,
  ) async {
    final decoded = img.decodeImage(_imageBytes);
    if (decoded == null) return;

    final updated = transform(decoded);
    final encoded = Uint8List.fromList(img.encodeJpg(updated, quality: 95));

    if (!mounted) return;
    setState(() {
      _imageBytes = encoded;
    });
  }

  Future<void> _rotateLeft() async {
    await _updateImageBytes((image) => img.copyRotate(image, angle: -90));
  }

  Future<void> _rotateRight() async {
    await _updateImageBytes((image) => img.copyRotate(image, angle: 90));
  }

  void _resetImage() {
    if (_isLoading) return;
    setState(() {
      _imageBytes = Uint8List.fromList(_originalBytes);
    });
  }

  Future<void> _saveCroppedImage(Uint8List croppedData) async {
    final dir = await getTemporaryDirectory();
    final croppedFile = File(
      path.join(
        dir.path,
        'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    await croppedFile.writeAsBytes(croppedData);
    if (!mounted) return;
    Navigator.pop(context, croppedFile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Image'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restore),
            onPressed: _isLoading ? null : _resetImage,
          ),
          IconButton(
            tooltip: 'Rotate left',
            icon: const Icon(Icons.rotate_left),
            onPressed: _isLoading ? null : _rotateLeft,
          ),
          IconButton(
            tooltip: 'Rotate right',
            icon: const Icon(Icons.rotate_right),
            onPressed: _isLoading ? null : _rotateRight,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _controller.crop,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load image: $_loadError',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
              : Column(
                children: [
                  Expanded(
                    child: Crop(
                      image: _imageBytes,
                      controller: _controller,
                      onCropped: _saveCroppedImage,
                      aspectRatio: null,
                      withCircleUi: false,
                      baseColor: Colors.black,
                      maskColor: Colors.black.withOpacity(0.6),
                      cornerDotBuilder:
                          (size, edgeAlignment) => const DotControl(),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _rotateLeft,
                            icon: const Icon(Icons.rotate_left),
                            label: const Text('Left'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _resetImage,
                            icon: const Icon(Icons.restore),
                            label: const Text('Reset'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _rotateRight,
                            icon: const Icon(Icons.rotate_right),
                            label: const Text('Right'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class DotControl extends StatelessWidget {
  const DotControl({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
    );
  }
}
