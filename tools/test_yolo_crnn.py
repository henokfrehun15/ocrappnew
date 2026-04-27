import argparse
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
import torch
import torch.nn as nn
import torch.nn.functional as F
from ultralytics import YOLO


@dataclass
class CFG:
    img_h: int = 32
    img_w: int = 384
    conf: float = 0.25
    iou: float = 0.50


class Residual(nn.Module):
    def __init__(self, in_c: int, out_c: int, s: int = 1):
        super().__init__()
        self.conv1 = nn.Conv2d(in_c, out_c, 3, s, 1)
        self.conv2 = nn.Conv2d(out_c, out_c, 3, 1, 1)
        self.skip = nn.Conv2d(in_c, out_c, 1, s) if s != 1 or in_c != out_c else nn.Identity()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return F.silu(self.conv2(F.silu(self.conv1(x))) + self.skip(x))


class PosEnc(nn.Module):
    def __init__(self, d: int):
        super().__init__()
        pe = torch.zeros(1000, d)
        pos = torch.arange(0, 1000).unsqueeze(1)
        div = torch.exp(torch.arange(0, d, 2) * (-math.log(10000) / d))
        pe[:, 0::2] = torch.sin(pos * div)
        pe[:, 1::2] = torch.cos(pos * div)
        self.register_buffer("pe", pe.unsqueeze(1), persistent=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x + self.pe[: x.size(0)]


class OCR(nn.Module):
    def __init__(self, num_classes: int):
        super().__init__()
        self.cnn = nn.Sequential(
            nn.Conv2d(1, 64, 3, 1, 1),
            nn.MaxPool2d(2),
            Residual(64, 128, 2),
            Residual(128, 256, 2),
            Residual(256, 256),
        )
        self.pool = nn.AdaptiveAvgPool2d((1, None))
        self.pos = PosEnc(256)
        enc_layer = nn.TransformerEncoderLayer(256, 8, 512, 0.1)
        self.tr = nn.TransformerEncoder(enc_layer, 4)
        self.fc = nn.Linear(256, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.cnn(x)
        x = self.pool(x).squeeze(2)
        x = x.permute(2, 0, 1)
        x = self.pos(x)
        x = self.tr(x)
        x = self.fc(x)
        return F.log_softmax(x, 2)


def build_vocab(path: Path):
    chars = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    vocab = ["<blank>"] + list(dict.fromkeys(chars)) + ["<unk>"]
    idx2char = {idx: ch for idx, ch in enumerate(vocab)}
    char2idx = {ch: idx for idx, ch in idx2char.items()}
    return vocab, char2idx, idx2char


def preprocess_crop(crop: Image.Image, cfg: CFG) -> torch.Tensor:
    crop = crop.convert("L")
    w, h = crop.size
    new_w = min(cfg.img_w, int(cfg.img_h * (w / max(h, 1))))
    crop = crop.resize((max(new_w, 1), cfg.img_h))

    canvas = Image.new("L", (cfg.img_w, cfg.img_h), 255)
    canvas.paste(crop, (0, 0))

    arr = np.array(canvas, dtype=np.float32) / 255.0
    arr = (arr - 0.5) / 0.5
    return torch.from_numpy(arr).unsqueeze(0).unsqueeze(0)


def decode(out: torch.Tensor, idx2char: dict[int, str], blank_idx: int = 0) -> str:
    pred = out.argmax(2).permute(1, 0)
    seq = pred[0]
    prev = -1
    txt = []
    for idx in seq:
        i = idx.item()
        if i != prev and i != blank_idx:
            ch = idx2char.get(i, "")
            if ch not in ("<unk>", "<blank>"):
                txt.append(ch)
        prev = i
    return "".join(txt)


def sort_boxes_reading_order(boxes: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int, int]]:
    if not boxes:
        return []
    heights = [max(1, y2 - y1) for x1, y1, x2, y2 in boxes]
    med_h = float(np.median(heights)) if heights else 10.0
    threshold = max(5.0, 0.6 * med_h)

    y_centers = [((y1 + y2) / 2.0) for x1, y1, x2, y2 in boxes]
    indices = sorted(range(len(boxes)), key=lambda i: y_centers[i])

    lines: list[dict] = []
    for idx in indices:
        yc = y_centers[idx]
        placed = False
        for line in lines:
            if abs(yc - line["y_mean"]) <= threshold:
                line["idxs"].append(idx)
                line["y_mean"] = float(np.mean([y_centers[i] for i in line["idxs"]]))
                placed = True
                break
        if not placed:
            lines.append({"y_mean": yc, "idxs": [idx]})

    lines.sort(key=lambda l: l["y_mean"])
    ordered: list[tuple[int, int, int, int]] = []
    for line in lines:
        row = sorted(line["idxs"], key=lambda i: boxes[i][0])
        ordered.extend([boxes[i] for i in row])
    return ordered


def _intersection_area(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> int:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    if ix2 <= ix1 or iy2 <= iy1:
        return 0
    return (ix2 - ix1) * (iy2 - iy1)


def _area(box: tuple[int, int, int, int]) -> int:
    x1, y1, x2, y2 = box
    return max(0, x2 - x1) * max(0, y2 - y1)


def _iou(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    inter = _intersection_area(a, b)
    if inter <= 0:
        return 0.0
    union = _area(a) + _area(b) - inter
    return float(inter / max(union, 1))


def _intersection_over_min_area(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    inter = _intersection_area(a, b)
    if inter <= 0:
        return 0.0
    return float(inter / max(min(_area(a), _area(b)), 1))


def deduplicate_boxes(
    boxes_with_scores: list[tuple[tuple[int, int, int, int], float]],
    iou_thr: float = 0.65,
    contain_thr: float = 0.92,
) -> list[tuple[int, int, int, int]]:
    if not boxes_with_scores:
        return []

    candidates = sorted(boxes_with_scores, key=lambda x: x[1], reverse=True)
    kept: list[tuple[int, int, int, int]] = []

    for box, _score in candidates:
        is_dup = False
        for k in kept:
            if _iou(box, k) >= iou_thr or _intersection_over_min_area(box, k) >= contain_thr:
                is_dup = True
                break
        if not is_dup:
            kept.append(box)

    return kept


def detect_boxes(yolo_model: YOLO, image_path: Path, cfg: CFG) -> list[tuple[int, int, int, int]]:
    results = yolo_model.predict(source=str(image_path), conf=cfg.conf, iou=cfg.iou, verbose=False)
    if not results:
        return []

    r0 = results[0]
    if r0.boxes is None or r0.boxes.xyxy is None:
        return []

    boxes_with_scores: list[tuple[tuple[int, int, int, int], float]] = []
    xyxy = r0.boxes.xyxy.cpu().numpy()
    confs = r0.boxes.conf.cpu().numpy() if r0.boxes.conf is not None else np.ones((len(xyxy),), dtype=np.float32)

    for b, c in zip(xyxy, confs):
        x1, y1, x2, y2 = [int(v) for v in b.tolist()]
        if x2 > x1 and y2 > y1:
            boxes_with_scores.append(((x1, y1, x2, y2), float(c)))

    deduped = deduplicate_boxes(boxes_with_scores)
    return sort_boxes_reading_order(deduped)


def run(args):
    cfg = CFG(conf=args.conf, iou=args.iou)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    vocab, _, idx2char = build_vocab(Path(args.vocab))
    model = OCR(len(vocab)).to(device)

    ckpt = torch.load(args.crnn, map_location=device)
    model.load_state_dict(ckpt, strict=True)
    model.eval()

    yolo = YOLO(args.yolo)
    image_path = Path(args.image)
    image = Image.open(image_path).convert("RGB")

    boxes = detect_boxes(yolo, image_path, cfg)
    if not boxes:
        print("No text boxes detected by YOLO.")
        return

    recognized_words = []
    for i, (x1, y1, x2, y2) in enumerate(boxes, start=1):
        crop = image.crop((x1, y1, x2, y2))
        inp = preprocess_crop(crop, cfg).to(device)

        with torch.no_grad():
            out = model(inp)
        text = decode(out.cpu(), idx2char)
        recognized_words.append(text.strip())
        print(f"[{i:02d}] box=({x1},{y1},{x2},{y2}) -> '{text}'")

    final_text = " ".join([w for w in recognized_words if w])
    print("\n=== OCR TEXT ===")
    print(final_text if final_text else "(empty output)")

    if args.save_vis:
        draw = ImageDraw.Draw(image)
        for x1, y1, x2, y2 in boxes:
            draw.rectangle((x1, y1, x2, y2), outline=(255, 0, 0), width=2)
        vis_path = image_path.with_name(image_path.stem + "_detected.jpg")
        image.save(vis_path)
        print(f"Saved detection visualization: {vis_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test YOLO + CRNN OCR on one image")
    parser.add_argument("--yolo", type=str, default=r"D:\final_Proj\amharic_yolov8s_last.pt")
    parser.add_argument("--crnn", type=str, default=r"D:\final_Proj\group\amharic_crnnmobi1.pth")
    parser.add_argument("--vocab", type=str, default=r"D:\final_Proj\full\awam_vocab.txt")
    parser.add_argument("--image", type=str, default=r"D:\internship\t1.jpg")
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--iou", type=float, default=0.50)
    parser.add_argument("--save-vis", action="store_true")
    args = parser.parse_args()

    run(args)
