import Foundation
import Testing
@testable import SorterCore

/// «Картка» і «Зображення» — дві тимчасові папки.
struct ImportFixture {
    let card = try! TempFolder()
    let pictures = try! TempFolder()
    let days: [String: DayDate]

    func plan() async throws -> SortPlan {
        try await Planner(reader: FakeReader(days: days))
            .makePlan(root: card.url, naming: .dayMonthYear, importInto: pictures.url)
    }

    func importAll() async throws -> ImportReport {
        Importer().run(try await plan())
    }
}

@Test func importCopiesSortedAndLeavesCardIntact() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15, "IMG_1.CR3": may15, "MVI_2.MP4": jan2])
    try f.card.file("DCIM/100CANON/IMG_1.JPG", "jpg")
    try f.card.file("DCIM/100CANON/IMG_1.CR3", "raw")
    try f.card.file("DCIM/100CANON/MVI_2.MP4", "video")
    try f.card.file("DCIM/CANONMSC/M0100.CTG", "ctg")
    let cardBefore = f.card.allFiles()

    let plan = try await f.plan()
    #expect(plan.isImport)
    #expect(plan.summary.totalToMove == 3)
    let report = Importer().run(plan)

    #expect(report.failures.isEmpty)
    #expect(report.totalCopied == 3)
    #expect(report.verified.count == 3)
    #expect(f.pictures.allFiles() == [
        "15 травня 2024/IMG_1.JPG",
        "15 травня 2024/raw/IMG_1.CR3",
        "2 січня 2025/video/MVI_2.MP4",
    ])
    #expect(try f.pictures.read("2 січня 2025/video/MVI_2.MP4") == "video")
    // На картці нічого не змінилося (і службовий CTG не чіпали).
    #expect(f.card.allFiles() == cardBefore)
}

@Test func importKeepsFileDates() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15])
    let src = try f.card.file("IMG_1.JPG")
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: src.path)
    _ = try await f.importAll()
    let copy = f.pictures.url.appendingPathComponent("15 травня 2024/IMG_1.JPG")
    #expect(Importer.modificationDate(copy) == old)
}

@Test func importLeavesNoTemporaryFiles() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15])
    try f.card.file("IMG_1.JPG", String(repeating: "x", count: 100_000))
    var importer = Importer()
    importer.chunkSize = 4096          // багато шматків
    _ = importer.run(try await f.plan())
    let all = try FileManager.default.subpathsOfDirectory(atPath: f.pictures.url.path)
    #expect(!all.contains { $0.hasSuffix(".part") })
    #expect(try f.pictures.read("15 травня 2024/IMG_1.JPG").count == 100_000)
}

@Test func reimportRecognisesAlreadyImportedFiles() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15, "IMG_1.xmp": may15])
    try f.card.file("IMG_1.JPG", "jpg")
    try f.card.file("IMG_1.xmp", "xmp")
    _ = try await f.importAll()
    let afterFirst = f.pictures.allFiles()

    let plan = try await f.plan()
    #expect(plan.summary.totalToMove == 0)
    #expect(plan.summary.alreadyImported == 2)
    #expect(plan.summary.hasWork)           // можна перевірити й видалити з картки
    let report = Importer().run(plan)

    #expect(report.alreadyThere == 2)
    #expect(report.verified.count == 2)
    #expect(f.pictures.allFiles() == afterFirst)   // жодних IMG_1_1.JPG
}

@Test func sameNameDifferentContentGetsNumber() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15, "IMG_2.JPG": may15])
    try f.pictures.file("15 травня 2024/IMG_1.JPG", "other camera, longer")   // інший розмір
    try f.pictures.file("15 травня 2024/IMG_2.JPG", "BBB")                    // той самий розмір, інший вміст
    try f.card.file("IMG_1.JPG", "new")
    try f.card.file("IMG_2.JPG", "AAA")

    let plan = try await f.plan()
    #expect(plan.summary.alreadyImported == 1)      // IMG_2 — підозра за розміром
    let report = Importer().run(plan)

    #expect(report.alreadyThere == 0)
    #expect(report.totalCopied == 2)
    #expect(try f.pictures.read("15 травня 2024/IMG_1.JPG") == "other camera, longer")
    #expect(try f.pictures.read("15 травня 2024/IMG_1_1.JPG") == "new")
    #expect(try f.pictures.read("15 травня 2024/IMG_2.JPG") == "BBB")
    #expect(try f.pictures.read("15 травня 2024/IMG_2_1.JPG") == "AAA")
}

// MARK: - Видалення з картки

@Test func deleteRemovesOnlyVerifiedFiles() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15, "MVI_2.MP4": jan2])
    try f.card.file("DCIM/100CANON/IMG_1.JPG")
    try f.card.file("DCIM/100CANON/MVI_2.MP4")
    try f.card.file("DCIM/100CANON/nodate.jpg")     // без дати — не імпортується
    try f.card.file("DCIM/CANONMSC/M0100.CTG")
    try f.card.file("readme.txt")
    let report = try await f.importAll()

    let deleted = Importer.deleteOriginals(report.verified)
    #expect(deleted.deleted == 2)
    #expect(deleted.kept.isEmpty)
    #expect(f.card.allFiles() == ["DCIM/100CANON/nodate.jpg", "DCIM/CANONMSC/M0100.CTG", "readme.txt"])
    #expect(f.pictures.allFiles().count == 2)
}

@Test func failedCopyIsNeverDeleted() async throws {
    let f = ImportFixture(days: ["good.jpg": may15, "broken.jpg": may15])
    try f.card.file("good.jpg")
    let broken = try f.card.file("broken.jpg")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: broken.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: broken.path) }

    let report = try await f.importAll()
    #expect(report.failures.count == 1)
    if case .system = report.failures.first?.reason {} else { Issue.record("очікувалась системна помилка читання") }
    #expect(report.verified.map(\.source.lastPathComponent) == ["good.jpg"])

    _ = Importer.deleteOriginals(report.verified)
    #expect(f.card.exists("broken.jpg"))
    #expect(!f.card.exists("good.jpg"))
}

@Test func deleteKeepsFileWhoseCopyDisappeared() async throws {
    let f = ImportFixture(days: ["a.jpg": may15, "b.jpg": may15])
    try f.card.file("a.jpg")
    try f.card.file("b.jpg")
    let report = try await f.importAll()
    try FileManager.default.removeItem(at: f.pictures.url.appendingPathComponent("15 травня 2024/a.jpg"))

    let deleted = Importer.deleteOriginals(report.verified)
    #expect(deleted.deleted == 1)
    #expect(deleted.kept.map(\.reason) == [.copyMissing])
    #expect(f.card.exists("a.jpg"))
}

@Test func deleteKeepsFileChangedOnCard() async throws {
    let f = ImportFixture(days: ["a.jpg": may15])
    let src = try f.card.file("a.jpg", "one")
    let report = try await f.importAll()
    try Data("changed!".utf8).write(to: src)

    let deleted = Importer.deleteOriginals(report.verified)
    #expect(deleted.deleted == 0)
    #expect(deleted.kept.map(\.reason) == [.sourceChanged])
    #expect(try f.card.read("a.jpg") == "changed!")
}

@Test func organizeModeIsNotImport() async throws {
    let t = try TempFolder()
    try t.file("IMG_1.JPG")
    let plan = try await Planner(reader: FakeReader(days: ["IMG_1.JPG": may15])).makePlan(root: t.url, naming: .dayMonthYear)
    #expect(!plan.isImport)
    #expect(plan.destinationRoot == plan.root)
}

// MARK: - Вибірковий імпорт

@Test func sidecarsKnowTheirPrimary() async throws {
    let f = ImportFixture(days: ["IMG_1.CR3": may15, "MVI_2.MP4": jan2])
    let raw = try f.card.file("IMG_1.CR3")
    try f.card.file("IMG_1.xmp")
    let video = try f.card.file("MVI_2.MP4")
    try f.card.file("MVI_2.gyroflow")
    let plan = try await f.plan()
    let byName = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.source.lastPathComponent, $0) })
    #expect(byName["IMG_1.xmp"]?.companionOf == raw.standardizedFileURL)
    #expect(byName["MVI_2.gyroflow"]?.companionOf == video.standardizedFileURL)
    #expect(byName["IMG_1.CR3"]?.companionOf == nil)
}

@Test func excludedFilesAreNotImportedAndNeverDeleted() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15, "IMG_1.CR3": may15, "IMG_2.JPG": jan2])
    try f.card.file("IMG_1.JPG")
    let raw = try f.card.file("IMG_1.CR3")
    try f.card.file("IMG_1.xmp")                       // іде за RAW — теж виключається
    try f.card.file("IMG_2.JPG")

    let full = try await f.plan()
    let plan = full.excluding([raw.standardizedFileURL])
    #expect(plan.summary.totalToMove == 2)
    #expect(full.isExcluded(full.items.first { $0.source.lastPathComponent == "IMG_1.xmp" }!, by: [raw.standardizedFileURL]))

    let report = Importer().run(plan)
    #expect(f.pictures.allFiles() == ["15 травня 2024/IMG_1.JPG", "2 січня 2025/IMG_2.JPG"])

    _ = Importer.deleteOriginals(report.verified)
    #expect(f.card.allFiles() == ["IMG_1.CR3", "IMG_1.xmp"])   // невибрані лишилися на картці
}

@Test func excludingNothingKeepsPlan() async throws {
    let f = ImportFixture(days: ["IMG_1.JPG": may15])
    try f.card.file("IMG_1.JPG")
    let plan = try await f.plan()
    #expect(plan.excluding([]).items.count == plan.items.count)
}
