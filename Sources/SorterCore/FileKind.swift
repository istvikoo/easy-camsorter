import Foundation

/// Тип файлу — визначає, куди файл потрапить.
public enum FileKind: String, Sendable, CaseIterable {
    case raw           // RAW-фото → <дата>/raw/
    case sidecar       // .xmp → поруч зі своїм RAW
    case photo         // JPG/HEIC/PNG → <дата>/
    case psd           // Photoshop → <дата>/PSD/
    case video         // → <дата>/video/
    case videoSidecar  // .gyroflow → поруч зі своїм відео
    case thumbnail     // .thm (мініатюра відео Canon/GoPro) → поруч з відео
    case videoMeta     // .xml (Sony), .srt (DJI) → поруч з відео; лише якщо відео знайдено
    case proxy         // .lrv (проксі GoPro/DJI) → <дата>/video/proxy/
    case gyroLog       // *_mix.bin (гіро-логи NiYien) → <дата>/video/gyro/
    case junk          // службові файли Canon (.ctg, .cpf) → у кошик
    case other         // усе інше лишається на місці

    public static func of(_ url: URL) -> FileKind {
        // Гіро-логи NiYien впізнаємо за назвою: розширення .bin надто загальне.
        if url.lastPathComponent.lowercased().hasSuffix("_mix.bin") { return .gyroLog }
        return of(extension: url.pathExtension)
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
        case "thm":
            return .thumbnail
        case "xml", "srt":
            return .videoMeta
        case "lrv":
            return .proxy
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
        case .video, .videoSidecar, .thumbnail, .videoMeta: return "video"
        case .proxy: return "video/proxy"
        case .gyroLog: return "video/gyro"
        case .psd: return "PSD"
        case .photo, .junk, .other: return ""
        }
    }

    /// Чи сортуємо цей тип за датою.
    public var isSortable: Bool {
        switch self {
        case .junk, .other: return false
        default: return true
        }
    }

    /// Супровідний файл, який іде за основним (RAW або відео).
    public var isSidecar: Bool {
        switch self {
        case .sidecar, .videoSidecar, .thumbnail, .videoMeta, .proxy: return true
        default: return false
        }
    }

    /// Супровідний файл саме відео.
    public var followsVideo: Bool {
        switch self {
        case .videoSidecar, .thumbnail, .videoMeta, .proxy: return true
        default: return false
        }
    }

    /// .xml і .srt бувають і не від камери — беремо їх, лише якщо знайшлося відео з такою назвою.
    public var requiresCompanion: Bool { self == .videoMeta }

    /// Чи варто попереджати, коли для файлу взято дату зміни файлу.
    /// Для супровідних файлів відео дата зйомки не важлива.
    public var needsCaptureDate: Bool {
        switch self {
        case .raw, .sidecar, .photo, .psd, .video: return true
        default: return false
        }
    }
}
