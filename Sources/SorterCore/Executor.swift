import Foundation

public struct SortReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public let id = UUID()
        public let file: URL
        public let reason: Reason

        /// Причина — кодом, а текст підбирає інтерфейс потрібною мовою.
        public enum Reason: Sendable, Equatable {
            case checksumMismatch   // копія не збіглася з оригіналом
            case copyMissing        // копії немає або вона змінилася
            case sourceChanged      // файл на картці змінився після імпорту
            case system(String)     // помилка macOS (уже перекладена системою)
        }

        public init(file: URL, reason: Reason) {
            self.file = file
            self.reason = reason
        }

        init(file: URL, error: Error) {
            self.file = file
            if case ImportError.checksumMismatch = error {
                reason = .checksumMismatch
            } else {
                reason = .system(error.localizedDescription)
            }
        }
    }

    public var moved: [FileKind: Int] = [:]
    public var trashed = 0
    public var alreadySorted = 0
    public var skipped = 0
    public var removedFolders = 0
    public var failures: [Failure] = []

    public var totalMoved: Int { moved.values.reduce(0, +) }
}

/// Виконує план: переміщує файли, службові кладе в кошик, прибирає порожні папки.
public struct Executor: Sendable {
    /// Як прибирати службові файли. За замовчуванням — у системний кошик.
    public var trash: @Sendable (URL) throws -> Void

    public init(trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.trash = trash
    }

    public func run(_ plan: SortPlan, progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) -> SortReport {
        let fm = FileManager.default
        var report = SortReport()
        var touchedDirs = Set<URL>()
        let work = plan.items.filter {
            if case .move = $0.action { return true }
            return $0.action == .trash
        }

        for item in plan.items {
            switch item.action {
            case .alreadySorted: report.alreadySorted += 1
            case .skipNoDate, .skipUnsupported: report.skipped += 1
            default: break
            }
        }

        for (n, item) in work.enumerated() {
            do {
                switch item.action {
                case .move(let dest):
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let target = Self.freeURL(near: dest)
                    try fm.moveItem(at: item.source, to: target)
                    report.moved[item.kind, default: 0] += 1
                case .trash:
                    try trash(item.source)
                    report.trashed += 1
                default:
                    break
                }
                touchedDirs.insert(item.source.deletingLastPathComponent().standardizedFileURL)
            } catch {
                report.failures.append(.init(file: item.source, error: error))
            }
            progress(n + 1, work.count)
        }

        report.removedFolders = Self.removeEmptyFolders(startingAt: touchedDirs, root: plan.root)
        return report
    }

    /// Якщо за час між планом і виконанням назву хтось зайняв — шукаємо наступну вільну.
    static func freeURL(near url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        while true {
            let name = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    /// Видаляє папки, які спорожніли після переміщення (і їхніх порожніх батьків).
    /// Папки, з яких нічого не забирали, не чіпаємо. Саму вибрану папку не видаляємо.
    static func removeEmptyFolders(startingAt dirs: Set<URL>, root: URL) -> Int {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var removed = 0
        var queue = dirs.sorted { $0.pathComponents.count > $1.pathComponents.count }
        var visited = Set<String>()

        while !queue.isEmpty {
            let dir = queue.removeFirst()
            let path = dir.standardizedFileURL.path
            guard path != rootPath, path.hasPrefix(rootPath + "/"), visited.insert(path).inserted else { continue }
            guard var contents = try? fm.contentsOfDirectory(atPath: path) else { continue }
            if contents == [".DS_Store"] {
                try? fm.removeItem(atPath: path + "/.DS_Store")
                contents = []
            }
            guard contents.isEmpty, (try? fm.removeItem(atPath: path)) != nil else { continue }
            removed += 1
            queue.append(dir.deletingLastPathComponent())
        }
        return removed
    }
}
