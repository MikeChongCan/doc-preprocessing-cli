---
name: doc-crop
description: Crop, straighten, and compress document images (receipts, invoices, scans) using Apple Vision framework. Use when processing photos of documents that need background removal, perspective correction, or size reduction. Triggers on tasks like "crop this receipt", "straighten this scan", "compress this document photo", "clean up this invoice image", or any document image preprocessing for OCR, archival, or upload.
---

# doc-crop

Detect documents in photos, apply perspective correction, and compress to target size.

## Prerequisites

```bash
brew install imWildCat/tap/doc-crop
```

Requires macOS 13+ (uses Vision framework).

## Usage

```bash
doc-crop <input> <output> [options]
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--max-size <KB>` | `200` | Max output file size |
| `--quality <0-100>` | `75` | Initial compression quality |
| `--no-perspective` | off | Skip perspective correction (crop only) |

### Examples

```bash
# Receipt photo → clean WebP ≤200KB
doc-crop receipt.jpg receipt.webp

# Tighter compression
doc-crop photo.jpg out.webp --quality 60 --max-size 100

# Crop only, no straightening
doc-crop scan.png output.jpg --no-perspective
```

## Output formats

Determined by output file extension: `.webp`, `.jpg`/`.jpeg`, `.png`.
WebP and JPEG support iterative quality reduction to meet `--max-size`. PNG does not.

## How it works

1. Vision framework detects document region (falls back to rectangle detection)
2. `CIPerspectiveCorrection` straightens the detected quadrilateral (3% padding)
3. Encodes to target format, iteratively reducing quality until under `--max-size`
4. If no document detected, falls back to 5% margin crop
