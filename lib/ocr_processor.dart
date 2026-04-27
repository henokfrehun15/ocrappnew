import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui';

class OCRRegionResult {
  OCRRegionResult({
    required this.box,
    required this.text,
    required this.confidence,
  });

  final Rect box;
  final String text;
  final double confidence;
}

class OCRPageResult {
  OCRPageResult({
    required this.imageFile,
    required this.text,
    required this.regions,
    required this.confidence,
  });

  final File imageFile;
  final String text;
  final List<OCRRegionResult> regions;
  final double confidence;
}

class OCRBatchResult {
  OCRBatchResult({required this.pages});

  final List<OCRPageResult> pages;

  String get combinedText => pages.map((p) => p.text).join('\n\n');
}

class _WordRecognitionResult {
  _WordRecognitionResult({required this.text, required this.confidence});

  final String text;
  final double confidence;
}

class OCRProcessor {
  Interpreter? _yoloInterpreter;
  Interpreter? _crnnInterpreter;
  List<String> _vocab = [];
  static const double _yoloConfThreshold = 0.35;
  static const double _yoloIouThreshold = 0.5;
  static const int _minBoxWidth = 12;
  static const int _minBoxHeight = 12;
  static const int _minBoxArea = 180;
  static const double _maxBoxAreaRatio = 0.40;
  static const int _maxDetections = 350;
  static const double _cropPaddingRatio = 0.08;
  static const int _minCropPaddingPx = 2;
  static const int _defaultCrnnHeight = 32;
  static const int _defaultCrnnMaxWidth = 320;

  Future<void> initialize() async {
    _yoloInterpreter = await Interpreter.fromAsset(
      'assets/models/new_amharic_yolo8s_last.tflite',
    );
    _crnnInterpreter = await Interpreter.fromAsset(
      'assets/models/ocr_fixed_tcn_ctc.tflite',
    );
    _crnnInterpreter!.allocateTensors();
    _vocab = await _loadVocabulary();
    _logCrnnTensorInfo();
  }

  void _logCrnnTensorInfo() {
    try {
      final inShape = _crnnInterpreter!.getInputTensor(0).shape;
      final outShape = _crnnInterpreter!.getOutputTensor(0).shape;
      debugPrint('CRNN input shape: $inShape, output shape: $outShape');
    } catch (_) {}
  }

  Future<List<String>> _loadVocabulary() async {
    final vocabString = await rootBundle.loadString(
      'assets/data/awam_vocab.txt',
    );
    final base =
        vocabString
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final seen = <String>{};
    final ordered = <String>[];
    for (final token in base) {
      if (token == '<blank>') continue;
      if (seen.add(token)) ordered.add(token);
    }

    const extraTokens = [
      ' ',
      '.',
      ',',
      '?',
      '!',
      '።',
      '፣',
      '፤',
      '፥',
      '፦',
      '(',
      ')',
      '-',
      '—',
      '"',
      "'",
    ];
    for (final token in extraTokens) {
      if (seen.add(token)) ordered.add(token);
    }

    if (seen.add('<unk>')) ordered.add('<unk>');
    return ['<blank>', ...ordered];
  }

  Future<String> recognizeText(File imageFile) async {
    final result = await recognizeTextDetailed(imageFile);
    return result.text;
  }

  Future<OCRPageResult> recognizeTextDetailed(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(bytes)!;

    final detections = await _detectTextRegions(originalImage);
    if (detections.isEmpty) throw Exception("No text regions detected");

    return await _recognizeTextInRegions(originalImage, detections, imageFile);
  }

  Future<OCRBatchResult> recognizeTextBatch(List<File> imageFiles) async {
    final pages = <OCRPageResult>[];
    for (final file in imageFiles) {
      pages.add(await recognizeTextDetailed(file));
    }
    return OCRBatchResult(pages: pages);
  }

  Future<List<Rect>> _detectTextRegions(img.Image image) async {
    final yoloImage = img.copyResize(image, width: 640, height: 640);
    final yoloInput = [
      List.generate(
        640,
        (y) => List.generate(640, (x) {
          final pixel = yoloImage.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    ];

    final outputShape = _yoloInterpreter!.getOutputTensor(0).shape;
    final yoloOutput = _createNestedFloatBuffer(outputShape);
    _yoloInterpreter!.run(yoloInput, yoloOutput);

    final detections = _parseYoloOutputWithNMS(
      yoloOutput,
      outputShape,
      image.width,
      image.height,
      confThresh: _yoloConfThreshold,
      iouThresh: _yoloIouThreshold,
    );

    if (detections.length <= _maxDetections) {
      return detections;
    }
    return detections.take(_maxDetections).toList(growable: false);
  }

  double _iou(Rect a, Rect b) {
    final intersectionLeft = max(a.left, b.left);
    final intersectionTop = max(a.top, b.top);
    final intersectionRight = min(a.right, b.right);
    final intersectionBottom = min(a.bottom, b.bottom);

    if (intersectionRight <= intersectionLeft ||
        intersectionBottom <= intersectionTop) {
      return 0.0;
    }
    final intersectionArea =
        (intersectionRight - intersectionLeft) *
        (intersectionBottom - intersectionTop);
    final aArea = (a.right - a.left) * (a.bottom - a.top);
    final bArea = (b.right - b.left) * (b.bottom - b.top);
    return intersectionArea / (aArea + bArea - intersectionArea);
  }

  List<Rect> _nonMaxSuppression(
    List<Rect> boxes,
    List<double> scores,
    double iouThresh,
  ) {
    if (boxes.isEmpty) return [];
    final indices = List<int>.generate(boxes.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final selected = <Rect>[];
    final active = List<bool>.filled(boxes.length, true);
    for (int i = 0; i < boxes.length; i++) {
      if (active[indices[i]]) {
        selected.add(boxes[indices[i]]);
        for (int j = i + 1; j < boxes.length; j++) {
          if (active[indices[j]] &&
              _iou(boxes[indices[i]], boxes[indices[j]]) > iouThresh) {
            active[indices[j]] = false;
          }
        }
      }
    }
    return selected;
  }

  List<Rect> _parseYoloOutputWithNMS(
    Object rawOutput,
    List<int> outputShape,
    int imgW,
    int imgH, {
    double confThresh = 0.25,
    double iouThresh = 0.5,
    int? wordClassId,
  }) {
    final boxes = <Rect>[];
    final scores = <double>[];
    final rows = _extractYoloRows(rawOutput, outputShape);

    for (final row in rows) {
      if (row.length < 4) continue;

      final cxRaw = row[0];
      final cyRaw = row[1];
      final widthRaw = row[2].abs();
      final heightRaw = row[3].abs();

      int? classId;
      double confidence;

      if (row.length == 4) {
        confidence = 1.0;
      } else if (row.length == 5) {
        confidence = row[4];
      } else {
        final objectness = row[4];
        final classScores = row.sublist(5);
        var bestClassScore = double.negativeInfinity;
        var bestClassIndex = -1;
        for (var i = 0; i < classScores.length; i++) {
          if (classScores[i] > bestClassScore) {
            bestClassScore = classScores[i];
            bestClassIndex = i;
          }
        }

        classId = bestClassIndex;
        if (wordClassId != null && classId != wordClassId) {
          continue;
        }

        final hasObjectness = objectness >= 0.0 && objectness <= 1.0;
        confidence =
            hasObjectness && bestClassScore.isFinite
                ? objectness * bestClassScore
                : (bestClassScore.isFinite ? bestClassScore : objectness);
      }

      if (!confidence.isFinite || confidence < confThresh) continue;

      final isNormalized = _isLikelyNormalizedBox(
        cxRaw,
        cyRaw,
        widthRaw,
        heightRaw,
      );

      final cx = isNormalized ? cxRaw * imgW : cxRaw;
      final cy = isNormalized ? cyRaw * imgH : cyRaw;
      final width = isNormalized ? widthRaw * imgW : widthRaw;
      final height = isNormalized ? heightRaw * imgH : heightRaw;

      if (width < _minBoxWidth || height < _minBoxHeight) continue;

      final area = width * height;
      if (area < _minBoxArea) continue;
      if (area > (imgW * imgH * _maxBoxAreaRatio)) continue;

      final left = (cx - width / 2).clamp(0, imgW - 1).toDouble();
      final top = (cy - height / 2).clamp(0, imgH - 1).toDouble();
      final right = (cx + width / 2).clamp(0, imgW - 1).toDouble();
      final bottom = (cy + height / 2).clamp(0, imgH - 1).toDouble();

      if (right <= left || bottom <= top) continue;

      boxes.add(Rect.fromLTRB(left, top, right, bottom));
      scores.add(confidence);
    }

    return _nonMaxSuppression(boxes, scores, iouThresh);
  }

  bool _isLikelyNormalizedBox(
    double cx,
    double cy,
    double width,
    double height,
  ) {
    return cx >= 0.0 &&
        cy >= 0.0 &&
        width >= 0.0 &&
        height >= 0.0 &&
        cx <= 2.0 &&
        cy <= 2.0 &&
        width <= 2.0 &&
        height <= 2.0;
  }

  List<List<double>> _extractYoloRows(Object rawOutput, List<int> shape) {
    List<double> toDoubleList(List<dynamic> values) {
      return values.map((v) => (v as num).toDouble()).toList();
    }

    if (shape.length == 4 && shape[0] == 1 && shape[1] == 1) {
      final list4 = rawOutput as List;
      return _extractYoloRows((list4[0] as List)[0], [shape[2], shape[3]]);
    }

    if (shape.length == 3 && shape[0] == 1) {
      final list3 = (rawOutput as List)[0] as List;
      final dim1 = shape[1];
      final dim2 = shape[2];

      if (dim1 < dim2) {
        final byAttr = list3
            .map((e) => (e as List).cast<dynamic>())
            .toList(growable: false);
        return List.generate(
          dim2,
          (pred) => List.generate(
            dim1,
            (attr) => (byAttr[attr][pred] as num).toDouble(),
          ),
        );
      }

      return list3
          .map((row) => toDoubleList((row as List).cast<dynamic>()))
          .toList();
    }

    if (shape.length == 2) {
      final list2 = rawOutput as List;
      final dim0 = shape[0];
      final dim1 = shape[1];

      if (dim0 < dim1) {
        final byAttr = list2
            .map((e) => (e as List).cast<dynamic>())
            .toList(growable: false);
        return List.generate(
          dim1,
          (pred) => List.generate(
            dim0,
            (attr) => (byAttr[attr][pred] as num).toDouble(),
          ),
        );
      }

      return list2
          .map((row) => toDoubleList((row as List).cast<dynamic>()))
          .toList();
    }

    if (shape.length == 3) {
      final list3 = rawOutput as List;
      return list3
          .map((row) => toDoubleList((row as List).cast<dynamic>()))
          .toList();
    }

    return const <List<double>>[];
  }

  Future<OCRPageResult> _recognizeTextInRegions(
    img.Image image,
    List<Rect> detections,
    File imageFile,
  ) async {
    final orderedBoxes = _sortBoxesReadingOrder(detections);
    final outputs = <OCRRegionResult>[];

    for (final box in orderedBoxes) {
      final word = await _recognizeWord(image, box);
      final text = word.text.trim();
      if (text.isNotEmpty) {
        outputs.add(
          OCRRegionResult(box: box, text: text, confidence: word.confidence),
        );
      }
    }

    final text = _outputsToPageText(outputs);
    final confidence =
        outputs.isEmpty
            ? 0.0
            : outputs.map((o) => o.confidence).reduce((a, b) => a + b) /
                outputs.length;

    return OCRPageResult(
      imageFile: imageFile,
      text: text,
      regions: outputs,
      confidence: confidence,
    );
  }

  List<Rect> _sortBoxesReadingOrder(
    List<Rect> boxes, {
    double lineThresholdRatio = 0.6,
  }) {
    if (boxes.isEmpty) return [];

    final yCenters = boxes.map((b) => (b.top + b.bottom) / 2.0).toList();
    final heights = boxes.map((b) => b.height).toList();
    final medH = _median(heights);
    final threshold = max(5.0, lineThresholdRatio * medH);

    final indices = List<int>.generate(boxes.length, (i) => i)
      ..sort((a, b) => yCenters[a].compareTo(yCenters[b]));

    final lines = <Map<String, Object>>[];
    for (final idx in indices) {
      final yc = yCenters[idx];
      var placed = false;

      for (final line in lines) {
        final yMean = line['yMean'] as double;
        if ((yc - yMean).abs() <= threshold) {
          final idxs = line['idxs'] as List<int>;
          idxs.add(idx);
          final mean =
              idxs
                  .map((i) => yCenters[i])
                  .reduce((value, element) => value + element) /
              idxs.length;
          line['yMean'] = mean;
          placed = true;
          break;
        }
      }

      if (!placed) {
        lines.add({
          'yMean': yc,
          'idxs': <int>[idx],
        });
      }
    }

    lines.sort(
      (a, b) => (a['yMean'] as double).compareTo(b['yMean'] as double),
    );

    final ordered = <Rect>[];
    for (final line in lines) {
      final idxs =
          (line['idxs'] as List<int>)
            ..sort((a, b) => boxes[a].left.compareTo(boxes[b].left));
      ordered.addAll(idxs.map((i) => boxes[i]));
    }

    return ordered;
  }

  String _outputsToPageText(
    List<OCRRegionResult> outputs, {
    double lineThresholdRatio = 0.6,
  }) {
    if (outputs.isEmpty) return '';

    final heights = outputs.map((o) => o.box.height).toList();
    final medH = _median(heights);
    final threshold = max(5.0, lineThresholdRatio * medH);

    final lines = <Map<String, dynamic>>[];
    for (final output in outputs) {
      final box = output.box;
      final yc = (box.top + box.bottom) / 2.0;
      final txt = output.text.trim();
      if (txt.isEmpty) continue;

      var placed = false;
      for (final line in lines) {
        final yMean = line['yMean'] as double;
        if ((yc - yMean).abs() <= threshold) {
          final items = line['items'] as List<Map<String, Object>>;
          items.add({'x': box.left, 'text': txt, 'yc': yc});
          final mean =
              items
                  .map((it) => it['yc'] as double)
                  .reduce((value, element) => value + element) /
              items.length;
          line['yMean'] = mean;
          placed = true;
          break;
        }
      }

      if (!placed) {
        lines.add({
          'yMean': yc,
          'items': [
            {'x': box.left, 'text': txt, 'yc': yc},
          ],
        });
      }
    }

    lines.sort(
      (a, b) => (a['yMean'] as double).compareTo(b['yMean'] as double),
    );

    final pageLines = <String>[];
    for (final line in lines) {
      final items =
          line['items'] as List<Map<String, Object>>
            ..sort((a, b) => (a['x'] as double).compareTo(b['x'] as double));
      final words = items.map((it) => it['text'] as String).toList();
      pageLines.add(words.join(' '));
    }

    return pageLines.join('\n');
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 10.0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  img.Image _resizeVariableWidth(
    img.Image src,
    int targetH,
    int minW,
    int maxW,
  ) {
    final sourceH = max(src.height, 1);
    final sourceW = max(src.width, 1);
    final rawW = (targetH * (sourceW / sourceH)).round();
    final targetW = rawW.clamp(minW, maxW);
    return img.copyResize(src, width: targetW, height: targetH);
  }

  Future<_WordRecognitionResult> _recognizeWord(
    img.Image image,
    Rect box,
  ) async {
    try {
      final padX = max(
        _minCropPaddingPx,
        (box.width * _cropPaddingRatio).round(),
      );
      final padY = max(
        _minCropPaddingPx,
        (box.height * _cropPaddingRatio).round(),
      );

      final left = (box.left.floor() - padX).clamp(0, image.width - 1);
      final top = (box.top.floor() - padY).clamp(0, image.height - 1);
      final right = (box.right.ceil() + padX).clamp(1, image.width);
      final bottom = (box.bottom.ceil() + padY).clamp(1, image.height);

      final cropW = max(1, right - left);
      final cropH = max(1, bottom - top);
      final wordImage = img.copyCrop(
        image,
        x: left,
        y: top,
        width: cropW,
        height: cropH,
      );

      return _runCrnnStrict(wordImage);
    } catch (e) {
      debugPrint('OCR word decode failed: $e');
      return _WordRecognitionResult(text: '', confidence: 0.0);
    }
  }

  _WordRecognitionResult _runCrnnStrict(img.Image wordImage) {
    final currentShape = List<int>.from(
      _crnnInterpreter!.getInputTensor(0).shape,
    );
    final resolvedShape = _resolveDynamicCrnnInputShape(currentShape);
    if (!_sameShape(currentShape, resolvedShape)) {
      try {
        _crnnInterpreter!.resizeInputTensor(0, resolvedShape);
        _crnnInterpreter!.allocateTensors();
      } catch (_) {}
    }

    final inputShape = List<int>.from(
      _crnnInterpreter!.getInputTensor(0).shape,
    );
    final targetHeight =
        _getInputHeight(inputShape) > 0
            ? _getInputHeight(inputShape)
            : _defaultCrnnHeight;
    final targetWidth =
        _getRawInputWidth(inputShape) > 0
            ? _getRawInputWidth(inputShape)
            : _defaultCrnnMaxWidth;

    final transformed = _resizeVariableWidth(
      wordImage,
      targetHeight,
      1,
      targetWidth,
    );

    final liveInputShape = _crnnInterpreter!.getInputTensor(0).shape;
    final liveOutputShape = _crnnInterpreter!.getOutputTensor(0).shape;
    final fixedWidth =
        _getRawInputWidth(liveInputShape) > 0
            ? _getRawInputWidth(liveInputShape)
            : targetWidth;
    final input = _buildStrictCrnnInput(
      transformed,
      liveInputShape,
      fixedWidth,
    );
    final output = _createNestedFloatBuffer(liveOutputShape);

    _crnnInterpreter!.run(input, output);
    final output2D = _extractTimeClassMatrix(output, liveOutputShape);
    return _decodeCrnnOutput(output2D);
  }

  List<int> _resolveDynamicCrnnInputShape(List<int> shape) {
    if (shape.isEmpty) return [1, _defaultCrnnHeight, _defaultCrnnMaxWidth, 1];

    final resolved = List<int>.from(shape);
    var hasDynamic = false;
    for (final dim in resolved) {
      if (dim <= 0) {
        hasDynamic = true;
        break;
      }
    }
    if (!hasDynamic) return resolved;

    if (resolved.length >= 4) {
      final isNchw = _isNchwLayout(resolved);
      resolved[0] = resolved[0] > 0 ? resolved[0] : 1;
      if (isNchw) {
        resolved[1] = resolved[1] > 0 ? resolved[1] : 1;
        resolved[2] = resolved[2] > 0 ? resolved[2] : _defaultCrnnHeight;
        resolved[3] = resolved[3] > 0 ? resolved[3] : _defaultCrnnMaxWidth;
      } else {
        resolved[1] = resolved[1] > 0 ? resolved[1] : _defaultCrnnHeight;
        resolved[2] = resolved[2] > 0 ? resolved[2] : _defaultCrnnMaxWidth;
        resolved[3] = resolved[3] > 0 ? resolved[3] : 1;
      }
      return resolved;
    }

    for (var i = 0; i < resolved.length; i++) {
      if (resolved[i] <= 0) {
        resolved[i] = 1;
      }
    }
    return resolved;
  }

  bool _sameShape(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Object _buildStrictCrnnInput(
    img.Image resizedGraySource,
    List<int> liveInputShape,
    int targetWidth,
  ) {
    final isNchw = _isNchwLayout(liveInputShape);
    final channels = _getInputChannels(liveInputShape);
    final targetHeight =
        _getInputHeight(liveInputShape) > 0
            ? _getInputHeight(liveInputShape)
            : _defaultCrnnHeight;
    final gray = _convertToGrayscale(resizedGraySource);

    double valueAt(int x, int y) {
      if (x >= gray.width || y >= gray.height) return 1.0;
      return (gray.getPixel(x, y).r / 127.5) - 1.0;
    }

    if (isNchw) {
      return [
        List.generate(channels, (_) {
          return List.generate(targetHeight, (y) {
            return List.generate(targetWidth, (x) => valueAt(x, y));
          });
        }),
      ];
    }

    return [
      List.generate(targetHeight, (y) {
        return List.generate(targetWidth, (x) {
          final v = valueAt(x, y);
          if (channels <= 1) return [v];
          return List<double>.filled(channels, v);
        });
      }),
    ];
  }

  int _getRawInputWidth(List<int> shape) {
    if (shape.length >= 4) {
      if (shape[1] > 0 && shape[1] <= 8) return shape[3];
      return shape[2];
    }
    if (shape.length == 3) {
      return shape[1];
    }
    return -1;
  }

  int _getInputHeight(List<int> shape) {
    if (shape.length >= 4) {
      if (shape[1] > 0 && shape[1] <= 8) {
        return shape[2] > 0 ? shape[2] : _defaultCrnnHeight;
      }
      return shape[1] > 0 ? shape[1] : _defaultCrnnHeight;
    }
    if (shape.length == 3) {
      return shape[0] > 0 ? shape[0] : _defaultCrnnHeight;
    }
    return _defaultCrnnHeight;
  }

  int _getInputChannels(List<int> shape) {
    if (shape.length >= 4) {
      if (shape[1] > 0 && shape[1] <= 8) return shape[1];
      return shape[3] > 0 ? shape[3] : 1;
    }
    if (shape.length == 3) {
      return shape[2] > 0 ? shape[2] : 1;
    }
    return 1;
  }

  bool _isNchwLayout(List<int> shape) {
    if (shape.length < 4) return false;
    final channelsFirst = shape[1] > 0 && shape[1] <= 8;
    final channelsLast = shape[3] > 0 && shape[3] <= 8;
    if (channelsFirst && !channelsLast) return true;
    if (channelsLast && !channelsFirst) return false;
    return false;
  }

  Object _createNestedFloatBuffer(List<int> shape, [int index = 0]) {
    if (shape.isEmpty) return [];
    if (index == shape.length - 1) {
      final size = shape[index] > 0 ? shape[index] : 1;
      return List<double>.filled(size, 0.0);
    }
    final size = shape[index] > 0 ? shape[index] : 1;
    return List.generate(
      size,
      (_) => _createNestedFloatBuffer(shape, index + 1),
    );
  }

  List<List<double>> _extractTimeClassMatrix(Object output, List<int> shape) {
    List<double> toDoubleList(List<dynamic> values) {
      return values.map((v) => (v as num).toDouble()).toList();
    }

    if (shape.length == 3) {
      if (shape[0] == 1) {
        final asList = output as List;
        return (asList[0] as List)
            .map((row) => toDoubleList((row as List).cast<dynamic>()))
            .toList();
      }
      if (shape[1] == 1) {
        final asList = output as List;
        return asList
            .map(
              (t) => toDoubleList((((t as List)[0] as List).cast<dynamic>())),
            )
            .toList();
      }
      final asList = output as List;
      return asList
          .map((row) => toDoubleList((row as List).cast<dynamic>()))
          .toList();
    }

    if (shape.length == 2) {
      final asList = output as List;
      return asList
          .map((row) => toDoubleList((row as List).cast<dynamic>()))
          .toList();
    }

    if (shape.length == 4 && shape[0] == 1 && shape[1] == 1) {
      final asList = output as List;
      return ((asList[0] as List)[0] as List)
          .map((row) => toDoubleList((row as List).cast<dynamic>()))
          .toList();
    }

    return [];
  }

  final List<String> _specialTokens = const ['<blank>', '<unk>'];

  bool _isSpecialToken(String token) {
    return _specialTokens.contains(token);
  }

  String _safeVocabAt(int index) {
    if (index < 0 || index >= _vocab.length) return '';
    final token = _vocab[index];
    if (_isSpecialToken(token)) return '';
    return token;
  }

  _WordRecognitionResult _decodeCrnnOutput(List<List<double>> output) {
    if (output.isEmpty)
      return _WordRecognitionResult(text: '', confidence: 0.0);

    final buffer = StringBuffer();
    int lastIndex = -1;
    final blankIndex = _vocab.indexOf('<blank>');
    double confidenceSum = 0.0;
    int confidenceCount = 0;

    for (final timestep in output) {
      if (timestep.isEmpty) continue;

      double maxProb = timestep[0];
      int maxIndex = 0;
      for (int i = 1; i < timestep.length; i++) {
        if (timestep[i] > maxProb) {
          maxProb = timestep[i];
          maxIndex = i;
        }
      }

      if (maxIndex != lastIndex && maxIndex != blankIndex) {
        buffer.write(_safeVocabAt(maxIndex));
        confidenceSum += maxProb;
        confidenceCount++;
      }
      lastIndex = maxIndex;
    }

    return _WordRecognitionResult(
      text: buffer.toString(),
      confidence: confidenceCount == 0 ? 0.0 : confidenceSum / confidenceCount,
    );
  }

  img.Image _convertToGrayscale(img.Image image) {
    final gray = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        gray.setPixelRgb(x, y, luminance, luminance, luminance);
      }
    }
    return gray;
  }
}
