import SwiftUI

enum Area: String, CaseIterable {
    case home = "Home folders"
    case library = "App data (~/Library)"
    case apps = "Applications"
    case system = "macOS & system"
    case free = "Free"

    var color: Color {
        switch self {
        case .home: return .blue
        case .library: return .purple
        case .apps: return .orange
        case .system: return .gray
        case .free: return Color.secondary.opacity(0.18)
        }
    }
}

struct UsageSlice: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let area: Area
    var path: String? = nil
}

struct FolderSize: Identifiable, Hashable {
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

    var color: Color { self == .safe ? .green : .orange }
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
