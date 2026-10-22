import AppKit
import SorterCore
import SwiftUI

struct ContentView: View {
    @Environment(SorterModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header(naming: $model.naming)
            Divider()
            Group {
                switch model.phase {
                case .idle:
                    IdleView()
                case .noCard:
                    MessagePane(symbol: "sdcard", tint: .secondary,
                                title: model.t("Картку не знайдено", "No card found"),
                                text: model.t("Вставте картку в картрідер — вона з'явиться тут. Якщо картка не розпізнається, виберіть її або папку з фото вручну.",
                                              "Insert a card into the card reader and it will appear here. If the card isn't recognised, choose it or a photo folder manually.")) {
                        HStack {
                            Button(model.t("Шукати ще раз", "Search again")) { model.startImport() }
                            Button(model.t("Вибрати вручну…", "Choose manually…")) { model.importFromChosenFolder() }
                        }
                    }
                case .pickCard(let cards):
                    MessagePane(symbol: "sdcard.fill", tint: .accentColor,
                                title: model.t("З якої картки імпортувати?", "Which card to import from?"), text: "") {
                        VStack(spacing: 8) {
                            ForEach(cards) { card in
                                Button { model.importFrom(card) } label: {
                                    Label(card.name, systemImage: "sdcard").frame(minWidth: 220)
                                }
                                .controlSize(.large)
                            }
                        }
                    }
                case .scanning(let done, let total):
                    ProgressPane(title: model.t("Читаю дати зйомки…", "Reading capture dates…"), done: done, total: total,
                                 of: model.t("з", "of"), cancelTitle: model.t("Скасувати", "Cancel")) { model.reset() }
                case .ready(let plan):
                    PlanView(plan: plan)
                case .sorting(let done, let total):
                    ProgressPane(title: model.t("Сортую файли…", "Sorting files…"), done: done, total: total,
                                 of: model.t("з", "of"), cancelTitle: nil, onCancel: nil)
                case .finished(let report):
                    ReportView(report: report)
                case .importing(let progress):
                    ImportProgressPane(progress: progress)
                case .imported(let report, let deleted):
                    ImportReportView(report: report, deleted: deleted)
                case .deleting:
                    ProgressPane(title: model.t("Видаляю перенесені файли з картки…", "Deleting imported files from the card…"),
                                 done: 0, total: 0, of: "", cancelTitle: nil, onCancel: nil)
                case .failed(let problem):
                    MessagePane(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                title: model.t("Щось пішло не так", "Something went wrong"), text: text(for: problem)) {
                        HStack {
                            Button(model.t("Назад", "Back")) { model.reset() }
                            if model.folder != nil { Button(model.t("Спробувати ще раз", "Try again")) { model.rescan() } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar(language: $model.language)
        }
        .frame(minWidth: 780, minHeight: 560)
        .navigationTitle("Easy CamSorter")
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isBusy, let url = urls.first else { return false }
            model.choose(url)
            return true
        } isTargeted: { model.isDropTargeted = $0 }
        .alert(model.t("Видалити оригінали з картки?", "Delete originals from the card?"), isPresented: $model.askDelete) {
            Button(model.t("Видалити з картки", "Delete from card"), role: .destructive) { model.deleteOriginals() }
            Button(model.t("Залишити на картці", "Keep on card"), role: .cancel) {}
        } message: {
            Text(deletePromptText)
        }
    }

    private var deletePromptText: String {
        guard case .imported(let report, _) = model.phase else { return "" }
        let n = report.verified.count
        let folder = model.destinationName
        var text = model.t("Копії всіх \(n) файлів перевірено — вони є в «\(folder)». Буде видалено лише ці файли.",
                           "All \(n) copies have been verified and are in “\(folder)”. Only these files will be deleted.")
        if !report.failures.isEmpty {
            let f = report.failures.count
            text += model.t(" Файли, які не вдалося скопіювати (\(f)), залишаться на картці.",
                            " Files that couldn't be copied (\(f)) will stay on the card.")
        }
        text += model.t("\n\nСкасувати видалення буде неможливо.", "\n\nThis can't be undone.")
        return text
    }

    private func text(for problem: Problem) -> String {
        switch problem {
        case .folderMissing(let url):
            return model.t("Папку не знайдено: \(url.path)", "Folder not found: \(url.path)")
        case .notEnoughSpace(let needed, let available):
            let n = formatBytes(needed, model.language), a = formatBytes(available, model.language)
            return model.t("Недостатньо місця на диску: потрібно \(n), вільно \(a).",
                           "Not enough disk space: \(n) needed, \(a) available.")
        case .ejectFailed(let message):
            return model.t("Не вдалося витягнути картку: \(message)", "Couldn't eject the card: \(message)")
        case .system(let message):
            return message
        }
    }

    private func header(naming: Binding<FolderNaming>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.importCard == nil ? "folder.fill" : "sdcard.fill")
                .foregroundStyle(.tint)
                .font(.title2)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                if let card = model.importCard {
                    Text(model.t("Імпорт з «\(card.name)»", "Import from “\(card.name)”")).font(.headline).lineLimit(1)
                    Text("→ \(displayPath(model.destinationRoot))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(model.folder?.lastPathComponent ?? "Easy CamSorter").font(.headline).lineLimit(1)
                    if let folder = model.folder {
                        Text(displayPath(folder.deletingLastPathComponent()))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            Spacer()
            Picker(model.t("Назви папок:", "Folder names:"), selection: naming) {
                Section(model.t("Українською", "Ukrainian")) {
                    ForEach(FolderNaming.ukrainianCases) { Text($0.example).tag($0) }
                }
                Section(model.t("Англійською", "English")) {
                    ForEach(FolderNaming.englishCases) { Text($0.example).tag($0) }
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(model.isBusy)
            .help(model.t("Як називати папки з датами", "How to name the date folders"))
            importButton
            Button(model.t("Вибрати папку…", "Choose Folder…")) { model.chooseFolder() }
                .disabled(model.isBusy)
                .help(model.t("Упорядкувати папку на місці", "Organize a folder in place"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var importButton: some View {
        let title = model.t("Імпорт", "Import")
        if model.cards.count > 1 {
            Menu {
                ForEach(model.cards) { card in
                    Button(card.name) { model.importFrom(card) }
                }
                Divider()
                Button(model.t("Вибрати вручну…", "Choose manually…")) { model.importFromChosenFolder() }
            } label: {
                Label(title, systemImage: "sdcard")
            }
            .fixedSize()
            .disabled(model.isBusy)
        } else {
            Button { model.startImport() } label: {
                Label(title, systemImage: "sdcard")
            }
            .disabled(model.isBusy)
            .help(model.t("Скопіювати фото з картки в «\(model.destinationName)» з сортуванням за датами",
                          "Copy photos from the card to “\(model.destinationName)”, sorted by date"))
        }
    }

    /// Тонка смуга внизу з перемикачем мови праворуч.
    private func statusBar(language: Binding<AppLanguage>) -> some View {
        HStack {
            Spacer()
            Picker("", selection: language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .fixedSize()
            .help(model.t("Мова інтерфейсу", "Interface language"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

func displayPath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    return path.hasPrefix(home) ? "~/" + path.dropFirst(home.count) : path
}

/// 294,7 МБ / 294.7 MB — у десяткових одиницях, як у Finder.
func formatBytes(_ bytes: Int64, _ language: AppLanguage) -> String {
    let units = language == .uk ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var i = 0
    while value >= 1000, i < units.count - 1 {
        value /= 1000
        i += 1
    }
    var number = i == 0 ? String(Int(value)) : String(format: "%.1f", value)
    if language == .uk { number = number.replacingOccurrences(of: ".", with: ",") }
    return number + " " + units[i]
}

// MARK: - Порожній стан

private struct IdleView: View {
    @Environment(SorterModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(model.isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            if let card = model.cards.first {
                Text(model.t("Підключено картку «\(card.name)»", "Card “\(card.name)” connected"))
                    .font(.title3.weight(.medium))
                Text(model.t("Фото й відео скопіюються в «\(model.destinationName)» і розкладуться по датах. Спершу покажу список — нічого не почнеться без вашого підтвердження.",
                             "Photos and videos will be copied to “\(model.destinationName)” and sorted by date. You'll see the list first — nothing starts until you confirm."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button {
                    model.cards.count == 1 ? model.importFrom(card) : model.startImport()
                } label: {
                    Label(model.cards.count == 1
                          ? model.t("Імпортувати з «\(card.name)»", "Import from “\(card.name)”")
                          : model.t("Імпортувати з картки…", "Import from card…"),
                          systemImage: "sdcard")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
                Text(model.t("або перетягніть сюди папку, щоб упорядкувати її на місці",
                             "or drop a folder here to organize it in place"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.top, 8)
            } else {
                Text(model.t("Перетягніть сюди папку з фото та відео", "Drop a folder with photos and videos here"))
                    .font(.title3.weight(.medium))
                Text(model.t("Спершу покажу, що і куди переміститься. Нічого не зміниться, доки ви не натиснете «Сортувати».\nЩоб скопіювати фото з картки камери, натисніть «Імпорт».",
                             "You'll see what goes where first. Nothing changes until you click “Sort”.\nTo copy photos from a camera card, click “Import”."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                if let ejected = model.ejectedCardName {
                    Label(model.t("Картку «\(ejected)» витягнуто — її можна виймати", "Card “\(ejected)” ejected — you can remove it"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                HStack {
                    Button(model.t("Вибрати папку…", "Choose Folder…")) { model.chooseFolder() }
                    Button { model.startImport() } label: {
                        Label(model.t("Імпорт з картки", "Import from Card"), systemImage: "sdcard")
                    }
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(model.isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .padding(20)
        }
    }
}

// MARK: - Прогрес

private struct ProgressPane: View {
    let title: String
    let done: Int
    let total: Int
    let of: String
    let cancelTitle: String?
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.title3.weight(.medium))
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .frame(width: 320)
                Text("\(done) \(of) \(total)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            if let onCancel, let cancelTitle {
                Button(cancelTitle, action: onCancel).padding(.top, 6)
            }
        }
        .padding(40)
    }
}

private struct ImportProgressPane: View {
    @Environment(SorterModel.self) private var model
    let progress: ImportProgress

    var body: some View {
        let lang = model.language
        let file = min(progress.filesDone + 1, max(progress.filesTotal, 1))
        let bytes = "\(formatBytes(progress.bytesDone, lang)) \(model.t("з", "of")) \(formatBytes(progress.bytesTotal, lang))"
        VStack(spacing: 12) {
            Text(model.t("Імпортую й перевіряю…", "Importing and verifying…")).font(.title3.weight(.medium))
            ProgressView(value: Double(progress.bytesDone), total: Double(max(progress.bytesTotal, 1)))
                .frame(width: 360)
            Text(model.t("Файл \(file) з \(progress.filesTotal)", "File \(file) of \(progress.filesTotal)") + "  ·  " + bytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(progress.currentFile)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 360)
            Button(model.t("Зупинити", "Stop")) { model.cancelImport() }.padding(.top, 6)
            Text(model.t("Уже скопійовані файли залишаться в папці призначення, а на картці нічого не зміниться.",
                         "Files already copied stay in the destination folder, and nothing on the card changes."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

// MARK: - Перегляд плану

private struct PlanView: View {
    @Environment(SorterModel.self) private var model
    let plan: SortPlan
    let summary: PlanSummary
    let groups: [(folder: String, items: [PlannedItem])]
    let trash: [PlannedItem]
    let skipped: [PlannedItem]
    let bytesToCopy: Int64

    init(plan: SortPlan) {
        self.plan = plan
        summary = plan.summary
        var byFolder: [String: [PlannedItem]] = [:]
        var trash: [PlannedItem] = []
        var skipped: [PlannedItem] = []
        for item in plan.items {
            switch item.action {
            case .move(let dest):
                byFolder[plan.relativeDestinationPath(of: dest.deletingLastPathComponent()), default: []].append(item)
            case .trash: trash.append(item)
            case .skipNoDate, .skipUnsupported: skipped.append(item)
            case .alreadySorted, .alreadyImported: break
            }
        }
        // Папки — за датою, а не за алфавітом.
        groups = byFolder.map { (folder: $0.key, items: $0.value) }.sorted { a, b in
            let da = a.items[0].capture?.day, db = b.items[0].capture?.day
            if let da, let db, da != db { return da < db }
            return a.folder.localizedStandardCompare(b.folder) == .orderedAscending
        }
        self.trash = trash
        self.skipped = skipped
        bytesToCopy = plan.isImport ? Importer.bytesNeeded(for: plan) : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            SummaryBar(summary: summary)
            if plan.isImport {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line").foregroundStyle(.secondary)
                    Text(model.t("Куди: ", "To: ") + displayPath(plan.destinationRoot))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button(model.t("Змінити…", "Change…")) { model.changeDestination() }
                        .buttonStyle(.link)
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if summary.usesFileDate > 0 {
                let n = summary.usesFileDate
                Label(model.t("У \(n) файлів немає дати зйомки — для них узято дату зміни файлу. Вони позначені нижче.",
                              "\(n) files have no capture date — their modification date is used instead. They're marked below."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Divider()
            if !groups.isEmpty || !trash.isEmpty || !skipped.isEmpty {
                list
            } else if plan.isImport && summary.alreadyImported > 0 {
                let n = summary.alreadyImported
                let folder = model.destinationName
                MessagePane(symbol: "checkmark.seal.fill", tint: .green,
                            title: model.t("Усе вже імпортовано", "Everything is already imported"),
                            text: model.t("Усі \(n) файлів з картки вже є в «\(folder)». Натисніть «Перевірити», щоб звірити їх і за бажанням видалити з картки.",
                                          "All \(n) files from the card are already in “\(folder)”. Click “Verify” to check them and optionally delete them from the card.")) { EmptyView() }
            } else if plan.isImport {
                MessagePane(symbol: "sdcard", tint: .secondary,
                            title: model.t("На картці немає фото й відео", "No photos or videos on the card"),
                            text: model.t("Не знайдено жодного файлу, який можна імпортувати.", "No files that can be imported were found.")) { EmptyView() }
            } else {
                MessagePane(symbol: "checkmark.seal.fill", tint: .green,
                            title: model.t("Усе вже відсортовано", "Everything is already sorted"),
                            text: model.t("У цій папці немає файлів, які потрібно переміщувати.", "Nothing in this folder needs to be moved.")) { EmptyView() }
            }
            Divider()
            footer
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.folder) { group in
                Section {
                    ForEach(group.items) { MoveRow(item: $0, plan: plan) }
                } header: {
                    Label("\(group.folder)  ·  \(group.items.count)", systemImage: "folder")
                }
            }
            if !trash.isEmpty {
                Section {
                    ForEach(trash) { item in
                        FileRow(kind: item.kind, name: plan.relativePath(of: item.source))
                    }
                } header: {
                    Label(model.t("У кошик (службові файли камери)", "To Trash (camera service files)") + "  ·  \(trash.count)",
                          systemImage: "trash")
                }
            }
            if !skipped.isEmpty {
                Section {
                    ForEach(skipped) { item in
                        FileRow(kind: item.kind, name: plan.relativePath(of: item.source), note: note(for: item))
                    }
                } header: {
                    Label((plan.isImport ? model.t("Не імпортуються, залишаться на картці", "Not imported, stay on the card")
                                         : model.t("Залишаться на місці", "Stay where they are")) + "  ·  \(skipped.count)",
                          systemImage: "arrow.uturn.backward")
                }
            }
        }
        .listStyle(.inset)
    }

    private func note(for item: PlannedItem) -> String {
        if item.action == .skipNoDate { return model.t("немає дати", "no date") }
        if item.kind == .junk { return model.t("службовий файл камери", "camera service file") }
        return model.t("інший формат", "other format")
    }

    private var footer: some View {
        HStack {
            Button(plan.isImport ? model.t("Скасувати", "Cancel") : model.t("Інша папка", "Other Folder")) { model.reset() }
            Button(model.t("Оновити", "Refresh")) { model.rescan() }
            Spacer()
            if summary.hasWork {
                Text(footerText).foregroundStyle(.secondary)
                Button(actionTitle) { model.run() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if !plan.isImport {
                Label(model.t("Усе вже відсортовано", "Everything is already sorted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionTitle: String {
        guard plan.isImport else { return model.t("Сортувати", "Sort") }
        return summary.totalToMove > 0 ? model.t("Імпортувати", "Import") : model.t("Перевірити", "Verify")
    }

    private var footerText: String {
        if plan.isImport {
            var parts: [String] = []
            if summary.totalToMove > 0 {
                parts.append(model.t("Скопіювати", "Copy") + ": \(summary.totalToMove) · " + formatBytes(bytesToCopy, model.language))
            }
            if summary.alreadyImported > 0 { parts.append(model.t("вже є", "already there") + ": \(summary.alreadyImported)") }
            return parts.joined(separator: ", ")
        }
        var parts = [model.t("Перемістити", "Move") + ": \(summary.totalToMove)"]
        if summary.toTrash > 0 { parts.append(model.t("у кошик", "to Trash") + ": \(summary.toTrash)") }
        return parts.joined(separator: ", ")
    }
}

private struct SummaryBar: View {
    @Environment(SorterModel.self) private var model
    let summary: PlanSummary

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FileKind.displayOrder, id: \.self) { kind in
                if let n = summary.toMove[kind], n > 0 {
                    Tile(symbol: kind.symbol, value: n, label: kind.title(model.language))
                }
            }
            if summary.toTrash > 0 {
                Tile(symbol: "trash", value: summary.toTrash, label: model.t("У кошик", "To Trash"))
            }
            if summary.alreadySorted > 0 {
                Tile(symbol: "checkmark.circle", value: summary.alreadySorted, label: model.t("Вже на місці", "Already sorted"))
            }
            if summary.alreadyImported > 0 {
                Tile(symbol: "checkmark.circle", value: summary.alreadyImported, label: model.t("Вже імпортовано", "Already imported"))
            }
            let skipped = summary.noDate + summary.unsupported
            if skipped > 0 {
                Tile(symbol: "arrow.uturn.backward", value: skipped, label: model.t("Пропущено", "Skipped"))
            }
            Spacer()
        }
        .padding(16)
    }
}

private struct Tile: View {
    let symbol: String
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(value)", systemImage: symbol)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MoveRow: View {
    @Environment(SorterModel.self) private var model
    let item: PlannedItem
    let plan: SortPlan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(plan.relativePath(of: item.source))
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isRenamed, case .move(let dest) = item.action {
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Text(dest.lastPathComponent)
                    .foregroundStyle(.blue)
                    .help(model.t("Файл з такою назвою вже є — буде додано номер", "A file with this name already exists — a number will be added"))
            }
            Spacer()
            if item.warnsAboutFileDate {
                Text(model.t("дата файлу", "file date"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .help(model.t("У файлі немає дати зйомки, тому взято дату його зміни", "The file has no capture date, so its modification date is used"))
            }
        }
    }
}

private struct FileRow: View {
    let kind: FileKind
    let name: String
    var note: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Результат сортування

private struct ReportView: View {
    @Environment(SorterModel.self) private var model
    let report: SortReport

    var body: some View {
        ResultLayout(
            ok: report.failures.isEmpty,
            title: report.failures.isEmpty ? model.t("Готово!", "Done!") : model.t("Готово, але не все вдалося", "Done, but some files failed"),
            lines: lines,
            problems: report.failures
        ) {
            Button(model.t("Відсортувати іншу папку", "Sort Another Folder")) { model.reset() }
            Spacer()
            if let folder = model.folder {
                Button(model.t("Відкрити у Finder", "Show in Finder")) { NSWorkspace.shared.open(folder) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var lines: [String] {
        var out: [String] = []
        for kind in FileKind.displayOrder {
            if let n = report.moved[kind], n > 0 { out.append("\(kind.title(model.language)): \(n)") }
        }
        if report.trashed > 0 { out.append(model.t("У кошик (CTG/CPF)", "Moved to Trash (CTG/CPF)") + ": \(report.trashed)") }
        if report.alreadySorted > 0 { out.append(model.t("Уже були на місці", "Already in place") + ": \(report.alreadySorted)") }
        if report.skipped > 0 { out.append(model.t("Пропущено", "Skipped") + ": \(report.skipped)") }
        if report.removedFolders > 0 { out.append(model.t("Видалено порожніх папок", "Empty folders removed") + ": \(report.removedFolders)") }
        if !report.failures.isEmpty { out.append(model.t("Помилок", "Errors") + ": \(report.failures.count)") }
        return out
    }
}

// MARK: - Результат імпорту

private struct ImportReportView: View {
    @Environment(SorterModel.self) private var model
    let report: ImportReport
    let deleted: DeleteReport?

    var body: some View {
        ResultLayout(ok: ok, title: title, lines: lines, problems: report.failures + (deleted?.kept ?? [])) {
            Button(model.t("Готово", "Done")) { model.reset() }
            Spacer()
            if deleted == nil, !report.verified.isEmpty {
                Button(model.t("Видалити з картки…", "Delete from Card…"), role: .destructive) { model.askDelete = true }
            }
            if model.importCard != nil, model.cards.contains(where: { $0.url == model.importCard?.url }) {
                Button(model.t("Витягнути картку", "Eject Card")) { model.ejectCard() }
            }
            Button(model.t("Відкрити у Finder", "Show in Finder")) { NSWorkspace.shared.open(model.destinationRoot) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var ok: Bool { report.failures.isEmpty && !report.cancelled && (deleted?.kept.isEmpty ?? true) }

    private var title: String {
        if report.cancelled { return model.t("Імпорт зупинено", "Import stopped") }
        if !report.failures.isEmpty { return model.t("Імпорт завершено, але не все вдалося", "Import finished, but some files failed") }
        if let deleted, deleted.kept.isEmpty { return model.t("Готово! Картку очищено", "Done! The card is cleared") }
        return model.t("Імпорт завершено", "Import finished")
    }

    private var lines: [String] {
        var out: [String] = []
        for kind in FileKind.displayOrder {
            if let n = report.copied[kind], n > 0 { out.append("\(kind.title(model.language)): \(n)") }
        }
        if report.bytesCopied > 0 {
            out.append(model.t("Скопійовано", "Copied") + ": " + formatBytes(report.bytesCopied, model.language))
        }
        if report.alreadyThere > 0 { out.append(model.t("Уже були імпортовані раніше", "Imported earlier") + ": \(report.alreadyThere)") }
        out.append(model.t("Перевірено копій", "Copies verified") + ": \(report.verified.count)")
        if !report.failures.isEmpty { out.append(model.t("Не вдалося скопіювати", "Couldn't copy") + ": \(report.failures.count)") }
        if let deleted {
            out.append(model.t("Видалено з картки", "Deleted from card") + ": \(deleted.deleted)")
            if !deleted.kept.isEmpty { out.append(model.t("Залишено на картці", "Kept on card") + ": \(deleted.kept.count)") }
        }
        if let ejected = model.ejectedCardName {
            out.append(model.t("Картку «\(ejected)» витягнуто — її можна виймати", "Card “\(ejected)” ejected — you can remove it"))
        }
        return out
    }
}

private struct ResultLayout<Buttons: View>: View {
    @Environment(SorterModel.self) private var model
    let ok: Bool
    let title: String
    let lines: [String]
    let problems: [SortReport.Failure]
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(ok ? .green : .orange)
                Text(title).font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { Text($0) }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 16)

            if !problems.isEmpty {
                List(problems) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.file.lastPathComponent).fontWeight(.medium)
                        Text(text(for: failure.reason)).font(.caption).foregroundStyle(.red)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
            }
            Divider()
            HStack { buttons() }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    private func text(for reason: SortReport.Failure.Reason) -> String {
        switch reason {
        case .checksumMismatch:
            return model.t("Копія не збігається з оригіналом (помилка читання картки або запису на диск)",
                           "The copy doesn't match the original (card read or disk write error)")
        case .copyMissing:
            return model.t("Копію в «\(model.destinationName)» не знайдено або вона змінилася — файл залишено на картці",
                           "The copy in “\(model.destinationName)” is missing or changed — the file was kept on the card")
        case .sourceChanged:
            return model.t("Файл на картці змінився після імпорту — його залишено", "The file on the card changed after import — it was kept")
        case .system(let message):
            return message
        }
    }
}

// MARK: - Загальне

private struct MessagePane<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(tint)
            Text(title).font(.title3.weight(.medium))
            if !text.isEmpty {
                Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            actions().padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension FileKind {
    static let displayOrder: [FileKind] = [.photo, .raw, .sidecar, .psd, .video, .videoSidecar]

    func title(_ language: AppLanguage) -> String {
        let uk = language == .uk
        switch self {
        case .raw: return "RAW"
        case .sidecar: return "XMP"
        case .photo: return uk ? "Фото" : "Photos"
        case .video: return uk ? "Відео" : "Videos"
        case .psd: return "PSD"
        case .videoSidecar: return "Gyroflow"
        case .junk: return uk ? "Службові" : "Service"
        case .other: return uk ? "Інші" : "Other"
        }
    }

    var symbol: String {
        switch self {
        case .raw: return "camera.aperture"
        case .sidecar: return "slider.horizontal.3"
        case .photo: return "photo"
        case .video: return "video"
        case .psd: return "square.3.layers.3d"
        case .videoSidecar: return "gyroscope"
        case .junk: return "trash"
        case .other: return "doc"
        }
    }
}
