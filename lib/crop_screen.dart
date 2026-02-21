import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
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
  late Uint8List imageBytes;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    imageBytes = await widget.imageFile.readAsBytes();
    setState(() => isLoading = false);
  }

  Future<void> _saveCroppedImage(Uint8List croppedData) async {
    final dir = await getTemporaryDirectory();
    final croppedFile = File(path.join(dir.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await croppedFile.writeAsBytes(croppedData);
    if (!mounted) return;
    Navigator.pop(context, croppedFile); // return cropped File
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Image'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _controller.crop(), // triggers crop
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Crop(
              image: imageBytes,
              controller: _controller,
              onCropped: _saveCroppedImage,
              aspectRatio: null, // null = freeform crop
              withCircleUi: false,
              baseColor: Colors.black,
              maskColor: Colors.black.withOpacity(0.6),
              cornerDotBuilder: (size, edgeAlignment) => const DotControl(),
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
