import Foundation
import Testing
@testable import SorterCore

// Супровідні файли відео: .THM, .LRV, .XML (Sony), .SRT (DJI), *_mix.bin (NiYien).

@Test func videoSidecarKinds() {
    #expect(FileKind.of(URL(fileURLWithPath: "/c/MVI_1.THM")) == .thumbnail)
    #expect(FileKind.of(URL(fileURLWithPath: "/c/GL010123.LRV")) == .proxy)
    #expect(FileKind.of(URL(fileURLWithPath: "/c/C0001M01.XML")) == .videoMeta)
    #expect(FileKind.of(URL(fileURLWithPath: "/c/DJI_0001.SRT")) == .videoMeta)
    #expect(FileKind.of(URL(fileURLWithPath: "/c/2026-10-12_17-06-59_mix.bin")) == .gyroLog)
    #expect(FileKind.of(URL(fileURLWithPath: "/c/firmware.bin")) == .other)     // звичайний .bin не чіпаємо
    #expect(FileKind.gyroLog.subfolder == "video/gyro")
    #expect(FileKind.proxy.subfolder == "video/proxy")
}

@Test func companionStemVariants() {
    #expect(PlanBuilderNames.stems("C0001M01", .videoMeta) == ["C0001M01", "C0001"])
    #expect(PlanBuilderNames.stems("GL010123", .proxy) == ["GL010123", "GX010123", "GH010123"])
    #expect(PlanBuilderNames.stems("DJI_0001", .proxy) == ["DJI_0001"])
    #expect(PlanBuilderNames.stems("M01", .videoMeta) == ["M01"])               // сама «M01» — не суфікс
}

@Test func canonThmFollowsVideo() async throws {
    let t = try TempFolder()
    try t.file("DCIM/100CANON/MVI_1234.MP4")
    try t.file("DCIM/100CANON/MVI_1234.THM")
    _ = try await sort(t, ["MVI_1234.MP4": may15])
    #expect(t.allFiles() == ["15 травня 2024/video/MVI_1234.MP4", "15 травня 2024/video/MVI_1234.THM"])
}

@Test func sonyXmlFollowsVideoIncludingRename() async throws {
    let t = try TempFolder()
    try t.file("15 травня 2024/video/C0001.MP4", "old")
    try t.file("PRIVATE/M4ROOT/CLIP/C0001.MP4", "new")
    try t.file("PRIVATE/M4ROOT/CLIP/C0001M01.XML", "meta")
    _ = try await sort(t, ["C0001.MP4": may15])
    #expect(try t.read("15 травня 2024/video/C0001_1.MP4") == "new")
    #expect(try t.read("15 травня 2024/video/C0001_1M01.XML") == "meta")
}

@Test func djiSrtAndLrvFollowVideo() async throws {
    let t = try TempFolder()
    try t.file("DCIM/100MEDIA/DJI_0001.MP4")
    try t.file("DCIM/100MEDIA/DJI_0001.SRT")
    try t.file("DCIM/100MEDIA/DJI_0001.LRV")
    let (plan, _) = try await sort(t, ["DJI_0001.MP4": jan2])
    #expect(t.allFiles() == [
        "2 січня 2025/video/DJI_0001.MP4",
        "2 січня 2025/video/DJI_0001.SRT",
        "2 січня 2025/video/proxy/DJI_0001.LRV",
    ])
    #expect(plan.summary.usesFileDate == 0)
}

@Test func goproProxyFindsVideoByPrefixSwap() async throws {
    let t = try TempFolder()
    try t.file("2 січня 2025/video/GX010123.MP4", "old")
    try t.file("DCIM/100GOPRO/GX010123.MP4", "new")
    try t.file("DCIM/100GOPRO/GL010123.LRV", "proxy")
    try t.file("DCIM/100GOPRO/GX010123.THM", "thm")
    _ = try await sort(t, ["GX010123.MP4": jan2])
    #expect(try t.read("2 січня 2025/video/GX010123_1.MP4") == "new")
    #expect(try t.read("2 січня 2025/video/proxy/GL010123_1.LRV") == "proxy")
    #expect(try t.read("2 січня 2025/video/GX010123_1.THM") == "thm")
}

@Test func xmlAndSrtWithoutVideoStayPut() async throws {
    let t = try TempFolder()
    try t.file("notes/subtitles.srt")
    try t.file("notes/config.xml")
    try t.file("notes/IMG_1.JPG")
    try t.file("notes/IMG_1.xml")              // поруч лише фото — не відео
    let (plan, _) = try await sort(t, ["IMG_1.JPG": may15, "subtitles.srt": may15, "config.xml": may15, "IMG_1.xml": may15])
    #expect(plan.summary.unsupported == 3)
    #expect(t.exists("notes/subtitles.srt"))
    #expect(t.exists("notes/config.xml"))
    #expect(t.exists("notes/IMG_1.xml"))
}

@Test func lonelyProxyAndThmUseOwnDate() async throws {
    let t = try TempFolder()
    try t.file("GL999.LRV")
    try t.file("MVI_9.THM")
    let (plan, _) = try await sort(t, ["GL999.LRV": may15, "MVI_9.THM": may15])
    #expect(t.allFiles() == ["15 травня 2024/video/MVI_9.THM", "15 травня 2024/video/proxy/GL999.LRV"])
    #expect(plan.items.allSatisfy { !$0.warnsAboutFileDate })
}

@Test func niyienGyroLogsGoToGyroFolderByNameDate() async throws {
    let t = try TempFolder()
    try t.file("2026-10-12/2026-10-12_17-06-59_mix.bin")
    try t.file("2026-10-12/2026-10-12_17-07-05_mix.bin")
    let plan = try await Planner(reader: SystemDateReader()).makePlan(root: t.url, naming: .dayMonthYear)
    #expect(plan.items.allSatisfy { $0.capture?.source == .fileName })
    _ = testExecutor.run(plan)
    #expect(t.allFiles() == [
        "12 жовтня 2026/video/gyro/2026-10-12_17-06-59_mix.bin",
        "12 жовтня 2026/video/gyro/2026-10-12_17-07-05_mix.bin",
    ])
}

@Test func videoSidecarsSecondRunChangesNothing() async throws {
    let t = try TempFolder()
    try t.file("C0001.MP4")
    try t.file("C0001M01.XML")
    try t.file("C0001.THM")
    try t.file("C0001.LRV")
    try t.file("C0001.SRT")
    let days = ["C0001.MP4": may15]
    _ = try await sort(t, days)
    let first = t.allFiles()
    let (plan, _) = try await sort(t, days)
    #expect(!plan.summary.hasWork)
    #expect(t.allFiles() == first)
}

@Test func untickingVideoSkipsAllItsSidecars() async throws {
    let f = ImportFixture(days: ["DJI_0001.MP4": jan2])
    let video = try f.card.file("DJI_0001.MP4")
    try f.card.file("DJI_0001.SRT")
    try f.card.file("DJI_0001.LRV")
    let plan = try await f.plan().excluding([video.standardizedFileURL])
    #expect(plan.summary.totalToMove == 0)
}

/// Доступ до внутрішніх допоміжних функцій планувальника.
enum PlanBuilderNames {
    static func stems(_ stem: String, _ kind: FileKind) -> [String] {
        PlanBuilder.companionStems(for: stem, kind: kind)
    }
}
