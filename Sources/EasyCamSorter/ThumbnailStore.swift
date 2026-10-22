import AppKit
import Observation
import QuickLookThumbnailing

/// Мініатюри файлів через Quick Look (працює з JPG, HEIC, RAW, PSD і відео).
/// Генеруються ліниво — лише для рядків, які з'явилися на екрані.
@MainActor @Observable
final class ThumbnailStore {
    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var requested = Set<URL>()

    static let size = CGSize(width: 44, height: 44)

    func request(_ url: URL) {
        guard requested.insert(url).inserted else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: Self.size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let image = NSImage(cgImage: cgImage, size: .zero)
            let box = UncheckedBox(image)
            Task { @MainActor in self.images[url] = box.value }
        }
    }

    func clear() {
        images = [:]
        requested = []
    }
}

/// NSImage не позначено Sendable, але тут ми лише передаємо готове зображення на головний потік.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
