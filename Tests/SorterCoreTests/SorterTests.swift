import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SorterCore

// MARK: - Допоміжне

/// Підставна «дата зйомки» за назвою файлу.
struct FakeReader: CaptureDateReading {
    var days: [String: DayDate]
    /// Якщо задано — для решти файлів «дата зміни файлу».
    var fileDate: DayDate? = nil
    func captureDay(of url: URL, kind: FileKind) async -> CaptureDay? {
        if let d = days[url.lastPathComponent] { return CaptureDay(day: d, source: .exif) }
        return fileDate.map { CaptureDay(day: $0, source: .fileDate) }
    }
}

final class TempFolder {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SorterTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ relative: String, _ content: String = "x") throws -> URL {
        let f = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: f)
        return f
    }
    func dir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent(relative), withIntermediateDirectories: true)
    }
    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }
    func read(_ relative: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
    }
    /// Усі файли відносно папки, відсортовано.
    func allFiles() -> [String] {
        let base = url.path + "/"
        let e = FileManager.default.enumerator(atPath: url.path)!
        var out: [String] = []
        while let p = e.nextObject() as? String {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: base + p, isDirectory: &isDir)
            if !isDir.boolValue { out.append(p) }
        }
        return out.sorted()
    }
}

let may15 = DayDate(year: 2024, month: 5, day: 15)!
let jan2 = DayDate(year: 2025, month: 1, day: 2)!

/// Тести не чіпають справжній кошик — службові файли просто видаляються.
let testExecutor = Executor(trash: { try FileManager.default.removeItem(at: $0) })

func sort(_ t: TempFolder, _ days: [String: DayDate], naming: FolderNaming = .dayMonthYear) async throws -> (SortPlan, SortReport) {
    let plan = try await Planner(reader: FakeReader(days: days)).makePlan(root: t.url, naming: naming)
    return (plan, testExecutor.run(plan))
}

// MARK: - Дати й назви

@Test func parsesExifAndIsoDates() {
    #expect(DayDate.parse("2024:05:15 10:20:30") == may15)
    #expect(DayDate.parse("2024-05-15T23:59:00+03:00") == may15)
    #expect(DayDate.parse("0000:00:00 00:00:00") == nil)
    #expect(DayDate.parse("2024:13:01") == nil)
    #expect(DayDate.parse("garbage") == nil)
    #expect(DayDate.parse("2024:05-15") == nil)
}

@Test func folderNames() {
    #expect(FolderNaming.dayMonthYear.relativePath(for: may15) == "15 травня 2024")
    #expect(FolderNaming.isoWithName.relativePath(for: jan2) == "2025-01-02 (2 січня)")
    #expect(FolderNaming.yearThenDay.relativePath(for: may15) == "2024/15 травня 2024")
}

@Test func englishFolderNames() {
    let dec31 = DayDate(year: 2025, month: 12, day: 31)!
    #expect(FolderNaming.dayMonthYearEnglish.relativePath(for: may15) == "15 May 2024")
    #expect(FolderNaming.isoWithNameEnglish.relativePath(for: jan2) == "2025-01-02 (2 January)")
    #expect(FolderNaming.yearThenDayEnglish.relativePath(for: dec31) == "2025/31 December 2025")
    #expect(FolderNaming.englishCases.count == 3)
    #expect(FolderNaming.ukrainianCases.count == 3)
    #expect(FolderNaming.englishCases.allSatisfy { $0.isEnglish })
}

@Test func switchingToEnglishNamesMovesSortedFoldersOnce() async throws {
    let t = try TempFolder()
    try t.file("IMG_1.JPG")
    try t.file("IMG_1.CR3")
    let days = ["IMG_1.JPG": may15, "IMG_1.CR3": may15]
    _ = try await sort(t, days)                                   // 15 травня 2024
    _ = try await sort(t, days, naming: .dayMonthYearEnglish)     // → 15 May 2024
    #expect(t.allFiles() == ["15 May 2024/IMG_1.JPG", "15 May 2024/raw/IMG_1.CR3"])
    #expect(!t.exists("15 травня 2024"))
    // Повторний запуск з тими самими назвами нічого не змінює.
    let (again, _) = try await sort(t, days, naming: .dayMonthYearEnglish)
    #expect(!again.summary.hasWork)
}

@Test func fileKinds() {
    #expect(FileKind.of(extension: "CR3") == .raw)
    #expect(FileKind.of(extension: "xmp") == .sidecar)
    #expect(FileKind.of(extension: "HEIC") == .photo)
    #expect(FileKind.of(extension: "MOV") == .video)
    #expect(FileKind.of(extension: "gyroflow") == .videoSidecar)
    #expect(FileKind.of(extension: "PSD") == .psd)
    #expect(FileKind.of(extension: "psb") == .psd)
    #expect(FileKind.of(extension: "ctg") == .junk)
    #expect(FileKind.of(extension: "txt") == .other)
}

// MARK: - Сортування

@Test func sortsByKindIntoDateFolders() async throws {
    let t = try TempFolder()
    try t.file("card/DCIM/IMG_1.CR3")
    try t.file("card/DCIM/IMG_1.JPG")
    try t.file("card/DCIM/MVI_2.MP4")
    try t.file("card/DCIM/iphone.heic")
    try t.file("card/DCIM/CANONMSC/M0100.CTG")
    try t.file("notes.txt")

    let (plan, report) = try await sort(t, [
        "IMG_1.CR3": may15, "IMG_1.JPG": may15, "MVI_2.MP4": jan2, "iphone.heic": jan2,
    ])

    #expect(plan.summary.totalToMove == 4)
    #expect(report.failures.isEmpty)
    #expect(report.trashed == 1)
    #expect(t.allFiles() == [
        "15 травня 2024/IMG_1.JPG",
        "15 травня 2024/raw/IMG_1.CR3",
        "2 січня 2025/iphone.heic",
        "2 січня 2025/video/MVI_2.MP4",
        "notes.txt",
    ])
    // Папка card/… спорожніла й видалена.
    #expect(!t.exists("card"))
}

@Test func planAloneChangesNothing() async throws {
    let t = try TempFolder()
    try t.file("a/IMG_1.JPG")
    try t.file("a/M.CTG")
    let before = t.allFiles()
    let plan = try await Planner(reader: FakeReader(days: ["IMG_1.JPG": may15])).makePlan(root: t.url, naming: .dayMonthYear)
    #expect(plan.summary.hasWork)
    #expect(t.allFiles() == before)
}

@Test func secondRunDoesNotRenameAnything() async throws {
    // Головна вада старого скрипта: повторний запуск давав IMG_1_1.jpg.
    let t = try TempFolder()
    try t.file("IMG_1.JPG")
    try t.file("IMG_1.CR3")
    try t.file("IMG_1.xmp")
    try t.file("MVI_2.MOV")
    let days = ["IMG_1.JPG": may15, "IMG_1.CR3": may15, "MVI_2.MOV": may15]

    _ = try await sort(t, days)
    let afterFirst = t.allFiles()
    let (plan, report) = try await sort(t, days)

    #expect(!plan.summary.hasWork)
    #expect(report.alreadySorted == 4)
    #expect(t.allFiles() == afterFirst)
}

@Test func duplicateNamesGetSuffix() async throws {
    let t = try TempFolder()
    try t.file("cardA/IMG_1.JPG", "A")
    try t.file("cardB/IMG_1.JPG", "B")
    try t.file("15 травня 2024/IMG_2.JPG", "old")    // уже відсортований
    try t.file("cardC/IMG_2.JPG", "C")

    let (plan, _) = try await sort(t, ["IMG_1.JPG": may15, "IMG_2.JPG": may15])

    #expect(plan.summary.renamed == 2)
    #expect(try t.read("15 травня 2024/IMG_1.JPG") == "A")
    #expect(try t.read("15 травня 2024/IMG_1_1.JPG") == "B")
    #expect(try t.read("15 травня 2024/IMG_2.JPG") == "old")
    #expect(try t.read("15 травня 2024/IMG_2_1.JPG") == "C")
}

@Test func xmpFollowsItsRawIncludingRename() async throws {
    let t = try TempFolder()
    try t.file("15 травня 2024/raw/IMG_1.CR3", "old")
    try t.file("new/IMG_1.CR3", "new")
    try t.file("new/IMG_1.xmp", "new-xmp")         // Lightroom: IMG_1.xmp
    try t.file("new/IMG_3.CR3")
    try t.file("new/IMG_3.CR3.xmp")                // darktable: IMG_3.CR3.xmp
    // Дата .xmp не задана — вона має взятися з RAW.
    let (plan, _) = try await sort(t, ["IMG_1.CR3": may15, "IMG_3.CR3": jan2])

    #expect(try t.read("15 травня 2024/raw/IMG_1_1.CR3") == "new")
    #expect(try t.read("15 травня 2024/raw/IMG_1_1.xmp") == "new-xmp")
    #expect(t.exists("2 січня 2025/raw/IMG_3.CR3.xmp"))
    #expect(plan.items.filter { $0.kind == .sidecar }.allSatisfy { $0.capture?.source == .companion })
}

@Test func gyroflowFollowsItsVideoIncludingRename() async throws {
    let t = try TempFolder()
    try t.file("15 травня 2024/video/C0001.MP4", "old")
    try t.file("card/C0001.MP4", "new")
    try t.file("card/C0001.gyroflow", "new-gyro")       // C0001.gyroflow
    try t.file("card/C0002.MP4")
    try t.file("card/C0002.MP4.gyroflow")               // C0002.MP4.gyroflow
    try t.file("card/C0002.xmp")                        // .xmp з тим самим ім'ям не плутається з .gyroflow
    let (plan, _) = try await sort(t, ["C0001.MP4": may15, "C0002.MP4": jan2])

    #expect(try t.read("15 травня 2024/video/C0001_1.MP4") == "new")
    #expect(try t.read("15 травня 2024/video/C0001_1.gyroflow") == "new-gyro")
    #expect(t.exists("2 січня 2025/video/C0002.MP4.gyroflow"))
    #expect(t.exists("2 січня 2025/video/C0002.xmp"))
    #expect(plan.items.filter { $0.kind == .videoSidecar }.allSatisfy { $0.capture?.source == .companion })

    // Повторний запуск нічого не змінює.
    let (again, _) = try await sort(t, ["C0001.MP4": may15, "C0002.MP4": jan2])
    #expect(!again.summary.hasWork)
}

@Test func gyroflowFindsItsVideoInAnotherFolder() async throws {
    // Як на скріншоті: відео вже відсортовані, а .gyroflow лежать окремо в video/.
    let t = try TempFolder()
    let oct12 = DayDate(year: 2026, month: 10, day: 12)!
    try t.file("12 жовтня 2026/video/A_0006C566H261012_CANON.MP4")
    try t.file("video/A_0006C566H261012_CANON.gyroflow")
    let reader = FakeReader(days: ["A_0006C566H261012_CANON.MP4": oct12], fileDate: jan2)
    let plan = try await Planner(reader: reader).makePlan(root: t.url, naming: .dayMonthYear)

    #expect(plan.summary.usesFileDate == 0)          // без попередження про дату
    #expect(plan.items.allSatisfy { !$0.warnsAboutFileDate })
    _ = testExecutor.run(plan)
    #expect(t.allFiles() == [
        "12 жовтня 2026/video/A_0006C566H261012_CANON.MP4",
        "12 жовтня 2026/video/A_0006C566H261012_CANON.gyroflow",
    ])
}

@Test func gyroflowWithAmbiguousVideoNameUsesOwnDate() async throws {
    // Дві різні C0001.MP4 у різних днях — не вгадуємо, беремо дату самого файлу.
    let t = try TempFolder()
    try t.file("day1/C0001.MP4")
    try t.file("day2/C0001.MP4")
    try t.file("projects/C0001.gyroflow")
    final class DirReader: CaptureDateReading {
        func captureDay(of url: URL, kind: FileKind) async -> CaptureDay? {
            switch url.deletingLastPathComponent().lastPathComponent {
            case "day1": return CaptureDay(day: may15, source: .video)
            case "day2": return CaptureDay(day: jan2, source: .video)
            default: return CaptureDay(day: DayDate(year: 2026, month: 1, day: 1)!, source: .fileDate)
            }
        }
    }
    let plan = try await Planner(reader: DirReader()).makePlan(root: t.url, naming: .dayMonthYear)
    _ = testExecutor.run(plan)
    #expect(t.exists("1 січня 2026/video/C0001.gyroflow"))
    #expect(plan.summary.usesFileDate == 0)
}

@Test func psdGoesToPsdFolder() async throws {
    let t = try TempFolder()
    try t.file("IMG_3699 copy.psd")
    try t.file("panorama.psb")
    let (plan, _) = try await sort(t, ["IMG_3699 copy.psd": may15, "panorama.psb": may15])
    #expect(plan.summary.toMove[.psd] == 2)
    #expect(t.allFiles() == ["15 травня 2024/PSD/IMG_3699 copy.psd", "15 травня 2024/PSD/panorama.psb"])
}

@Test func psdWithoutDateIsStillFlagged() async throws {
    let t = try TempFolder()
    try t.file("edit.psd")
    let plan = try await Planner(reader: FakeReader(days: [:], fileDate: jan2)).makePlan(root: t.url, naming: .dayMonthYear)
    #expect(plan.summary.usesFileDate == 1)
}

@Test func gyroflowWithoutVideoGoesToVideoFolder() async throws {
    let t = try TempFolder()
    try t.file("project.gyroflow")
    _ = try await sort(t, ["project.gyroflow": jan2])
    #expect(t.exists("2 січня 2025/video/project.gyroflow"))
}

@Test func xmpWithoutRawUsesOwnDate() async throws {
    let t = try TempFolder()
    try t.file("lonely.xmp")
    _ = try await sort(t, ["lonely.xmp": jan2])
    #expect(t.exists("2 січня 2025/raw/lonely.xmp"))
}

@Test func filesWithoutDateStayInPlace() async throws {
    let t = try TempFolder()
    try t.file("sub/nodate.jpg")
    let (plan, report) = try await sort(t, [:])
    #expect(plan.summary.noDate == 1)
    #expect(report.skipped == 1)
    #expect(t.exists("sub/nodate.jpg"))
}

@Test func onlyEmptiedFoldersAreRemoved() async throws {
    let t = try TempFolder()
    try t.dir("my empty folder")                   // користувач створив сам — не чіпаємо
    try t.file("trip/day1/.DS_Store")
    try t.file("trip/day1/IMG_1.JPG")
    try t.file("keep/IMG_2.JPG")
    try t.file("keep/readme.txt")

    let (_, report) = try await sort(t, ["IMG_1.JPG": may15, "IMG_2.JPG": may15])

    #expect(t.exists("my empty folder"))
    #expect(!t.exists("trip"))
    #expect(t.exists("keep/readme.txt"))
    #expect(report.removedFolders == 2)
}

@Test func otherNamingStyles() async throws {
    let t = try TempFolder()
    try t.file("IMG_1.JPG")
    try t.file("MVI.MP4")
    _ = try await sort(t, ["IMG_1.JPG": may15, "MVI.MP4": may15], naming: .yearThenDay)
    #expect(t.allFiles() == ["2024/15 травня 2024/IMG_1.JPG", "2024/15 травня 2024/video/MVI.MP4"])

    // Перехід на інший стиль переносить уже відсортоване.
    _ = try await sort(t, ["IMG_1.JPG": may15, "MVI.MP4": may15], naming: .isoWithName)
    #expect(t.allFiles() == ["2024-05-15 (15 травня)/IMG_1.JPG", "2024-05-15 (15 травня)/video/MVI.MP4"])
}

@Test func doesNotEnterPackages() async throws {
    let t = try TempFolder()
    try t.file("Photos Library.photoslibrary/originals/IMG_1.JPG")
    try t.file("IMG_2.JPG")
    let (plan, _) = try await sort(t, ["IMG_1.JPG": may15, "IMG_2.JPG": may15])
    #expect(plan.items.count == 1)
    #expect(t.exists("Photos Library.photoslibrary/originals/IMG_1.JPG"))
}

@Test func missingFolderThrows() async {
    await #expect(throws: PlannerError.self) {
        _ = try await Planner().makePlan(root: URL(fileURLWithPath: "/nonexistent-\(UUID())"), naming: .dayMonthYear)
    }
}

// MARK: - Справжнє читання метаданих

func writeJPEG(to url: URL, exifDate: String?) throws {
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var props: [CFString: Any] = [:]
    if let exifDate {
        props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: exifDate]
    }
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
}

@Test func systemReaderReadsExif() async throws {
    let t = try TempFolder()
    let photo = t.url.appendingPathComponent("photo.jpg")
    try writeJPEG(to: photo, exifDate: "2024:05:15 18:30:00")
    let result = await SystemDateReader().captureDay(of: photo, kind: .photo)
    #expect(result == CaptureDay(day: may15, source: .exif))
}

@Test func systemReaderFallsBackToFileDate() async throws {
    let t = try TempFolder()
    let photo = t.url.appendingPathComponent("noexif.jpg")
    try writeJPEG(to: photo, exifDate: nil)
    var c = DateComponents(); c.year = 2025; c.month = 1; c.day = 2; c.hour = 12
    try FileManager.default.setAttributes([.modificationDate: Calendar.current.date(from: c)!], ofItemAtPath: photo.path)
    let result = await SystemDateReader().captureDay(of: photo, kind: .photo)
    #expect(result == CaptureDay(day: jan2, source: .fileDate))
}

@Test func systemReaderReadsXmp() async throws {
    let t = try TempFolder()
    let a = try t.file("a.xmp", #"<rdf:Description exif:DateTimeOriginal="2024-05-15T10:00:00"/>"#)
    let b = try t.file("b.xmp", "<xmp:CreateDate>2025-01-02T08:00:00</xmp:CreateDate>")
    #expect(await SystemDateReader().captureDay(of: a, kind: .sidecar)?.day == may15)
    #expect(await SystemDateReader().captureDay(of: b, kind: .sidecar)?.source == .xmp)
}

@Test func systemReaderReadsPsdExif() async throws {
    let t = try TempFolder()
    let psd = t.url.appendingPathComponent("edit.psd")
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    guard let dest = CGImageDestinationCreateWithURL(psd as CFURL, "com.adobe.photoshop-image" as CFString, 1, nil) else {
        return  // ця macOS не вміє записувати PSD — нічого перевіряти
    }
    let props: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:15 12:00:00"]]
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    #expect(CGImageDestinationFinalize(dest))
    let result = await SystemDateReader().captureDay(of: psd, kind: .psd)
    #expect(result == CaptureDay(day: may15, source: .exif))
}
