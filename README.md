# doc-crop

A macOS CLI that detects, crops, and compresses document images using Apple Vision framework. Feed it a photo of a receipt, invoice, or any document — it finds the document edges, applies perspective correction, and outputs a clean, compressed image.

## Features

- **Document detection** — uses `VNDetectDocumentSegmentationRequest` with rectangle detection fallback
- **Perspective correction** — straightens skewed documents via `CIPerspectiveCorrection`
- **Smart compression** — iteratively reduces quality to meet a target file size
- **Multiple formats** — WebP, JPEG, and PNG output
- **Zero dependencies** — pure Swift, uses only Apple frameworks (Vision, CoreImage, AppKit)

## Install

### Homebrew (recommended)

```bash
brew install imWildCat/tap/doc-crop
```

### Build from source

Requires macOS 13+ (Ventura or later) and Swift 5.9+.

```bash
swift build -c release
# binary at .build/release/doc-crop
```

## Usage

```bash
doc-crop <input> <output> [options]
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--max-size <KB>` | `200` | Max output file size in KB |
| `--quality <0-100>` | `75` | Initial compression quality |
| `--no-perspective` | off | Skip perspective correction (crop only) |

### Examples

```bash
# Crop and compress a receipt photo to WebP (≤200KB)
doc-crop receipt.jpg receipt.webp

# Lower quality, smaller output
doc-crop photo.jpg cropped.webp --quality 60 --max-size 100

# Crop without perspective correction
doc-crop scan.png output.jpg --no-perspective
```

## How it works

1. **Detect** — Vision framework finds the document region in the image
2. **Correct** — CIPerspectiveCorrection straightens the detected quadrilateral (with 3% padding to avoid clipping edges)
3. **Compress** — Encodes to the target format, iteratively lowering quality until the file fits under `--max-size`
4. **Fallback** — If no document is detected, trims 5% margins as a conservative crop

## Agent Skill

This repo includes an [AgentSkill](https://awesomeskills.dev) at `skills/doc-crop/SKILL.md` for use with Claude Code, Codex, and other AI coding agents.

## License

MIT
