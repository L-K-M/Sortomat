import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

/// On-device text recognition and image facts. Screenshots, photographed
/// receipts and scanned PDFs used to reach the model as a file name and a
/// byte count; the Vision framework reads them locally (nothing leaves the
/// machine at this step), so their visible text can be classified — or, for
/// deterministic rules, matched — like any other document's.
enum ImageText {
    /// Images above this are not recognized: the decode alone would dominate
    /// a scan, and a classification sample needs a legible page, not a poster.
    static let maxImageBytes: Int64 = 40 * 1024 * 1024
    /// Long-edge size the image is downsampled to before recognition; enough
    /// for body text on a screenshot or a scan, a fraction of the decode cost.
    static let maxPixelSize = 2400
    /// Pages of a text-less PDF that are rendered and recognized.
    static let scannedPDFPages = 2

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
    ]

    // MARK: - Recognition

    static func recognize(imageAt url: URL) -> String {
        guard !Task.isCancelled else { return "" }
        guard sizeAllows(url), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return "" }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return "" }
        return recognize(image)
    }

    /// Text on the first pages of a PDF that has no text layer (a scan).
    static func recognize(scannedPDF document: PDFDocument) -> String {
        var pieces: [String] = []
        for index in 0..<min(document.pageCount, scannedPDFPages) {
            // Recognition is seconds per page; a stopped scan should not keep
            // paying for pages nobody is waiting for.
            if Task.isCancelled { break }
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale = min(3, CGFloat(maxPixelSize) / max(bounds.width, bounds.height))
            let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let text = recognize(cgImage)
            if !text.isEmpty { pieces.append(text) }
        }
        return pieces.joined(separator: "\n")
    }

    static func recognize(_ image: CGImage) -> String {
        // One `.accurate` request is seconds of CPU that cannot be interrupted
        // once it starts; the cheapest place to notice a stopped pass is right
        // before it does.
        guard !Task.isCancelled else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.pipeline.error("text recognition failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    // MARK: - Facts

    /// Pixel size, capture date and camera — metadata, so it is described even
    /// for metadata-only rules. Location is deliberately never read.
    static func facts(imageAt url: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }
        var facts: [(String, String)] = []
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            facts.append(("Dimensions", "\(width)×\(height)"))
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let taken = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            facts.append(("Taken", taken))
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            let make = (tiff[kCGImagePropertyTIFFMake as String] as? String) ?? ""
            let model = (tiff[kCGImagePropertyTIFFModel as String] as? String) ?? ""
            let camera = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
            if !camera.isEmpty { facts.append(("Camera", camera)) }
        }
        return facts
    }

    /// Internal so the symlink behaviour can be asserted against the gate
    /// itself rather than against `FileManager`.
    static func sizeAllows(_ url: URL) -> Bool {
        // `attributesOfItem` describes the *link*; `CGImageSourceCreateWithURL`
        // follows it. A symlink to a forty-megapixel original weighed a few
        // bytes and passed the cap that exists to stop that decode.
        let target = url.resolvingSymlinksInPath()
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.size] as? Int64 ?? 0
        return size <= maxImageBytes
    }
}
