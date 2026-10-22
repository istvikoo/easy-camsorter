import AVFoundation
import Foundation
import ImageIO

/// Звідки взято дату.
public enum DateSource: String, Sendable {
    case exif        // метадані фото
    case video       // метадані відео
    case xmp         // дата всередині .xmp
    case companion   // дата RAW-файлу, до якого належить .xmp
    case fileDate    // дата зміни файлу (запасний варіант)
}

public struct CaptureDay: Hashable, Sendable {
    public var day: DayDate
    public var source: DateSource

    public init(day: DayDate, source: DateSource) {
        self.day = day
        self.source = source
    }
}

public protocol CaptureDateReading: Sendable {
    func captureDay(of url: URL, kind: FileKind) async -> CaptureDay?
}

/// Читає дату вбудованими засобами macOS — без exiftool.
public struct SystemDateReader: CaptureDateReading {
    public init() {}

    public func captureDay(of url: URL, kind: FileKind) async -> CaptureDay? {
        switch kind {
        case .raw, .photo, .psd:
            if let d = Self.imageDay(url) { return CaptureDay(day: d, source: .exif) }
        case .video:
            if let d = await Self.videoDay(url) { return CaptureDay(day: d, source: .video) }
        case .sidecar:
            if let d = Self.xmpDay(url) { return CaptureDay(day: d, source: .xmp) }
        case .videoSidecar:
            break   // дати всередині немає — береться з відео або з дати файлу
        case .junk, .other:
            return nil
        }
        if let d = Self.fileDay(url) { return CaptureDay(day: d, source: .fileDate) }
        return nil
    }

    static func imageDay(_ url: URL) -> DayDate? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let candidates: [Any?] = [
            exif?[kCGImagePropertyExifDateTimeOriginal],
            exif?[kCGImagePropertyExifDateTimeDigitized],
            tiff?[kCGImagePropertyTIFFDateTime],
        ]
        for case let text as String in candidates.compactMap({ $0 }) {
            if let d = DayDate.parse(text) { return d }
        }
        return nil
    }

    static func videoDay(_ url: URL) async -> DayDate? {
        let asset = AVURLAsset(url: url)
        guard let item = try? await asset.load(.creationDate) else { return nil }
        // Рядок зберігає часовий пояс зйомки, тому він точніший за Date.
        if let text = try? await item.load(.stringValue), let d = DayDate.parse(text) {
            return d
        }
        if let date = try? await item.load(.dateValue) {
            return DayDate(date: date)
        }
        return nil
    }

    static func xmpDay(_ url: URL) -> DayDate? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count < 5_000_000,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        for key in ["exif:DateTimeOriginal", "photoshop:DateCreated", "xmp:CreateDate"] {
            // Підходить і `key="2024-05-15..."`, і `<key>2024-05-15...</key>`.
            let pattern = key + #"\s*(=\s*"|>)\s*\d{4}[-:]\d{2}[-:]\d{2}"#
            if let range = text.range(of: pattern, options: .regularExpression),
               let d = DayDate.parse(String(text[range].suffix(10))) {
                return d
            }
        }
        return nil
    }

    static func fileDay(_ url: URL) -> DayDate? {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return DayDate(date: date)
    }
}
