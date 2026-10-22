import AppKit
import Foundation
import Observation
import SorterCore

/// Підключена картка пам'яті (або папка, з якої імпортуємо).
struct CardVolume: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: URL { url }
}

/// Мова інтерфейсу.
enum AppLanguage: String, CaseIterable, Identifiable {
    case uk, en
    var id: String { rawValue }
    var label: String { self == .uk ? "UA" : "EN" }
}

/// Що пішло не так — кодом, щоб текст можна було показати будь-якою мовою.
enum Problem {
    case folderMissing(URL)
    case notEnoughSpace(needed: Int64, available: Int64)
    case ejectFailed(String)
    case system(String)
}

/// Стан застосунку: вибір → перегляд плану → сортування/імпорт → результат.
@MainActor @Observable
final class SorterModel {
    enum Mode: Equatable {
        case organize                // упорядкувати папку на місці
        case importCard(CardVolume)  // скопіювати з картки в «Зображення»
    }

    enum Phase {
        case idle
        case noCard
        case pickCard([CardVolume])
        case scanning(done: Int, total: Int)
        case ready(SortPlan)
        case sorting(done: Int, total: Int)
        case finished(SortReport)
        case importing(ImportProgress)
        case imported(ImportReport, DeleteReport?)
        case deleting
        case failed(Problem)
    }

    private(set) var mode: Mode = .organize
    private(set) var folder: URL?
    private(set) var phase: Phase = .idle
    /// Картки, підключені зараз.
    private(set) var cards: [CardVolume] = []
    private(set) var ejectedCardName: String?
    /// Куди імпортувати (за замовчуванням — «Зображення»).
    private(set) var destinationRoot: URL

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    /// Текст потрібною мовою: `t("Імпорт", "Import")`.
    func t(_ uk: String, _ en: String) -> String {
        language == .uk ? uk : en
    }

    /// Назва папки призначення так, як її показує Finder («Зображення» / «Pictures»).
    var destinationName: String {
        language == .uk
            ? FileManager.default.displayName(atPath: destinationRoot.path)
            : destinationRoot.lastPathComponent
    }

    // MARK: Вибір файлів

    /// Файли, з яких знято галочку (за шляхом — щоб вибір не губився після «Оновити»).
    private(set) var excludedSources: Set<URL> = []
    let thumbnails = ThumbnailStore()
    /// Файл, відкритий у Quick Look (подвійний клік по рядку).
    var previewURL: URL?

    func isIncluded(_ item: PlannedItem, in plan: SortPlan) -> Bool {
        !plan.isExcluded(item, by: excludedSources)
    }

    /// Галочка біля файлу. Супровідні файли (.xmp, .gyroflow) йдуть за своїм основним файлом.
    func toggle(_ item: PlannedItem) {
        if excludedSources.contains(item.source) {
            excludedSources.remove(item.source)
        } else {
            excludedSources.insert(item.source)
        }
    }

    /// Галочка біля дня або «Вибрати все / Зняти все».
    func setIncluded(_ items: [PlannedItem], _ included: Bool) {
        for item in items {
            if included {
                excludedSources.remove(item.source)
            } else if item.companionOf == nil {
                // Супровідні файли окремо не позначаємо — вони йдуть за основним файлом.
                excludedSources.insert(item.source)
            }
        }
    }

    private func clearSelection() {
        excludedSources = []
        thumbnails.clear()
        previewURL = nil
    }

    // Стан вікна (тут, а не в @State: Command Line Tools не мають макросу State).
    var isDropTargeted = false
    var askDelete = false

    var naming: FolderNaming {
        didSet {
            UserDefaults.standard.set(naming.rawValue, forKey: "folderNaming")
            if oldValue != naming, folder != nil, isPreview { rescan() }
        }
    }

    private var task: Task<Void, Never>?
    private var workTask: Task<ImportReport, Never>?
    /// Номер поточного запуску — щоб старий скасований запуск не перезаписав стан.
    private var generation = 0

    init() {
        Self.migrateOldSettings()
        if let saved = UserDefaults.standard.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) {
            language = saved
        } else {
            language = Locale.preferredLanguages.first?.hasPrefix("uk") == true ? .uk : .en
        }
        let saved = UserDefaults.standard.string(forKey: "folderNaming")
        naming = saved.flatMap(FolderNaming.init(rawValue:)) ?? .dayMonthYear
        if let path = UserDefaults.standard.string(forKey: "importDestination") {
            destinationRoot = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destinationRoot = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        }
    }

    var isBusy: Bool {
        switch phase {
        case .scanning, .sorting, .importing, .deleting: return true
        default: return false
        }
    }

    var importCard: CardVolume? {
        if case .importCard(let card) = mode { return card }
        return nil
    }

    private var isPreview: Bool {
        switch phase {
        case .scanning, .ready, .failed: return true
        default: return false
        }
    }

    // MARK: - Вибір джерела

    func chooseFolder() {
        if let url = pickFolder(message: t("Виберіть папку, яку потрібно впорядкувати", "Choose a folder to organize")) { choose(url) }
    }

    /// Упорядкувати папку на місці.
    func choose(_ url: URL) {
        guard !isBusy || isPreview else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        mode = .organize
        folder = isDir.boolValue ? url : url.deletingLastPathComponent()
        clearSelection()
        rescan()
    }

    func refreshCards() {
        cards = CardDetector.find()
    }

    /// Кнопка «Імпорт».
    func startImport() {
        guard !isBusy || isPreview else { return }
        refreshCards()
        switch cards.count {
        case 0: phase = .noCard
        case 1: importFrom(cards[0])
        default: phase = .pickCard(cards)
        }
    }

    func importFrom(_ card: CardVolume) {
        guard !isBusy || isPreview else { return }
        mode = .importCard(card)
        folder = card.url
        ejectedCardName = nil
        clearSelection()
        rescan()
    }

    func importFromChosenFolder() {
        if let url = pickFolder(message: t("Виберіть картку або папку, з якої імпортувати фото", "Choose a card or folder to import photos from")) {
            importFrom(CardVolume(url: url, name: url.lastPathComponent))
        }
    }

    func changeDestination() {
        guard let url = pickFolder(message: t("Куди імпортувати фото", "Where to import photos"), start: destinationRoot) else { return }
        destinationRoot = url
        UserDefaults.standard.set(url.path, forKey: "importDestination")
        if importCard != nil, isPreview { rescan() }
    }

    // MARK: - План

    func rescan() {
        guard let folder, !isBusy || isPreview else { return }
        task?.cancel()
        generation += 1
        let gen = generation
        let naming = naming
        let destination = importCard == nil ? nil : destinationRoot
        phase = .scanning(done: 0, total: 0)

        task = Task {
            do {
                let plan = try await Planner().makePlan(root: folder, naming: naming, importInto: destination) { done, total in
                    Task { @MainActor in
                        guard self.generation == gen, case .scanning = self.phase else { return }
                        self.phase = .scanning(done: done, total: total)
                    }
                }
                guard generation == gen else { return }
                phase = .ready(plan)
            } catch is CancellationError {
                // скасовано — нічого не робимо
            } catch PlannerError.notAFolder(let url) {
                guard generation == gen else { return }
                phase = .failed(.folderMissing(url))
            } catch {
                guard generation == gen else { return }
                phase = .failed(.system(error.localizedDescription))
            }
        }
    }

    /// Кнопка «Сортувати» / «Імпортувати».
    func run() {
        guard case .ready(let fullPlan) = phase else { return }
        let plan = fullPlan.excluding(excludedSources)
        guard plan.summary.hasWork else { return }
        plan.isImport ? runImport(plan) : runSort(plan)
    }

    // MARK: - Сортування папки

    private func runSort(_ plan: SortPlan) {
        generation += 1
        let gen = generation
        phase = .sorting(done: 0, total: plan.summary.totalToMove + plan.summary.toTrash)

        task = Task {
            let report = await Task.detached(priority: .userInitiated) {
                Executor().run(plan) { done, total in
                    guard done == total || done % 20 == 0 else { return }
                    Task { @MainActor in
                        guard self.generation == gen else { return }
                        self.phase = .sorting(done: done, total: total)
                    }
                }
            }.value
            guard generation == gen else { return }
            phase = .finished(report)
        }
    }

    // MARK: - Імпорт

    private func runImport(_ plan: SortPlan) {
        do {
            try Importer.checkSpace(for: plan)
        } catch ImportError.notEnoughSpace(let needed, let available) {
            phase = .failed(.notEnoughSpace(needed: needed, available: available))
            return
        } catch {
            phase = .failed(.system(error.localizedDescription))
            return
        }
        generation += 1
        let gen = generation
        phase = .importing(ImportProgress())

        let work = Task.detached(priority: .userInitiated) {
            var lastUpdate = Date.distantPast
            return Importer().run(plan) { progress in
                // Оновлюємо екран не частіше ніж 10 разів на секунду.
                let now = Date()
                guard now.timeIntervalSince(lastUpdate) > 0.1 || progress.filesDone == progress.filesTotal else { return }
                lastUpdate = now
                Task { @MainActor in
                    guard self.generation == gen, case .importing = self.phase else { return }
                    self.phase = .importing(progress)
                }
            }
        }
        workTask = work
        task = Task {
            let report = await work.value
            guard generation == gen else { return }
            phase = .imported(report, nil)
            if !report.verified.isEmpty && !report.cancelled {
                askDelete = true
            }
        }
    }

    func cancelImport() {
        workTask?.cancel()
    }

    /// Видаляє з картки лише перевірені файли.
    func deleteOriginals() {
        guard case .imported(let report, nil) = phase, !report.verified.isEmpty else { return }
        generation += 1
        let gen = generation
        phase = .deleting
        task = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Importer.deleteOriginals(report.verified)
            }.value
            guard generation == gen else { return }
            phase = .imported(report, result)
        }
    }

    func ejectCard() {
        guard let card = importCard else { return }
        Task {
            let error: String? = await Task.detached {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: card.url)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let error {
                phase = .failed(.ejectFailed(error))
            } else {
                ejectedCardName = card.name
                refreshCards()
            }
        }
    }

    func reset() {
        task?.cancel()
        workTask?.cancel()
        generation += 1
        folder = nil
        mode = .organize
        phase = .idle
        askDelete = false
        clearSelection()
    }

    // MARK: - Допоміжне

    /// Раніше застосунок звався «Фотосортувальник» (ua.photosorter.app).
    /// Один раз переносимо звідти мову, формат назв папок і папку імпорту.
    private static func migrateOldSettings() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromPhotoSorter") else { return }
        defaults.set(true, forKey: "migratedFromPhotoSorter")
        guard let old = UserDefaults(suiteName: "ua.photosorter.app") else { return }
        for key in ["language", "folderNaming", "importDestination"] where defaults.object(forKey: key) == nil {
            if let value = old.string(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    private func pickFolder(message: String, start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = t("Вибрати", "Choose")
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Шукає підключені картки пам'яті.
///
/// Карткою вважаємо:
/// - будь-який знімний носій (SD/CF у картрідері, флешка) — навіть без папки DCIM;
/// - зовнішній диск із папкою DCIM (або PRIVATE у Sony) — напр. камера, підключена кабелем.
/// Зовнішні SSD/HDD без DCIM не показуємо — це не картки.
enum CardDetector {
    static func find() -> [CardVolume] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeIsRootFileSystemKey,
        ]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let found: [(card: CardVolume, isCamera: Bool)] = volumes.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true else { return nil }
            let removable = v.volumeIsRemovable == true
            let external = removable || v.volumeIsEjectable == true || v.volumeIsInternal == false
            let isCamera = looksLikeCameraCard(url)
            guard removable || (external && isCamera) else { return nil }
            return (CardVolume(url: url, name: v.volumeLocalizedName ?? url.lastPathComponent), isCamera)
        }
        // Картки з DCIM — першими.
        return found.sorted { $0.isCamera && !$1.isCamera }.map(\.card)
    }

    static func looksLikeCameraCard(_ url: URL) -> Bool {
        ["DCIM", "PRIVATE"].contains { name in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path, isDirectory: &isDir)
                && isDir.boolValue
        }
    }
}
