import Foundation

/// Тип файлу за розширенням — визначає, куди файл потрапить.
public enum FileKind: String, Sendable, CaseIterable {
    case raw       // RAW-фото → <дата>/raw/
    case sidecar   // .xmp → поруч зі своїм RAW
    case videoSidecar  // .gyroflow → поруч зі своїм відео
    case photo     // JPG/HEIC/PNG → <дата>/
    case psd       // Photoshop → <дата>/PSD/
    case video     // → <дата>/video/
    case junk      // службові файли Canon (.ctg, .cpf) → у кошик
    case other     // усе інше лишається на місці

    public static func of(_ url: URL) -> FileKind {
        of(extension: url.pathExtension)
    }

    public static func of(extension ext: String) -> FileKind {
        switch ext.lowercased() {
        case "cr3", "cr2", "crw", "raw", "dng", "raf", "nef", "nrw", "arw", "srf", "sr2",
             "orf", "srw", "rw2", "pef", "x3f", "3fr", "iiq", "rwl":
            return .raw
        case "xmp":
            return .sidecar
        case "gyroflow":
            return .videoSidecar
        case "jpg", "jpeg", "jpe", "jfif", "heic", "heif", "hif", "png":
            return .photo
        case "psd", "psb":
            return .psd
        case "mp4", "mov", "m4v", "avi", "mts", "m2ts", "mkv", "webm", "3gp":
            return .video
        case "ctg", "cpf":
            return .junk
        default:
            return .other
        }
    }

    /// Підпапка всередині папки з датою ("" — сама папка з датою).
    public var subfolder: String {
        switch self {
        case .raw, .sidecar: return "raw"
        case .video, .videoSidecar: return "video"
        case .psd: return "PSD"
        default: return ""
        }
    }

    /// Чи має цей тип дату зйомки, за якою його сортуємо.
    public var isSortable: Bool {
        switch self {
        case .raw, .sidecar, .videoSidecar, .photo, .psd, .video: return true
        case .junk, .other: return false
        }
    }

    /// Супровідний файл, який іде за основним (.xmp за RAW, .gyroflow за відео).
    public var isSidecar: Bool { self == .sidecar || self == .videoSidecar }
}
