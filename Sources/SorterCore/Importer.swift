import CryptoKit
import Foundation

/// Файл, копію якого перевірено, — лише такі можна видаляти з картки.
public struct VerifiedCopy: Sendable {
    public let source: URL
    public let destination: URL
    public let size: Int64
    public let sourceModified: Date?
}

public struct ImportProgress: Sendable {
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0
    public var currentFile = ""

    public init() {}
}

public struct ImportReport: Sendable {
    public var copied: [FileKind: Int] = [:]
    /// Уже були в «Зображеннях» і збіглися за вмістом.
    public var alreadyThere = 0
    public var skipped = 0
    public var bytesCopied: Int64 = 0
    public var verified: [VerifiedCopy] = []
    public var failures: [SortReport.Failure] = []
    public var cancelled = false

    public var totalCopied: Int { copied.values.reduce(0, +) }

    public init() {}
}

public struct DeleteReport: Sendable {
    public var deleted = 0
    /// Файли, які залишено на картці, з причиною.
    public var kept: [SortReport.Failure] = []

    public init() {}
}

public enum ImportError: LocalizedError {
    case checksumMismatch
    case notEnoughSpace(needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Копія не збігається з оригіналом (помилка читання картки або запису на диск)"
        case .notEnoughSpace(let needed, let available):
            let f = ByteCountFormatter()
            return "Недостатньо місця на диску: потрібно \(f.string(fromByteCount: needed)), вільно \(f.string(fromByteCount: available))"
        }
    }
}

/// Копіює файли з картки за планом і перевіряє кожну копію.
///
/// Як захищаємо дані:
/// 1. Файл пишеться під тимчасовою прихованою назвою, тож недописана копія ніколи не виглядає справжньою.
/// 2. Під час копіювання рахуємо SHA-256 оригіналу; потім читаємо копію з диска (в обхід кешу) і звіряємо.
/// 3. Лише після збігу файл отримує справжню назву і потрапляє в список «можна видаляти».
public struct Importer: Sendable {
    public var chunkSize = 8 << 20

    public init() {}

    /// Скільки місця потрібно для нових файлів.
    public static func bytesNeeded(for plan: SortPlan) -> Int64 {
        plan.items.reduce(0) { sum, item in
            if case .move = item.action { return sum + (fileSize(item.source) ?? 0) }
            return sum
        }
    }

    public static func availableSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Перевіряє, що на диску вистачить місця (із запасом 1 ГБ).
    public static func checkSpace(for plan: SortPlan) throws {
        let needed = bytesNeeded(for: plan)
        var probe = plan.destinationRoot
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        if let available = availableSpace(at: probe), needed + (1 << 30) > available {
            throw ImportError.notEnoughSpace(needed: needed, available: available)
        }
    }

    public func run(_ plan: SortPlan, progress: (ImportProgress) -> Void = { _ in }) -> ImportReport {
        var report = ImportReport()
        var state = ImportProgress()
        let work = plan.items.filter {
            switch $0.action {
            case .move, .alreadyImported: return true
            default: return false
            }
        }
        report.skipped = plan.items.count - work.count
        state.filesTotal = work.count
        state.bytesTotal = work.reduce(0) { $0 + (Self.fileSize($1.source) ?? 0) }
        progress(state)

        for item in work {
            if Task.isCancelled { report.cancelled = true; break }
            state.currentFile = item.source.lastPathComponent
            progress(state)
            let onBytes: (Int) -> Void = { n in
                state.bytesDone += Int64(n)
                progress(state)
            }
            do {
                switch item.action {
                case .move(let dest):
                    let copy = try copyVerified(from: item.source, to: dest, onBytes: onBytes)
                    report.copied[item.kind, default: 0] += 1
                    report.bytesCopied += copy.size
                    report.verified.append(copy)

                case .alreadyImported(let existing):
                    let size = Self.fileSize(item.source) ?? 0
                    let sourceDigest = try Self.digest(of: item.source, onBytes: onBytes)
                    if try Self.digest(of: existing, uncached: true) == sourceDigest {
                        report.alreadyThere += 1
                        report.verified.append(VerifiedCopy(
                            source: item.source, destination: existing, size: size,
                            sourceModified: Self.modificationDate(item.source)))
                    } else {
                        // Та сама назва й розмір, але інший вміст — копіюємо поруч з номером.
                        let copy = try copyVerified(from: item.source, to: existing, onBytes: { _ in })
                        report.copied[item.kind, default: 0] += 1
                        report.bytesCopied += copy.size
                        report.verified.append(copy)
                    }
                default:
                    break
                }
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failures.append(.init(file: item.source, error: error))
            }
            state.filesDone += 1
            progress(state)
        }
        return report
    }

    /// Видаляє з картки лише перевірені файли. Перед кожним видаленням ще раз упевнюється,
    /// що оригінал не змінився, а копія на місці й має той самий розмір.
    public static func deleteOriginals(_ copies: [VerifiedCopy]) -> DeleteReport {
        let fm = FileManager.default
        var report = DeleteReport()
        for copy in copies {
            guard fm.fileExists(atPath: copy.source.path) else { continue }   // уже немає
            guard fileSize(copy.destination) == copy.size else {
                report.kept.append(.init(file: copy.source, reason: .copyMissing))
                continue
            }
            guard fileSize(copy.source) == copy.size, modificationDate(copy.source) == copy.sourceModified else {
                report.kept.append(.init(file: copy.source, reason: .sourceChanged))
                continue
            }
            do {
                try fm.removeItem(at: copy.source)
                report.deleted += 1
            } catch {
                report.kept.append(.init(file: copy.source, error: error))
            }
        }
        return report
    }

    // MARK: - Копіювання

    func copyVerified(from source: URL, to dest: URL, onBytes: (Int) -> Void) throws -> VerifiedCopy {
        let fm = FileManager.default
        let dir = dest.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let attrs = try fm.attributesOfItem(atPath: source.path)
        let modified = attrs[.modificationDate] as? Date
        let created = attrs[.creationDate] as? Date

        let temp = dir.appendingPathComponent(".\(dest.lastPathComponent).\(UUID().uuidString).part")
        guard fm.createFile(atPath: temp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temp.path])
        }
        var finished = false
        defer { if !finished { try? fm.removeItem(at: temp) } }

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temp)
        var hasher = SHA256()
        var size: Int64 = 0
        do {
            while true {
                if Task.isCancelled { throw CancellationError() }
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
                size += Int64(chunk.count)
                onBytes(chunk.count)
            }
            try output.synchronize()   // дочекатися реального запису на диск
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        guard try Self.digest(of: temp, uncached: true) == hasher.finalize() else {
            throw ImportError.checksumMismatch
        }

        // Дати як в оригіналу — від них залежить сортування файлів без EXIF.
        var newAttrs: [FileAttributeKey: Any] = [:]
        if let modified { newAttrs[.modificationDate] = modified }
        if let created { newAttrs[.creationDate] = created }
        try fm.setAttributes(newAttrs, ofItemAtPath: temp.path)

        let final = Executor.freeURL(near: dest)
        try fm.moveItem(at: temp, to: final)
        finished = true
        return VerifiedCopy(source: source, destination: final, size: size, sourceModified: modified)
    }

    static func digest(of url: URL, uncached: Bool = false, onBytes: (Int) -> Void = { _ in }) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if uncached {
            // Читаємо з диска, а не з пам'яті, щоб перевірити саме записане.
            _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { throw CancellationError() }
            guard let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            onBytes(chunk.count)
        }
        return hasher.finalize()
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
