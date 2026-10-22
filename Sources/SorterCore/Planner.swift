import Foundation

/// Що станеться з одним файлом.
public struct PlannedItem: Identifiable, Sendable {
    public enum Action: Sendable, Equatable {
        case move(to: URL)      // при імпорті — копіювання
        case alreadySorted      // уже лежить у правильній папці
        case alreadyImported(at: URL)  // такий самий файл уже є в «Зображеннях»
        case trash              // службовий файл → у кошик
        case skipUnsupported    // невідомий формат
        case skipNoDate         // не вдалося визначити дату
    }

    public let id: Int
    public let source: URL
    public let kind: FileKind
    public let capture: CaptureDay?
    public let action: Action
    /// Для .xmp/.gyroflow — основний файл (RAW чи відео), за яким вони йдуть.
    public var companionOf: URL? = nil

    /// Дату взято з дати зміни файлу і про це варто попередити.
    /// Для .gyroflow дати зйомки не буває, тому їх не позначаємо.
    public var warnsAboutFileDate: Bool {
        capture?.source == .fileDate && kind.needsCaptureDate
    }

    /// Чи файл отримає іншу назву (через дублікат).
    public var isRenamed: Bool {
        if case .move(let to) = action { return to.lastPathComponent != source.lastPathComponent }
        return false
    }
}

public struct PlanSummary: Sendable, Equatable {
    public var toMove: [FileKind: Int] = [:]
    public var alreadySorted = 0
    public var toTrash = 0
    public var unsupported = 0
    public var noDate = 0
    /// Скільки з переміщуваних файлів отримали дату зміни файлу, а не дату зйомки.
    public var usesFileDate = 0
    public var renamed = 0
    /// Імпорт: файли, які вже є в папці призначення (їх лише перевіримо).
    public var alreadyImported = 0
    public var isImport = false

    public var totalToMove: Int { toMove.values.reduce(0, +) }
    public var hasWork: Bool {
        isImport ? totalToMove > 0 || alreadyImported > 0 : totalToMove > 0 || toTrash > 0
    }
}

public struct SortPlan: Sendable {
    /// Звідки беремо файли.
    public let root: URL
    /// Куди кладемо (для сортування — та сама папка, для імпорту — «Зображення»).
    public let destinationRoot: URL
    public let naming: FolderNaming
    public let items: [PlannedItem]

    public var isImport: Bool { root != destinationRoot }

    public var summary: PlanSummary {
        var s = PlanSummary()
        s.isImport = isImport
        for item in items {
            switch item.action {
            case .move:
                s.toMove[item.kind, default: 0] += 1
                if item.warnsAboutFileDate { s.usesFileDate += 1 }
                if item.isRenamed { s.renamed += 1 }
            case .alreadySorted: s.alreadySorted += 1
            case .alreadyImported: s.alreadyImported += 1
            case .trash: s.toTrash += 1
            case .skipUnsupported: s.unsupported += 1
            case .skipNoDate: s.noDate += 1
            }
        }
        return s
    }

    /// План без вибраних файлів (і без супровідних файлів, чий основний файл виключено).
    /// Виключені файли не копіюються й не переміщуються — а отже й ніколи не видаляються з картки.
    public func excluding(_ sources: Set<URL>) -> SortPlan {
        guard !sources.isEmpty else { return self }
        let kept = items.filter { !isExcluded($0, by: sources) }
        return SortPlan(root: root, destinationRoot: destinationRoot, naming: naming, items: kept)
    }

    /// Чи файл виключено — сам по собі або разом зі своїм основним файлом.
    public func isExcluded(_ item: PlannedItem, by sources: Set<URL>) -> Bool {
        if sources.contains(item.source) { return true }
        if let primary = item.companionOf { return sources.contains(primary) }
        return false
    }

    /// Шлях відносно вибраної папки — для показу користувачу.
    public func relativePath(of url: URL) -> String {
        Self.relative(url, to: root)
    }

    /// Шлях відносно папки призначення.
    public func relativeDestinationPath(of url: URL) -> String {
        Self.relative(url, to: destinationRoot)
    }

    static func relative(_ url: URL, to base: URL) -> String {
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

public enum PlannerError: LocalizedError {
    case notAFolder(URL)

    public var errorDescription: String? {
        switch self {
        case .notAFolder(let url): return "Папку не знайдено: \(url.path)"
        }
    }
}

/// Складає план сортування, нічого не змінюючи на диску.
public struct Planner: Sendable {
    public var reader: any CaptureDateReading
    public var maxConcurrency: Int

    public init(reader: any CaptureDateReading = SystemDateReader(), maxConcurrency: Int = 8) {
        self.reader = reader
        self.maxConcurrency = max(1, maxConcurrency)
    }

    /// - Parameter importInto: якщо задано — план імпорту (копіювання) з `root` у цю папку.
    public func makePlan(
        root: URL,
        naming: FolderNaming,
        importInto: URL? = nil,
        progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> SortPlan {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let destination = importInto.map { $0.standardizedFileURL.resolvingSymlinksInPath() } ?? root
        // На картці пакети (напр. AVCHD у Sony) містять відео — туди теж заходимо.
        let files = try Self.listFiles(in: root, skipPackages: importInto == nil)
        let kinds = files.map(FileKind.of)

        let captures = try await readDates(files: files, kinds: kinds, progress: progress)

        var builder = PlanBuilder(root: destination, naming: naming, isImport: destination != root)
        // Спершу основні файли, потім .xmp/.gyroflow — щоб вони пішли за своїми RAW/відео.
        for i in files.indices where !kinds[i].isSidecar {
            builder.addPrimary(index: i, url: files[i], kind: kinds[i], capture: captures[i])
        }
        for i in files.indices where kinds[i].isSidecar {
            builder.addSidecar(index: i, url: files[i], kind: kinds[i], capture: captures[i])
        }
        return SortPlan(root: root, destinationRoot: destination, naming: naming,
                        items: builder.items.sorted { $0.id < $1.id })
    }

    static func listFiles(in root: URL, skipPackages: Bool = true) throws -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw PlannerError.notAFolder(root)
        }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            // Не заходимо в пакети (бібліотеку «Фото», .app тощо) і пропускаємо приховані файли.
            options: skipPackages ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true {
                result.append(url.standardizedFileURL)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func readDates(
        files: [URL],
        kinds: [FileKind],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [CaptureDay?] {
        let work = files.indices.filter { kinds[$0].isSortable }
        var result = [CaptureDay?](repeating: nil, count: files.count)
        let total = work.count
        progress(0, total)
        guard total > 0 else { return result }

        let reader = self.reader
        try await withThrowingTaskGroup(of: (Int, CaptureDay?).self) { group in
            var next = 0
            var done = 0
            func launch(_ i: Int) {
                let url = files[i], kind = kinds[i]
                group.addTask { (i, await reader.captureDay(of: url, kind: kind)) }
            }
            while next < min(maxConcurrency, total) {
                launch(work[next]); next += 1
            }
            while let (i, capture) = try await group.next() {
                try Task.checkCancellation()
                result[i] = capture
                done += 1
                if done == total || done % 25 == 0 { progress(done, total) }
                if next < total {
                    launch(work[next]); next += 1
                }
            }
        }
        return result
    }
}

/// Призначає кожному файлу місце, стежачи, щоб назви не збігалися.
struct PlanBuilder {
    let root: URL           // куди кладемо
    let naming: FolderNaming
    let isImport: Bool
    var items: [PlannedItem] = []
    /// Шляхи, які вже зайняті файлами з цього плану.
    var reserved = Set<String>()
    /// Основні файли за папкою, для пошуку RAW до .xmp.
    var primaries: [String: [Primary]] = [:]
    /// Відео за назвою (і за назвою без розширення) по всій вибраній папці — для .gyroflow.
    var videosByName: [String: [Primary]] = [:]

    struct Primary {
        let source: URL
        let name: String        // початкова назва, напр. IMG_1.CR3
        let kind: FileKind
        let capture: CaptureDay
        let destDir: URL
        let newName: String     // назва після переміщення
    }

    init(root: URL, naming: FolderNaming, isImport: Bool) {
        self.root = root
        self.naming = naming
        self.isImport = isImport
    }

    mutating func addPrimary(index: Int, url: URL, kind: FileKind, capture: CaptureDay?) {
        switch kind {
        case .other:
            return add(index, url, kind, nil, .skipUnsupported)
        case .junk:
            // При імпорті службові файли камери лишаються на картці.
            return add(index, url, kind, nil, isImport ? .skipUnsupported : .trash)
        default:
            break
        }
        guard let capture else { return add(index, url, kind, nil, .skipNoDate) }

        let destDir = destinationDir(for: capture.day, kind: kind)
        let name = url.lastPathComponent
        let newName: String
        if key(url.deletingLastPathComponent()) == key(destDir) {
            newName = name
            add(index, url, kind, capture, .alreadySorted)
        } else {
            let action = place(name, in: destDir, source: url)
            newName = action.destinationName
            add(index, url, kind, capture, action.action)
        }
        let primary = Primary(source: url, name: name, kind: kind, capture: capture, destDir: destDir, newName: newName)
        primaries[key(url.deletingLastPathComponent()), default: []].append(primary)
        if kind == .video {
            videosByName[name.lowercased(), default: []].append(primary)
            videosByName[(name as NSString).deletingPathExtension.lowercased(), default: []].append(primary)
        }
    }

    mutating func addSidecar(index: Int, url: URL, kind: FileKind, capture ownCapture: CaptureDay?) {
        let name = url.lastPathComponent
        let stem = url.deletingPathExtension().lastPathComponent   // IMG_1, IMG_1.CR3, C0001M01, GL010123
        let stems = Self.companionStems(for: stem, kind: kind)

        var anywhere: Primary?
        if kind.followsVideo {
            for candidate in stems { if let found = videoAnywhere(named: candidate) { anywhere = found; break } }
        }
        if let primary = companion(for: url, stems: stems, kind: kind) ?? anywhere {
            // Іде туди ж, куди й основний файл, і отримує таку ж нову назву.
            let capture = CaptureDay(day: primary.capture.day, source: .companion)
            var targetDir = primary.destDir
            if kind == .proxy { targetDir = targetDir.appendingPathComponent("proxy", isDirectory: true) }
            let wantedName = Self.renamedSidecar(name: name, stem: stem, primary: primary)
            if key(url.deletingLastPathComponent()) == key(targetDir), wantedName == name {
                return add(index, url, kind, capture, .alreadySorted, companionOf: primary.source)
            }
            return add(index, url, kind, capture, place(wantedName, in: targetDir, source: url).action,
                       companionOf: primary.source)
        }

        // .xml і .srt без свого відео — не від камери, не чіпаємо.
        if kind.requiresCompanion { return add(index, url, kind, nil, .skipUnsupported) }

        guard let ownCapture else { return add(index, url, kind, nil, .skipNoDate) }
        let destDir = destinationDir(for: ownCapture.day, kind: kind)
        if key(url.deletingLastPathComponent()) == key(destDir) {
            return add(index, url, kind, ownCapture, .alreadySorted)
        }
        add(index, url, kind, ownCapture, place(name, in: destDir, source: url).action)
    }

    /// Можливі назви основного файлу для супровідного.
    /// - Sony: `C0001M01.XML` → `C0001`
    /// - GoPro: проксі `GL010123.LRV` → відео `GX010123` або `GH010123`
    static func companionStems(for stem: String, kind: FileKind) -> [String] {
        var stems = [stem]
        if kind == .videoMeta, let range = stem.range(of: #"M\d{2}$"#, options: [.regularExpression, .caseInsensitive]),
           range.lowerBound > stem.startIndex {
            stems.append(String(stem[..<range.lowerBound]))
        }
        if kind == .proxy, stem.count > 2, stem.prefix(2).caseInsensitiveCompare("GL") == .orderedSame {
            let rest = stem.dropFirst(2)
            stems += ["GX" + rest, "GH" + rest]
        }
        return stems
    }

    /// Нова назва супровідного файлу: та сама зміна, що й в основного файлу.
    /// IMG_1.CR3 → IMG_1_1.CR3 дає IMG_1_1.xmp, C0001M01.XML → C0001_1M01.XML, GL01.LRV → GL01_1.LRV.
    static func renamedSidecar(name: String, stem: String, primary: Primary) -> String {
        guard primary.newName != primary.name else { return name }   // основний не перейменовано
        let ext = (name as NSString).pathExtension
        let oldStem = (primary.name as NSString).deletingPathExtension
        let newStem = (primary.newName as NSString).deletingPathExtension
        func same(_ a: Substring, _ b: Substring) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

        if same(Substring(stem), Substring(primary.name)) {         // IMG_1.CR3.xmp
            return primary.newName + "." + ext
        }
        if same(Substring(stem), Substring(oldStem)) {              // IMG_1.xmp
            return newStem + "." + ext
        }
        if stem.count > oldStem.count, same(stem.prefix(oldStem.count), Substring(oldStem)) {   // C0001M01.XML
            return newStem + stem.dropFirst(oldStem.count) + "." + ext
        }
        if stem.count > 2, oldStem.count > 2, same(stem.dropFirst(2), oldStem.dropFirst(2)) {   // GL010123.LRV
            return stem.prefix(2) + newStem.dropFirst(2) + "." + ext
        }
        return name
    }

    /// Супровідні файли відео часто лежать окремо — шукаємо відео з такою ж назвою по всій папці.
    /// Беремо лише якщо таке відео одне, щоб не сплутати однакові назви з різних днів (C0001.MP4).
    private func videoAnywhere(named stem: String) -> Primary? {
        let found = videosByName[stem.lowercased()] ?? []
        return found.count == 1 ? found[0] : nil
    }

    private func companion(for url: URL, stems: [String], kind: FileKind) -> Primary? {
        var candidates = primaries[key(url.deletingLastPathComponent())] ?? []
        // Супровідні файли відео шукають пару лише серед відео (IMG_1.xml не належить до IMG_1.JPG).
        if kind.followsVideo { candidates = candidates.filter { $0.kind == .video } }
        for stem in stems {
            // IMG_1.CR3.xmp → точний збіг з IMG_1.CR3
            if let exact = candidates.first(where: { $0.name.caseInsensitiveCompare(stem) == .orderedSame }) {
                return exact
            }
            // IMG_1.xmp → IMG_1.<будь-що>; для .xmp перевага за RAW
            let sameStem = candidates.filter {
                ($0.name as NSString).deletingPathExtension.caseInsensitiveCompare(stem) == .orderedSame
            }
            if let found = sameStem.first(where: { $0.kind == .raw }) ?? sameStem.first { return found }
        }
        return nil
    }

    private func destinationDir(for day: DayDate, kind: FileKind) -> URL {
        var dir = root.appendingPathComponent(naming.relativePath(for: day), isDirectory: true)
        if !kind.subfolder.isEmpty {
            dir = dir.appendingPathComponent(kind.subfolder, isDirectory: true)
        }
        return dir.standardizedFileURL
    }

    /// Підбирає назву: IMG.jpg → IMG_1.jpg → IMG_2.jpg…, поки не знайдеться вільна.
    /// При імпорті файл з тією ж назвою й розміром вважаємо вже імпортованим
    /// (вміст звіримо контрольною сумою під час імпорту).
    private mutating func place(_ name: String, in dir: URL, source: URL) -> (action: PlannedItem.Action, destinationName: String) {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let sourceSize = isImport ? Self.size(of: source) : nil
        var candidate = name
        var counter = 1
        while true {
            let url = dir.appendingPathComponent(candidate)
            if !reserved.contains(key(url)) {
                if !FileManager.default.fileExists(atPath: url.path) {
                    reserved.insert(key(url))
                    return (.move(to: url), candidate)
                }
                if let sourceSize, Self.size(of: url) == sourceSize {
                    reserved.insert(key(url))
                    return (.alreadyImported(at: url), candidate)
                }
            }
            candidate = ext.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(ext)"
            counter += 1
        }
    }

    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private mutating func add(_ id: Int, _ url: URL, _ kind: FileKind, _ capture: CaptureDay?, _ action: PlannedItem.Action,
                              companionOf: URL? = nil) {
        items.append(PlannedItem(id: id, source: url, kind: kind, capture: capture, action: action, companionOf: companionOf))
    }

    /// Диск у macOS зазвичай не розрізняє регістр, тому порівнюємо без нього.
    private func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.lowercased()
    }
}
