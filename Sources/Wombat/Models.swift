import SwiftUI

enum Area: String, CaseIterable, Codable {
    case home = "Home folders"
    case library = "App data (~/Library)"
    case apps = "Applications"
    case system = "macOS & system"
    case free = "Free"

    /// The same colours as the icon and the website's usage bar.
    var color: Color {
        switch self {
        case .home: return Color(hex: 0x4287ff)
        case .library: return Color(hex: 0xa865f0)
        case .apps: return Color(hex: 0xffa040)
        case .system: return Color(hex: 0x96959e)
        case .free: return Theme.free
        }
    }
}

struct UsageSlice: Identifiable, Codable {
    var id = UUID()
    let name: String
    let bytes: Int64
    let area: Area
    var path: String? = nil
}

struct FolderSize: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let bytes: Int64
}

extension Array where Element == FolderSize {
    var total: Int64 { reduce(0) { $0 + $1.bytes } }
}

enum Risk: String {
    case safe = "Safe"
    case check = "Check first"

    var color: Color { self == .safe ? Theme.green : Theme.orange }
}

/// What a scan measures. The project search walks the whole home folder, so it's slow and optional.
enum ScanKind: String, CaseIterable, Codable, Identifiable {
    case overview
    case projects
    case everything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Disk overview"
        case .projects: return "Projects"
        case .everything: return "Everything"
        }
    }

    var detail: String {
        switch self {
        case .overview: return "Your home folder, ~/Library, apps, Xcode and Homebrew. Fills the usage bar, the folder lists and the cleanup list."
        case .projects: return "Searches your home folder for node_modules and Composer vendor folders. The slow one on big drives."
        case .everything: return "The disk overview, then the project search."
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .projects: return "shippingbox"
        case .everything: return "square.stack.3d.down.right"
        }
    }

    var includesOverview: Bool { self != .projects }
    var includesProjects: Bool { self != .overview }
}

enum FolderKind: String, Identifiable {
    case nodeModules
    case vendor

    var id: String { rawValue }

    var title: String {
        self == .nodeModules ? "node_modules folders" : "Composer vendor folders"
    }

    var note: String {
        self == .nodeModules
            ? "Dependencies installed by npm, yarn or pnpm. Pick the projects you're not actively working on."
            : "PHP dependencies installed by Composer. Pick the projects you're not actively working on."
    }

    var restore: String {
        self == .nodeModules
            ? "They are deleted permanently. Run npm install (or yarn / pnpm install) in a project to bring them back."
            : "They are deleted permanently. Run composer install in a project to bring them back."
    }
}

enum CleanupAction {
    case emptyTrash
    case deleteContents(String)
    case deletePaths([String])
    case shell(String)
    case reveal(String)
    case pickFolders(FolderKind)
}

struct CleanupItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64
    let risk: Risk
    let action: CleanupAction
    /// Command-line equivalent, shown in monospace under the description.
    var command: String? = nil
    /// The size is an upper bound (e.g. a whole data folder), so it is left out of the totals.
    var upTo = false

    var symbol: String {
        switch id {
        case "trash": return "trash"
        case "caches": return "archivebox"
        case "npm": return "shippingbox"
        case "docker": return "cube"
        case "phpls": return "chevron.left.forwardslash.chevron.right"
        case "simdevices", "simruntimes": return "iphone"
        case "devicesupport": return "cable.connector"
        case "derived": return "hammer"
        case "mail": return "envelope"
        case "downloads": return "arrow.down.circle"
        case "ollama": return "brain"
        case "node_modules", "vendor": return "shippingbox.fill"
        default: return "folder"
        }
    }

    var confirmText: String {
        switch action {
        case .emptyTrash: return "Everything in the Trash is deleted permanently."
        case .deleteContents(let dir): return "Deletes everything inside \(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~")). \(detail)"
        case .deletePaths: return detail
        case .shell(let cmd): return "\(detail)\n\nRuns: \(cmd)"
        case .reveal, .pickFolders: return detail
        }
    }
}
