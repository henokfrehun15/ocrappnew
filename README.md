# ocrappnew

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Convert CRNN checkpoint to TFLite (AI Edge)

This project includes a converter script for your PyTorch CRNN checkpoint:

- Script: `tools/convert_crnn_ai_edge.py`
- Converter backend: `ai_edge_torch` (Google AI Edge Torch)

### 1) Install Python packages

```bash
pip install torch numpy ai-edge-torch-nightly
```

### 2) Run conversion

```bash
python tools/convert_crnn_ai_edge.py \
	--checkpoint path/to/best_amharic_word_ctc.pth \
	--out-tflite assets/models/new_amharic_crnn.tflite \
	--out-vocab assets/data/amharic_vocab.txt \
	--img-h 32 --img-w 160 --batch 1
```

### Notes

- Your Flutter OCR pipeline currently enforces fixed CRNN input shape `[1,3,32,160]`.
- Keep `--img-w 160` unless you also update Flutter preprocessing and tensor resizing logic.
