import Foundation
import Testing
@testable import SorterCore

// Виправлення після перегляду коду (листопад 2026).

@Test func impossibleDatesAreRejected() {
    #expect(DayDate.parse("2024:02:31 10:00:00") == nil)
    #expect(DayDate.parse("2023:02:29 10:00:00") == nil)
    #expect(DayDate.parse("2024:02:29 10:00:00") != nil)   // високосний
    #expect(DayDate.parse("2024:04:31 10:00:00") == nil)
    #expect(DayDate.parse("2024:12:31 10:00:00") != nil)
}

@Test func newRawDoesNotPairWithForeignXmp() async throws {
    let f = ImportFixture(days: ["IMG_1.CR3": may15, "IMG_1.xmp": may15])
    try f.pictures.file("15 травня 2024/raw/IMG_1.xmp", "old edits of another photo")
    try f.card.file("DCIM/IMG_1.CR3", "new raw")
    try f.card.file("DCIM/IMG_1.xmp", "new xmp!")
    _ = try await f.importAll()
    #expect(try f.pictures.read("15 травня 2024/raw/IMG_1_1.CR3") == "new raw")
    #expect(try f.pictures.read("15 травня 2024/raw/IMG_1_1.xmp") == "new xmp!")
    #expect(try f.pictures.read("15 травня 2024/raw/IMG_1.xmp") == "old edits of another photo")
}

@Test func newVideoDoesNotPairWithForeignGyroflow() async throws {
    let t = try TempFolder()
    try t.file("15 травня 2024/video/C0001.gyroflow", "old")
    try t.file("C0001.MP4", "new")
    _ = try await sort(t, ["C0001.MP4": may15])
    #expect(try t.read("15 травня 2024/video/C0001_1.MP4") == "new")
}

@Test func deleteRereadsCardAndKeepsFileThatReadsDifferently() async throws {
    let f = ImportFixture(days: ["a.jpg": may15])
    let src = try f.card.file("a.jpg", "abc")
    let fixed = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes([.modificationDate: fixed], ofItemAtPath: src.path)
    let report = try await f.importAll()
    // Той самий розмір і дата зміни, але інші байти — як збій читання картки.
    try Data("xyz".utf8).write(to: src)
    try FileManager.default.setAttributes([.modificationDate: fixed], ofItemAtPath: src.path)

    let deleted = Importer.deleteOriginals(report.verified)
    #expect(deleted.deleted == 0)
    #expect(deleted.kept.map(\.reason) == [.checksumMismatch])
    #expect(f.card.exists("a.jpg"))
}

@Test func deleteReportsProgress() async throws {
    let f = ImportFixture(days: ["a.jpg": may15, "b.jpg": may15])
    try f.card.file("a.jpg")
    try f.card.file("b.jpg")
    let report = try await f.importAll()
    var steps: [Int] = []
    let deleted = Importer.deleteOriginals(report.verified) { partial, total in
        #expect(total == 2)
        steps.append(partial.checked)
    }
    #expect(steps == [1, 2])
    #expect(deleted.deleted == 2)
}

@Test func veryLongFileNameImports() async throws {
    let name = String(repeating: "довга_назва_", count: 10) + ".jpg"   // ~230 байтів
    #expect(name.utf8.count < 255)
    let f = ImportFixture(days: [name: may15])
    try f.card.file(name, "x")
    let report = try await f.importAll()
    #expect(report.failures.isEmpty)
    #expect(f.pictures.exists("15 травня 2024/" + name))
}
