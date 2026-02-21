import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'dart:ui';
class OCRProcessor {
  Interpreter? _yoloInterpreter;
  Interpreter? _crnnInterpreter;
  List<String> _vocab = [];

  Future<void> initialize() async {
    _yoloInterpreter = await Interpreter.fromAsset('assets/models/new_amharic_yolo8s_last.tflite');
    _crnnInterpreter = await Interpreter.fromAsset('assets/models/new_amharic_crnn.tflite');
    _vocab = await _loadVocabulary();
  }

  Future<List<String>> _loadVocabulary() async {
    final vocabString = await rootBundle.loadString('assets/data/amharic_vocab.txt');
    final vocab = vocabString.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (!vocab.contains('<blank>')) vocab.insert(0, '<blank>');
    if (!vocab.contains(' ')) vocab.add(' ');
    return vocab;
  }

  Future<String> recognizeText(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(bytes)!;
    
    final detections = await _detectTextRegions(originalImage);
    if (detections.isEmpty) throw Exception("No text regions detected");
    
    return await _recognizeTextInRegions(originalImage, detections);
  }

  Future<List<Rect>> _detectTextRegions(img.Image image) async {
    final yoloImage = img.copyResize(image, width: 640, height: 640);
    final yoloInput = [
      List.generate(640, (y) => List.generate(640, (x) {
        final pixel = yoloImage.getPixel(x, y);
        return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
      }))
    ];

    final yoloOutput = List.generate(1, (_) => List.generate(5, (_) => List.filled(8400, 0.0)));
    _yoloInterpreter!.run(yoloInput, yoloOutput);

    return _parseYoloOutputWithNMS(yoloOutput[0], image.width, image.height);
  }

  double _iou(Rect a, Rect b) {
    final intersectionLeft = max(a.left, b.left);
    final intersectionTop = max(a.top, b.top);
    final intersectionRight = min(a.right, b.right);
    final intersectionBottom = min(a.bottom, b.bottom);

    if (intersectionRight <= intersectionLeft || intersectionBottom <= intersectionTop) {
      return 0.0;
    }
    final intersectionArea = (intersectionRight - intersectionLeft) * (intersectionBottom - intersectionTop);
    final aArea = (a.right - a.left) * (a.bottom - a.top);
    final bArea = (b.right - b.left) * (b.bottom - b.top);
    return intersectionArea / (aArea + bArea - intersectionArea);
  }

  List<Rect> _nonMaxSuppression(List<Rect> boxes, List<double> scores, double iouThresh) {
    if (boxes.isEmpty) return [];
    final indices = List<int>.generate(boxes.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final selected = <Rect>[];
    final active = List<bool>.filled(boxes.length, true);
    for (int i = 0; i < boxes.length; i++) {
      if (active[indices[i]]) {
        selected.add(boxes[indices[i]]);
        for (int j = i + 1; j < boxes.length; j++) {
          if (active[indices[j]] && _iou(boxes[indices[i]], boxes[indices[j]]) > iouThresh) {
            active[indices[j]] = false;
          }
        }
      }
    }
    return selected;
  }

  List<Rect> _parseYoloOutputWithNMS(List<List<double>> output, int imgW, int imgH,
      {double confThresh = 0.5, double iouThresh = 0.5}) {
    final boxes = <Rect>[];
    final scores = <double>[];

    for (int i = 0; i < output[0].length; i++) {
      final cx = output[0][i] * imgW;
      final cy = output[1][i] * imgH;
      final width = output[2][i] * imgW;
      final height = output[3][i] * imgH;
      final confidence = output[4][i];

      if (confidence > confThresh) {
        final left = (cx - width / 2).clamp(0, imgW - 1).toDouble();
        final top = (cy - height / 2).clamp(0, imgH - 1).toDouble();
        final right = (cx + width / 2).clamp(0, imgW - 1).toDouble();
        final bottom = (cy + height / 2).clamp(0, imgH - 1).toDouble();

        boxes.add(Rect.fromLTRB(left, top, right, bottom));
        scores.add(confidence);
      }
    }
    return _nonMaxSuppression(boxes, scores, iouThresh);
  }

  Future<String> _recognizeTextInRegions(img.Image image, List<Rect> detections) async {
    final lines = _sortDetectionsIntoLines(detections);
    final textLines = <String>[];

    for (final line in lines) {
      final words = <String>[];
      for (final box in line) {
        final word = await _recognizeWord(image, box);
        words.add(word);
      }
      textLines.add(_createTextLineWithSpacing(words, line));
    }

    final cleanedLines = textLines
    .map((line) => line.replaceAll(RegExp(r'\s{2,}'), ' ').trim())
    .toList();
    return cleanedLines.join('\n');

  }

  List<List<Rect>> _sortDetectionsIntoLines(List<Rect> boxes, {double lineThreshold = 10}) {
    boxes.sort((a, b) => a.top.compareTo(b.top));
    final lines = <List<Rect>>[];
    List<Rect> currentLine = [];

    for (final box in boxes) {
      if (currentLine.isEmpty) {
        currentLine.add(box);
      } else {
        if ((box.top - currentLine.last.top).abs() < lineThreshold) {
          currentLine.add(box);
        } else {
          currentLine.sort((a, b) => a.left.compareTo(b.left));
          lines.add(List.from(currentLine));
          currentLine = [box];
        }
      }
    }

    if (currentLine.isNotEmpty) {
      currentLine.sort((a, b) => a.left.compareTo(b.left));
      lines.add(currentLine);
    }

    return lines;
  }

  img.Image _resizeAndPad(img.Image src, int targetW, int targetH) {
    final ratio = min(targetW / src.width, targetH / src.height);
    final newW = (src.width * ratio).round();
    final newH = (src.height * ratio).round();
    final resized = img.copyResize(src, width: newW, height: newH);
    final padded = img.Image(width: targetW, height: targetH);

    final white = img.ColorRgb8(255, 255, 255);
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        padded.setPixel(x, y, white);
      }
    }
    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        padded.setPixel(
          ((targetW - newW) ~/ 2) + x,
          ((targetH - newH) ~/ 2) + y,
          resized.getPixel(x, y),
        );
      }
    }
    return padded;
  }

  Future<String> _recognizeWord(img.Image image, Rect box) async {
    try {
      final wordImage = img.copyCrop(
        image,
        x: box.left.toInt(),
        y: box.top.toInt(),
        width: box.width.toInt(),
        height: box.height.toInt(),
      );

      final paddedWordImage = _resizeAndPad(wordImage, 128, 32);
      final crnnInputRaw = _prepareCrnnInput(paddedWordImage);
      final crnnInput = [crnnInputRaw];

      final crnnOutput = List.generate(31, (_) => List.generate(1, (_) => List.filled(586, 0.0)));
      _crnnInterpreter!.run(crnnInput, crnnOutput);

      final output2D = [for (var i = 0; i < 31; i++) crnnOutput[i][0]];
      return _decodeCrnnOutput(output2D);
    } catch (e) {
      return "?";
    }
  }

  Float32List _prepareCrnnInput(img.Image image) {
    final gray = _convertToGrayscale(image);
    final input = Float32List(1 * 32 * 128);
    int pixelIndex = 0;
    
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 128; x++) {
        input[pixelIndex++] = (gray.getPixel(x, y).r / 127.5) - 1.0;
      }
    }
    return input;
  }

  img.Image _convertToGrayscale(img.Image image) {
    final gray = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        gray.setPixelRgb(x, y, luminance, luminance, luminance);
      }
    }
    return gray;
  }

  String _decodeCrnnOutput(List<List<double>> output) {
    final buffer = StringBuffer();
    int lastIndex = -1;
    final blankIndex = _vocab.indexOf('<blank>');

    for (final timestep in output) {
      double maxProb = timestep[0];
      int maxIndex = 0;
      for (int i = 1; i < timestep.length; i++) {
        if (timestep[i] > maxProb) {
          maxProb = timestep[i];
          maxIndex = i;
        }
      }

      if (maxIndex != lastIndex && maxIndex != blankIndex && maxIndex < _vocab.length) {
        buffer.write(_vocab[maxIndex]);
      }
      lastIndex = maxIndex;
    }

    return buffer.toString();
  }

  String _createTextLineWithSpacing(List<String> words, List<Rect> boxes, {double spaceScale = 10.0}) {
    if (words.isEmpty) return "";

    final buffer = StringBuffer();
    buffer.write(words[0]);
    double prevX2 = boxes[0].right;

    for (int i = 1; i < words.length; i++) {
      final gapPixels = boxes[i].left - prevX2;
      final numSpaces = gapPixels > 0 ? (gapPixels / spaceScale).round().clamp(1, 1000) : 1;
      buffer.write(' ' * numSpaces + words[i]);
      prevX2 = boxes[i].right;
    }

    return buffer.toString().replaceAll(RegExp(r' (?=\S)'), '');
  }
} 