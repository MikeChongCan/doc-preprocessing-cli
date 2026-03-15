import Foundation
import Vision
import CoreImage
import AppKit
import UniformTypeIdentifiers
import WebP

// MARK: - CLI Argument Parsing

struct Options {
    var inputPath: String = ""
    var outputPath: String = ""
    var maxSizeKB: Int = 200
    var quality: Int = 75
    var perspectiveCorrection: Bool = true
}

func parseArgs() -> Options? {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        printUsage()
        return nil
    }

    var opts = Options()
    opts.inputPath = args[1]
    opts.outputPath = args[2]

    var i = 3
    while i < args.count {
        switch args[i] {
        case "--max-size":
            i += 1
            if i < args.count, let val = Int(args[i]) { opts.maxSizeKB = val }
        case "--quality":
            i += 1
            if i < args.count, let val = Int(args[i]) { opts.quality = val }
        case "--no-perspective":
            opts.perspectiveCorrection = false
        default:
            fputs("Warning: Unknown option \(args[i])\n", stderr)
        }
        i += 1
    }
    return opts
}

func printUsage() {
    let usage = """
    Usage: doc-crop <input> <output> [options]

    Options:
      --max-size <KB>     Max output file size (default: 200)
      --quality <0-100>   Initial WebP/JPEG quality (default: 75)
      --no-perspective    Skip perspective correction

    Examples:
      doc-crop receipt.jpg receipt.webp --max-size 200
      doc-crop photo.jpg cropped.webp --quality 60
      doc-crop scan.png output.jpg
    """
    print(usage)
}

// MARK: - Document Detection

func detectDocument(in cgImage: CGImage) -> VNRectangleObservation? {
    let request = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
        try handler.perform([request])
        if let result = request.results?.first {
            return result
        }
    } catch {
        fputs("Document detection failed: \(error.localizedDescription)\n", stderr)
    }

    // Fallback: try rectangle detection
    let rectRequest = VNDetectRectanglesRequest()
    rectRequest.minimumConfidence = 0.5
    rectRequest.maximumObservations = 1
    rectRequest.minimumAspectRatio = 0.3
    rectRequest.maximumAspectRatio = 1.0

    do {
        try handler.perform([rectRequest])
        if let result = rectRequest.results?.first {
            return result
        }
    } catch {
        fputs("Rectangle detection failed: \(error.localizedDescription)\n", stderr)
    }

    return nil
}

// MARK: - Image Processing

func applyPerspectiveCorrection(to ciImage: CIImage, observation: VNRectangleObservation) -> CIImage {
    let imageSize = ciImage.extent.size

    // Convert normalized coordinates to pixel coordinates
    // Add padding (3% of image dimensions) to avoid clipping content near edges
    let padX = imageSize.width * 0.03
    let padY = imageSize.height * 0.03

    let topLeft = CGPoint(
        x: max(0, observation.topLeft.x * imageSize.width - padX),
        y: min(imageSize.height, observation.topLeft.y * imageSize.height + padY)
    )
    let topRight = CGPoint(
        x: min(imageSize.width, observation.topRight.x * imageSize.width + padX),
        y: min(imageSize.height, observation.topRight.y * imageSize.height + padY)
    )
    let bottomLeft = CGPoint(
        x: max(0, observation.bottomLeft.x * imageSize.width - padX),
        y: max(0, observation.bottomLeft.y * imageSize.height - padY)
    )
    let bottomRight = CGPoint(
        x: min(imageSize.width, observation.bottomRight.x * imageSize.width + padX),
        y: max(0, observation.bottomRight.y * imageSize.height - padY)
    )

    let corrected = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
        "inputTopLeft": CIVector(cgPoint: topLeft),
        "inputTopRight": CIVector(cgPoint: topRight),
        "inputBottomLeft": CIVector(cgPoint: bottomLeft),
        "inputBottomRight": CIVector(cgPoint: bottomRight),
    ])

    return corrected
}

func cropToObservation(ciImage: CIImage, observation: VNRectangleObservation) -> CIImage {
    let imageSize = ciImage.extent.size

    // Get bounding box in pixel coordinates
    let boundingBox = observation.boundingBox
    let cropRect = CGRect(
        x: boundingBox.origin.x * imageSize.width,
        y: boundingBox.origin.y * imageSize.height,
        width: boundingBox.width * imageSize.width,
        height: boundingBox.height * imageSize.height
    )

    // Add small padding (2%)
    let padX = cropRect.width * 0.02
    let padY = cropRect.height * 0.02
    let paddedRect = cropRect.insetBy(dx: -padX, dy: -padY)
        .intersection(ciImage.extent)

    return ciImage.cropped(to: paddedRect)
}

func fallbackSmartCrop(ciImage: CIImage) -> CIImage {
    // Remove 5% margins from each side as a conservative fallback
    let extent = ciImage.extent
    let marginX = extent.width * 0.05
    let marginY = extent.height * 0.05
    let cropRect = extent.insetBy(dx: marginX, dy: marginY)
    fputs("No document detected, using fallback margin crop\n", stderr)
    return ciImage.cropped(to: cropRect)
}

// MARK: - Output Encoding

func cgImageFrom(ciImage: CIImage) -> CGImage? {
    let context = CIContext(options: [.useSoftwareRenderer: false])
    return context.createCGImage(ciImage, from: ciImage.extent)
}

func encodeWebP(cgImage: CGImage, quality: Float) -> Data? {
    // Use Swift-WebP (libwebp) for reliable WebP encoding on all macOS versions
    let width = cgImage.width
    let height = cgImage.height
    let stride = width * 4

    // Render CGImage into RGBA pixel buffer
    guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }
    var pixelData = [UInt8](repeating: 0, count: height * stride)
    guard let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: stride,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Failed to create bitmap context for WebP encoding\n", stderr)
        return nil
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    do {
        let encoder = WebPEncoder()
        let qualityPercent = quality * 100
        let config = WebPEncoderConfig.preset(.photo, quality: qualityPercent)
        let data = try pixelData.withUnsafeBufferPointer { buffer in
            try encoder.encode(
                buffer,
                format: .rgba,
                config: config,
                originWidth: Int(width),
                originHeight: Int(height),
                stride: stride
            )
        }
        return data
    } catch {
        fputs("WebP encoding failed: \(error.localizedDescription)\n", stderr)
        return nil
    }
}

func encodeJPEG(cgImage: CGImage, quality: Float) -> Data? {
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
}

func encodePNG(cgImage: CGImage) -> Data? {
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

func encodeImage(cgImage: CGImage, outputPath: String, quality: Float) -> Data? {
    let ext = (outputPath as NSString).pathExtension.lowercased()
    switch ext {
    case "webp":
        return encodeWebP(cgImage: cgImage, quality: quality)
    case "jpg", "jpeg":
        return encodeJPEG(cgImage: cgImage, quality: quality)
    case "png":
        return encodePNG(cgImage: cgImage)
    default:
        fputs("Unknown output format '\(ext)', defaulting to WebP\n", stderr)
        return encodeWebP(cgImage: cgImage, quality: quality)
    }
}

// MARK: - Main

func main() {
    guard let opts = parseArgs() else {
        exit(1)
    }

    // Load input image
    guard let inputURL = URL(string: "file://" + opts.inputPath) ?? URL(fileURLWithPath: opts.inputPath) as URL?,
          let ciImage = CIImage(contentsOf: inputURL) else {
        fputs("Error: Cannot load image at \(opts.inputPath)\n", stderr)
        exit(1)
    }

    guard let cgImage = cgImageFrom(ciImage: ciImage) else {
        fputs("Error: Cannot create CGImage from input\n", stderr)
        exit(1)
    }

    fputs("Input: \(cgImage.width)x\(cgImage.height)\n", stderr)

    // Detect document
    var processedImage: CIImage

    if let observation = detectDocument(in: cgImage) {
        let confidence = observation.confidence
        fputs("Document detected (confidence: \(String(format: "%.2f", confidence)))\n", stderr)

        if opts.perspectiveCorrection {
            processedImage = applyPerspectiveCorrection(to: ciImage, observation: observation)
            fputs("Applied perspective correction\n", stderr)
        } else {
            processedImage = cropToObservation(ciImage: ciImage, observation: observation)
            fputs("Cropped to document bounds (no perspective correction)\n", stderr)
        }
    } else {
        processedImage = fallbackSmartCrop(ciImage: ciImage)
    }

    guard let outputCGImage = cgImageFrom(ciImage: processedImage) else {
        fputs("Error: Failed to render processed image\n", stderr)
        exit(1)
    }

    fputs("Output: \(outputCGImage.width)x\(outputCGImage.height)\n", stderr)

    // Encode with iterative quality reduction to meet size target
    let maxBytes = opts.maxSizeKB * 1024
    var quality = Float(opts.quality) / 100.0
    let ext = (opts.outputPath as NSString).pathExtension.lowercased()
    let supportsQualityReduction = (ext == "webp" || ext == "jpg" || ext == "jpeg")

    var data = encodeImage(cgImage: outputCGImage, outputPath: opts.outputPath, quality: quality)

    if supportsQualityReduction {
        var attempts = 0
        while let d = data, d.count > maxBytes, quality > 0.10, attempts < 10 {
            quality -= 0.08
            if quality < 0.10 { quality = 0.10 }
            fputs("Size \(d.count / 1024)KB > \(opts.maxSizeKB)KB, reducing quality to \(Int(quality * 100))%\n", stderr)
            data = encodeImage(cgImage: outputCGImage, outputPath: opts.outputPath, quality: quality)
            attempts += 1
        }
    }

    guard let finalData = data else {
        fputs("Error: Failed to encode output image\n", stderr)
        exit(1)
    }

    // Write output
    let outputURL = URL(fileURLWithPath: opts.outputPath)
    do {
        try finalData.write(to: outputURL)
        let sizeKB = finalData.count / 1024
        fputs("Saved: \(opts.outputPath) (\(sizeKB)KB, quality: \(Int(quality * 100))%)\n", stderr)
    } catch {
        fputs("Error writing output: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

main()
